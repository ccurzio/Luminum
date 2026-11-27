#
# Luminum::P2P
#
# Server-side P2P file distribution (docs/p2p.md). Phase 3 is the seed
# path: the broker mints a server-only transfer grant for a deploy
# command, pushes the package files to the target over the client's
# inbound data channel (10704, protocol 8.3/8.4), and folds the
# terminal transfer reports back into the token and holder tables.
#
# The grant is a signed envelope (protocol 5) and is self-authenticating:
# the requester verifies it under the server signing key it already holds,
# so no out-of-band channel is needed to validate a transfer.
#
# Peer-channel session (protocol 8.4), server as source:
#   S -- grant frame (the minted p2pgrant envelope, verbatim) -->
#   S <-- core/p2pfetch resp {token, status, files} -----------
#   for each file in grant order:
#   S <-- core/p2pfetch req {token, fileid} -------------------
#   S --> core/p2pfetch resp {token, fileid, status, size} ----
#   S --> raw chunks (4B big-endian length + bytes, <= 1 MiB) --
#   S --> zero-length frame (EOF) -----------------------------
#
# Envelopes are signed by their sender: the grant by the server (the
# requester's key anchor), the p2pfetch req/resp by the client (verified
# here against the stored AUTH.PUBKEY) or the server (verified by the
# client against its SRVPUB).
#

package Luminum::P2P;

use strict;
use warnings;

use JSON::PP;
use IO::Socket::INET;
use IO::Socket::SSL qw(SSL_VERIFY_PEER);
use Net::SSLeay;
use Luminum::Protocol;
use Luminum::Repo;
use Luminum::Cert;

our $VERSION = "0.0.1";

# Grant lifetime (protocol 9.3 v1.1): 300 s, fixed.
use constant GRANT_SECS => 300;
# Maximum raw chunk on the data channel (docs/p2p.md 6): 1 MiB.
use constant CHUNK_SIZE => 1024 * 1024;
# The client's inbound data port (protocol 2): the seed path.
use constant IPORT => 10704;
# Connect/handshake and per-frame I/O bounds for the push session.
use constant CONNECT_TIMEOUT_SECS => 30;
use constant IO_TIMEOUT_SECS => 60;

# --- Grant minting ------------------------------------------------------------

# Mint a transfer grant for one deploy target (docs/p2p.md 5, 7.1).
# Phase 3 mints the seed form: a single server entry in the source list
# (uid 0, the server's address, port 10704).
#
#   mint_grant(contentdbh => ..., dbh => ..., seed => ..., uid => ...,
#              pkgid => ..., os => ..., aid => ..., server_ip => ..., log => ...)
#
# $dbh is the CLIENTS database (P2PTOKENS), $contentdbh the CONTENT
# database (PKGFILES, FILES). Returns (1, $grant_env, $token) on success
# or (0, $reason) when the package has no files attached for the OS.
sub mint_grant {
	my (%a) = @_;
	my $log = $a{log} || sub { };
	my $uid = $a{uid};
	my $pkgid = $a{pkgid};
	my $os = $a{os};
	return (0, "missing grant parameters")
		unless defined $uid && $uid =~ /^[0-9]+$/ && defined $pkgid && $pkgid =~ /^[0-9]+$/ && defined $os && length $os;

	# The grant covers one package revision for one OS: the full per-file
	# list, so a multi-file package is one grant and one session.
	my $sth = $a{contentdbh}->prepare(qq{
		select f.ID, pf.PATH, f.SIZE, f.SHA256
		from PKGFILES pf
		join FILES f on f.ID = pf.FILEID
		where pf.PKGID = ? and pf.OS = ?
		order by pf.ID
	});
	$sth->execute($pkgid, $os)
		or return (0, "cannot read the package file list: " . $a{contentdbh}->errstr);
	my @files;
	while (my ($fileid, $path, $size, $sha) = $sth->fetchrow_array()) {
		push @files, { fileid => 0 + $fileid, path => $path, size => 0 + $size, sha256 => $sha };
	}
	return (0, "no files attached to package $pkgid for OS $os") unless @files;

	my $ts = time();
	my $exp = $ts + GRANT_SECS;
	my $token = Luminum::Protocol::new_uuid4();
	my $sources = [ { uid => 0, ip => $a{server_ip} // "", port => IPORT } ];

	my $env = Luminum::Protocol::new_envelope(
		src => "server", uid => $uid, lumy => "core", action => "p2pgrant", status => "OK",
		data => {
			token => $token,
			pkgid => 0 + $pkgid,
			os => $os,
			aid => $a{aid},
			files => \@files,
			sources => $sources,
			exp => $exp,
		},
	);
	Luminum::Protocol::sign_envelope($env, $a{seed});

	# Record the single-use grant (protocol 7.3): the token is consumed on
	# completion (p2p_fetch_ok) or a failed walk (p2p_fetch_fail), and the
	# broker sweep prunes expired unused rows.
	$a{dbh}->do(
		"insert into P2PTOKENS (TOKEN,PKGID,REQUID,SOURCES,EXPIRES) values (?,?,?,?,from_unixtime(?))",
		undef, $token, $pkgid, $uid, JSON::PP->new->canonical->encode($sources), $exp
	)
		or return (0, "P2PTOKENS insert failed: " . $a{dbh}->errstr);
	$log->("p2p: minted grant $token for UID $uid (package $pkgid, " . scalar(@files) . " file(s), seed path)");
	return (1, $env, $token);
}

# --- The push session (server -> client, 10704) --------------------------------

# Read exactly $n bytes from a socket. Returns undef on EOF/error.
sub _read_exact {
	my ($s, $n) = @_;
	my $buf = "";
	while (length($buf) < $n) {
		my $rc = sysread($s, $buf, $n - length($buf), length($buf));
		return undef unless $rc;
	}
	return $buf;
}

# Read one length-prefixed frame and decode its envelope. Returns the
# envelope hashref, or undef on failure (protocol 8.2).
sub _read_frame {
	my ($s) = @_;
	my $lenbuf = _read_exact($s, 4) or return undef;
	my ($len) = unpack("N", $lenbuf);
	return undef if $len == 0 || $len > 16 * 1024 * 1024;
	my $payload = _read_exact($s, $len) or return undef;
	my ($ok, $env) = Luminum::Protocol::frame_decode($lenbuf . $payload);
	return $ok ? $env : undef;
}

# Write $bytes exactly (a full syswrite loop).
sub _write_all {
	my ($s, $bytes) = @_;
	my $off = 0;
	while ($off < length($bytes)) {
		my $rc = syswrite($s, $bytes, length($bytes) - $off, $off);
		return 0 unless $rc;
		$off += $rc;
	}
	return 1;
}

# Write one length-prefixed frame of raw bytes (a data chunk, or the
# zero-length EOF marker). Envelope frames are already framed by
# Luminum::Protocol::frame_encode and go through _write_all directly.
sub _write_frame {
	my ($s, $bytes) = @_;
	return _write_all($s, pack("N", length($bytes)) . $bytes);
}

# The subject CN of the peer certificate (undef on parse failure).
# IO::Socket::SSL's peer_certificate() returns the Net::SSLeay X509
# object (a scalar handle) in current builds and PEM text in older
# ones - handle both. The object form is cached by the socket, so it
# is not freed here.
sub _cert_cn {
	my ($cert) = @_;
	return undef unless defined $cert && length "$cert";
	my $line;
	if ($cert =~ /^-----BEGIN CERTIFICATE-----/) {
		my $bio = Net::SSLeay::BIO_new(Net::SSLeay::BIO_s_mem());
		Net::SSLeay::BIO_write($bio, $cert);
		my $x = Net::SSLeay::PEM_read_bio_X509($bio);
		Net::SSLeay::BIO_free($bio);
		return undef unless $x;
		$line = Net::SSLeay::X509_NAME_oneline(Net::SSLeay::X509_get_subject_name($x));
		Net::SSLeay::X509_free($x);
	} else {
		$line = Net::SSLeay::X509_NAME_oneline(Net::SSLeay::X509_get_subject_name($cert));
	}
	return undef unless defined $line && $line =~ m{(?:^|/)CN=([^/,]+)};
	return $1;
}

# Push a minted grant to its requester over the requester's inbound data
# channel (10704) and serve the session (protocol 8.3, 8.4).
#
#   push_grant(grant => $env, uid => ..., ip => ..., seed => ...,
#              sslcert => ..., sslprvkey => ..., clpubraw => ...,
#              content_root => ..., log => ...)
#
# $seed is the server signing seed (the per-file p2pfetch responses are
# signed with it; the client verifies them against its SRVPUB).
#
# $clpubraw is the requester's raw 32-byte Ed25519 public key
# (CLIENTS.AUTH.PUBKEY, SPKI-decoded); its p2pfetch envelopes are verified
# against it. Returns (1) when the whole session completed, (0, $reason)
# otherwise. Run in a forked child: the session is blocking and can last
# as long as the package download timeout.
sub push_grant {
	my (%a) = @_;
	my $log = $a{log} || sub { };
	my $grant = $a{grant};
	my $uid = $a{uid};
	my $ip = $a{ip};
	my $token = $grant->{data}{token};
	my $files = $grant->{data}{files};
	return (0, "malformed grant") unless ref($files) eq "ARRAY" && @$files;

	my $s = IO::Socket::SSL->new(
		PeerAddr => "$ip:" . IPORT,
		Timeout => CONNECT_TIMEOUT_SECS,
		SSL_cert_file => $a{sslcert},
		SSL_key_file => $a{sslprvkey},
		SSL_ca_file => (Luminum::Cert::ca_material($a{sslcert}, $a{sslprvkey}))[0],
		SSL_verify_mode => SSL_VERIFY_PEER,
		# Hostname verification is replaced by the channel-identity check
		# below (chain-to-root + the certificate CN bound to the grant's
		# UID, docs/p2p.md 4.4): peers are addressed by IP, and the client
		# certificate carries no SAN for that IP.
		SSL_verifycn_scheme => "none",
	);
	unless ($s) {
		my $err = $! || ($IO::Socket::SSL::SSL_ERROR // "unknown TLS error");
		return (0, "cannot reach $ip:" . IPORT . " ($err)");
	}
	# Bound the per-frame I/O so a wedged session cannot hang the child.
	{
		use Socket;
		my $tv = pack("l2", IO_TIMEOUT_SECS, 0);
		setsockopt($s, SOL_SOCKET, SO_RCVTIMEO, $tv);
		setsockopt($s, SOL_SOCKET, SO_SNDTIMEO, $tv);
	}

	# The channel identity is bound to the grant: the peer must present the
	# certificate the server issued for this UID (CN = luminum-client-{UID},
	# docs/p2p.md 4.2).
	my $peer_cert = $s->peer_certificate();
	my $cn = defined $peer_cert ? _cert_cn($peer_cert) : undef;
	if (!defined $cn || $cn ne "luminum-client-$uid") {
		$log->("p2p: push to $ip rejected: peer certificate CN " . (defined $cn ? "\"$cn\"" : "missing") . " != luminum-client-$uid");
		close($s);
		return (0, "PEER_CERT_MISMATCH");
	}

	# Present the grant (server-signed, forwarded verbatim). frame_encode
	# returns the complete length-prefixed frame.
	my $frame = Luminum::Protocol::frame_encode($grant);
	unless (defined $frame && _write_all($s, $frame)) {
		close($s);
		return (0, "grant frame write failed");
	}

	# Handshake response: the client's signed p2pfetch envelope.
	my $resp = _read_frame($s);
	unless ($resp && $resp->{action} eq "p2pfetch" && $resp->{status} eq "OK"
		&& (ref($resp->{data}) eq "HASH") && $resp->{data}{token} eq $token) {
		close($s);
		return (0, "client handshake refused or malformed");
	}
	unless (Luminum::Protocol::verify_envelope($resp, $a{clpubraw})) {
		$log->("p2p: push to $ip: handshake signature verification failed");
		close($s);
		return (0, "BAD_SIGNATURE");
	}

	# Serve the files in grant order.
	my $served = 0;
	for my $file (@$files) {
		my $req = _read_frame($s);
		unless ($req && $req->{action} eq "p2pfetch" && (ref($req->{data}) eq "HASH")
			&& $req->{data}{token} eq $token && $req->{data}{fileid} == $file->{fileid}) {
			close($s);
			return (0, "per-file request out of sequence or malformed");
		}
		unless (Luminum::Protocol::verify_envelope($req, $a{clpubraw})) {
			$log->("p2p: push to $ip: per-file request signature verification failed");
			close($s);
			return (0, "BAD_SIGNATURE");
		}
		my $path = Luminum::Repo::store_path($a{content_root}, $file->{sha256});
		my $fh;
		unless (open($fh, "<:raw", $path)) {
			$log->("p2p: push to $ip: repository file missing for fileid $file->{fileid} ($path)");
			close($s);
			return (0, "FILE_MISSING");
		}
		my $okresp = Luminum::Protocol::new_envelope(
			src => "server", uid => $uid, lumy => "core", action => "p2pfetch", status => "OK",
			data => { token => $token, fileid => $file->{fileid}, size => $file->{size} },
		);
		Luminum::Protocol::sign_envelope($okresp, $a{seed});
		my $okframe = Luminum::Protocol::frame_encode($okresp);
		unless (defined $okframe && _write_all($s, $okframe)) {
			close($fh);
			close($s);
			return (0, "per-file response write failed");
		}
		my $buf;
		while (read($fh, $buf, CHUNK_SIZE)) {
			unless (_write_frame($s, $buf)) {
				close($fh);
				close($s);
				return (0, "chunk write failed (client disconnected?)");
			}
		}
		close($fh);
		unless (_write_frame($s, "")) {   # zero-length frame: EOF
			close($s);
			return (0, "EOF frame write failed");
		}
		$served++;
	}
	close($s);
	$log->("p2p: push to $ip completed ($served file(s), grant $token)");
	return (1);
}

# --- Terminal report handling ---------------------------------------------------

# Fold a terminal transfer report (protocol 6.1 v1.1) into the bookkeeping
# tables. $data is the report's data field:
#   p2p_fetch_ok:   {event, token, pkgid, srcuid, files: [fileids]}
#   p2p_fetch_fail: {event, token, pkgid, srcuid, err}
#
# The token is consumed on completion, not on start (docs/p2p.md 5.2): a
# successful walk upserts the requester as a holder for every file in the
# grant; a failed walk (every source exhausted) consumes the grant so the
# replacement mint starts clean.
sub on_report {
	my ($dbh, $contentdbh, $uid, $data, $log) = @_;
	$log = $log || sub { };
	my $event = $data->{event} // "";
	return unless $event eq "p2p_fetch_ok" || $event eq "p2p_fetch_fail";
	my $token = $data->{token};
	return $log->("p2p: $event from UID $uid without a token; ignored")
		unless defined $token && $token =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

	my $sth = $dbh->prepare("select REQUID, USED from P2PTOKENS where TOKEN = ?");
	$sth->execute($token);
	my ($requid, $used) = $sth->fetchrow_array();
	if (!defined $requid) {
		$log->("p2p: $event from UID $uid for unknown token $token (expired and swept?); ignored");
		return;
	}
	if ($requid != $uid) {
		$log->("p2p: $event from UID $uid for a token minted for UID $requid; ignored");
		return;
	}
	unless ($used) {
		$dbh->do("update P2PTOKENS set USED = now() where TOKEN = ?", undef, $token);
	}

	if ($event eq "p2p_fetch_ok") {
		my $srcuid = $data->{srcuid};
		my $source = (defined $srcuid && "$srcuid" =~ /^[0-9]+$/ && 0 + $srcuid != 0) ? 0 + $srcuid : "server";
		my $files = (ref($data->{files}) eq "ARRAY") ? $data->{files} : [];
		my $ins = $contentdbh->prepare(qq{
			insert into PKGHOLDERS (FILEID,UID,SOURCE,TS) values (?,?,?,now())
			on duplicate key update SOURCE = values(SOURCE), TS = now()
		});
		my $n = 0;
		for my $fileid (@$files) {
			next unless defined $fileid && "$fileid" =~ /^[0-9]+$/;
			$ins->execute(0 + $fileid, $uid, $source) or do {
				$log->("p2p: PKGHOLDERS upsert failed for fileid $fileid: " . $contentdbh->errstr);
				next;
			};
			$n++;
		}
		$log->("p2p: UID $uid completed grant $token ($n file(s) held, source $source)");
	}
	else {
		$log->("p2p: UID $uid failed grant $token: " . ($data->{err} // "no reason given"));
	}
}

1;
