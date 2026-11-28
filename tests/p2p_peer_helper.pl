#!/usr/bin/perl
#
# p2p_peer_helper.pl - a stand-in peer for the 10464 P2P channel
# (docs/p2p.md 8.4), used by tests/p2p_peer_test.sh.
#
# Two real Luminum clients cannot run on one host (both bind the fixed
# 10704/10464 ports on the local IP), so the test runs one real client in a
# role and this helper in the other:
#
#   mode = requester  - dial a source's 10464, present a server-signed grant,
#                       receive the files, verify size + SHA-256. Used to
#                       exercise the real client's SERVING side
#                       (handle_peer_session) and its source-side rejections.
#
#   mode = source     - listen on 10464, accept one mutual-TLS connection,
#                       read the grant, run the source-side checklist, and
#                       serve the files from disk. Used to exercise the real
#                       client's FETCHER (fetch_from_source / p2p_fetch_walk).
#
# The wire protocol is the same in both roles (protocol 8.4):
#   requester -- grant frame (the minted p2pgrant envelope, verbatim) -->
#   requester <-- core/p2pfetch resp {token, status, files:[sizes]} ----
#   for each file in grant order:
#   requester -- core/p2pfetch req {token, fileid} --------------------
#   requester <-- core/p2pfetch resp {token, fileid, status, size} ----
#   requester <-- raw chunks (4B big-endian length + bytes, <= 1 MiB) --
#   requester <-- zero-length frame (EOF) -----------------------------
#
# Envelopes are signed by their sender. On 10464 neither side re-verifies the
# other's per-file signatures (identity is bound by the mutual-TLS channel,
# docs/p2p.md 4.2); the grant is verified server-signed by both.
#
# Usage: perl tests/p2p_peer_helper.pl <requester|source> <config.json>
#
# The config JSON carries the TLS material paths, the signing seed, the
# source list, and the file list. Prints a single result line to stdout:
#   OK ...            on success
#   REFUSED: <code>   a source-side refusal (requester mode)
#   <CODE>: ...       a transport/validation failure
# Exit code 0 on OK, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use JSON::PP;
use IO::Socket::INET;
use IO::Socket::SSL qw(SSL_VERIFY_PEER);
use Net::SSLeay;
use Digest::SHA qw(sha256_hex);

my $REPO = "$Bin/..";
unshift @INC, "$REPO/server/lib";
require Luminum::Protocol;

my ($mode, $cfgfile) = @ARGV;
die "usage: p2p_peer_helper.pl <requester|source> <config.json>\n"
    unless $mode && $cfgfile && -f $cfgfile;
open(my $cf, "<", $cfgfile) or die "cannot read config: $!";
my $cfg = JSON::PP->new->utf8->decode(do { local $/; <$cf> });
close($cf);

# --- raw material -------------------------------------------------------------
sub read_seed {
    my ($path) = @_;
    open(my $fh, "<:raw", $path) or die "cannot read seed $path: $!";
    my $b; read($fh, $b, 32) == 32 or die "short seed";
    close($fh);
    return $b;
}
sub read_pub {
    my ($path) = @_;
    open(my $fh, "<:raw", $path) or die "cannot read pubkey $path: $!";
    my $b; read($fh, $b, 32) == 32 or die "short pubkey";
    close($fh);
    return $b;
}

# --- framing (mirrors Luminum::P2P) ------------------------------------------
sub _read_exact {
    my ($s, $n) = @_;
    my $buf = "";
    while (length($buf) < $n) {
        my $rc = sysread($s, $buf, $n - length($buf), length($buf));
        return undef unless $rc;
    }
    return $buf;
}
sub _read_frame {
    my ($s) = @_;
    my $lenbuf = _read_exact($s, 4) or return undef;
    my ($len) = unpack("N", $lenbuf);
    return undef if $len == 0 || $len > 16 * 1024 * 1024;
    my $payload = _read_exact($s, $len) or return undef;
    my ($ok, $env) = Luminum::Protocol::frame_decode($lenbuf . $payload);
    return $ok ? $env : undef;
}
sub _read_raw_frame {
    my ($s) = @_;
    my $lenbuf = _read_exact($s, 4) or return undef;
    my ($len) = unpack("N", $lenbuf);
    return "" if $len == 0;          # zero-length frame: EOF
    return undef if $len > 16 * 1024 * 1024;
    return _read_exact($s, $len);
}
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
sub _write_frame {
    my ($s, $bytes) = @_;
    return _write_all($s, pack("N", length($bytes)) . $bytes);
}

# The subject CN of a peer certificate (IO::Socket::SSL returns a Net::SSLeay
# X509 object in current builds, PEM text in older ones - handle both).
sub _cert_cn {
    my ($cert) = @_;
    return undef unless defined $cert && length "$cert";
    my $x;
    if ($cert =~ /^-----BEGIN CERTIFICATE-----/) {
        my $bio = Net::SSLeay::BIO_new(Net::SSLeay::BIO_s_mem());
        Net::SSLeay::BIO_write($bio, $cert);
        $x = Net::SSLeay::PEM_read_bio_X509($bio);
        Net::SSLeay::BIO_free($bio);
    } else {
        $x = $cert;
    }
    return undef unless $x;
    my $line = Net::SSLeay::X509_NAME_oneline(Net::SSLeay::X509_get_subject_name($x));
    return undef unless defined $line && $line =~ m{(?:^|/)CN=([^/,]+)};
    return $1;
}

# Build a server-signed transfer grant. $cfg->{token} fixes the token (the
# replay test reuses one); otherwise a fresh UUIDv4 is minted.
sub build_grant {
    my ($cfg) = @_;
    my $seed = read_seed($cfg->{seed});
    my $token = $cfg->{token} // Luminum::Protocol::new_uuid4();
    # The client's Envelope decodes uid as a String (the server mints it from
    # the string target), so the grant's uid must be a JSON string.
    my $env = Luminum::Protocol::new_envelope(
        src => "server", uid => "$cfg->{uid}", lumy => "core", action => "p2pgrant", status => "OK",
        data => {
            token => $token,
            pkgid => 0 + $cfg->{pkgid},
            os => "Linux",
            aid => $cfg->{aid} // "peer-test",
            files => $cfg->{files},
            sources => $cfg->{sources},
            exp => time() + 300,
        },
    );
    Luminum::Protocol::sign_envelope($env, $seed);
    return ($env, $token);
}

# --- requester role -----------------------------------------------------------
sub run_requester {
    my ($cfg) = @_;
    my $seed = read_seed($cfg->{seed});
    my ($grant, $token) = build_grant($cfg);

    my $s = IO::Socket::SSL->new(
        PeerAddr => $cfg->{ip} . ":" . $cfg->{port},
        Timeout => 30,
        SSL_cert_file => $cfg->{crt},
        SSL_key_file => $cfg->{key},
        SSL_ca_file => $cfg->{ca},
        SSL_verify_mode => SSL_VERIFY_PEER,
        SSL_verifycn_scheme => "none",
    );
    unless ($s) {
        my $err = $! || ($IO::Socket::SSL::SSL_ERROR // "unknown TLS error");
        return ("CONNECT_FAILED: $err", 1);
    }
    {
        use Socket;
        my $tv = pack("l2", 60, 0);
        setsockopt($s, SOL_SOCKET, SO_RCVTIMEO, $tv);
        setsockopt($s, SOL_SOCKET, SO_SNDTIMEO, $tv);
    }

    unless (defined Luminum::Protocol::frame_encode($grant)
            && _write_all($s, Luminum::Protocol::frame_encode($grant))) {
        close($s);
        return ("GRANT_WRITE_FAILED", 1);
    }
    my $resp = _read_frame($s);
    unless ($resp && $resp->{action} eq "p2pfetch") {
        close($s);
        return ("BAD_HANDSHAKE", 1);
    }
    if ($resp->{status} ne "OK") {
        close($s);
        return ("REFUSED: " . ($resp->{err} // "UNKNOWN"), 1);
    }
    my @shas;
    for my $file (@{$cfg->{files}}) {
        my $req = Luminum::Protocol::new_envelope(
            src => "client", uid => "$cfg->{uid}", lumy => "core", action => "p2pfetch", status => "OK",
            data => { token => $token, fileid => 0 + $file->{fileid} },
        );
        Luminum::Protocol::sign_envelope($req, $seed);
        unless (_write_all($s, Luminum::Protocol::frame_encode($req))) {
            close($s);
            return ("REQ_WRITE_FAILED", 1);
        }
        my $okresp = _read_frame($s);
        unless ($okresp && $okresp->{action} eq "p2pfetch" && $okresp->{status} eq "OK") {
            close($s);
            return ("BAD_FILE_RESP", 1);
        }
        my $buf = "";
        while (1) {
            my $chunk = _read_raw_frame($s);
            return ("STREAM_ERROR", 1) unless defined $chunk;
            last if length($chunk) == 0;
            $buf .= $chunk;
        }
        my $digest = sha256_hex($buf);
        if (length($buf) != $file->{size} || $digest ne $file->{sha256}) {
            close($s);
            return ("HASH_MISMATCH: fileid=$file->{fileid}", 1);
        }
        push @shas, $digest;
    }
    close($s);
    return ("OK token=$token " . join(" ", map { "sha=" . $_ } @shas), 0);
}

# --- source role --------------------------------------------------------------
sub run_source {
    my ($cfg) = @_;
    my $seed = read_seed($cfg->{seed});
    my $srvpub = read_pub($cfg->{srvpub});

    # SSL listener with a DEFERRED handshake (SSL_startHandshake => 0), the
    # same pattern as broker.pl's bootstrap listener: accept() performs only
    # the plain TCP accept, and accept_SSL() does the mutual-TLS handshake
    # per connection (verifying the requester's certificate against the CA).
    my $listener = IO::Socket::SSL->new(
        LocalAddr => $cfg->{ip}, LocalPort => $cfg->{port},
        Proto => "tcp", Listen => 5, ReuseAddr => 1,
        SSL_cert_file => $cfg->{crt},
        SSL_key_file => $cfg->{key},
        SSL_ca_file => $cfg->{ca},
        SSL_verify_mode => SSL_VERIFY_PEER,
        SSL_verifycn_scheme => "none",
        SSL_startHandshake => 0,
    );
    unless ($listener) {
        return ("LISTEN_FAILED: " . ($! || $IO::Socket::SSL::SSL_ERROR), 1);
    }
    # Accept connections until one completes the mutual-TLS handshake: a
    # probe or stray connection that does not speak TLS is skipped, so the
    # test's readiness check cannot consume the real requester's session.
    # Bounded so a wedged source cannot hang the test.
    my $deadline = time() + 180;
    my $s;
    while (time() < $deadline) {
        my $rin = "";
        vec($rin, fileno($listener), 1) = 1;
        my $n = select($rin, my $wout = "", my $eout = "", $deadline - time());
        next unless $n;
        my $client = $listener->accept();
        next unless $client;
        $client->blocking(1);
        $client->timeout(60);
        my $ok = eval { $client->accept_SSL() };
        if ($ok && !$@) {
            $s = $client;
            last;
        }
        close($client);
    }
    unless ($s) {
        close($listener);
        return ("TLS_ACCEPT_TIMEOUT", 1);
    }
    {
        use Socket;
        my $tv = pack("l2", 60, 0);
        setsockopt($s, SOL_SOCKET, SO_RCVTIMEO, $tv);
        setsockopt($s, SOL_SOCKET, SO_SNDTIMEO, $tv);
    }

    my $grant = _read_frame($s);
    unless ($grant && $grant->{action} eq "p2pgrant" && (ref($grant->{data}) eq "HASH")) {
        close($s); close($listener);
        return ("BAD_GRANT_FRAME", 1);
    }
    my $token = $grant->{data}{token};

    # Channel identity: the requester's certificate CN must equal the grant's
    # requester UID (docs/p2p.md 4.2).
    my $cn = _cert_cn($s->peer_certificate());
    if (!defined $cn || $cn ne "luminum-client-" . $cfg->{req_uid}) {
        close($s); close($listener);
        return ("UID_MISMATCH: " . (defined $cn ? $cn : "missing"), 1);
    }
    # The grant is server-signed.
    unless (Luminum::Protocol::verify_envelope($grant, $srvpub)) {
        close($s); close($listener);
        return ("BAD_SIGNATURE", 1);
    }

    my $sizes = [ map { 0 + $_->{size} } @{$cfg->{files}} ];
    my $resp = Luminum::Protocol::new_envelope(
        src => "client", uid => "$cfg->{src_uid}", lumy => "core", action => "p2pfetch", status => "OK",
        data => { token => $token, files => $sizes },
    );
    Luminum::Protocol::sign_envelope($resp, $seed);
    unless (_write_all($s, Luminum::Protocol::frame_encode($resp))) {
        close($s); close($listener);
        return ("HANDSHAKE_WRITE_FAILED", 1);
    }

    my $served = 0;
    for my $file (@{$cfg->{files}}) {
        my $req = _read_frame($s);
        unless ($req && $req->{action} eq "p2pfetch" && (ref($req->{data}) eq "HASH")
                && $req->{data}{token} eq $token && $req->{data}{fileid} == $file->{fileid}) {
            close($s); close($listener);
            return ("BAD_REQ", 1);
        }
        my $size = (-s $file->{disk}) // 0;
        my $okresp = Luminum::Protocol::new_envelope(
            src => "client", uid => "$cfg->{src_uid}", lumy => "core", action => "p2pfetch", status => "OK",
            data => { token => $token, fileid => 0 + $file->{fileid}, size => $size },
        );
        Luminum::Protocol::sign_envelope($okresp, $seed);
        unless (_write_all($s, Luminum::Protocol::frame_encode($okresp))) {
            close($s); close($listener);
            return ("OKRESP_WRITE_FAILED", 1);
        }
        my $fh;
        unless (open($fh, "<:raw", $file->{disk})) {
            close($s); close($listener);
            return ("FILE_OPEN_FAILED: $file->{disk}", 1);
        }
        my $buf;
        while (read($fh, $buf, 1024 * 1024)) {
            unless (_write_frame($s, $buf)) {
                close($fh); close($s); close($listener);
                return ("CHUNK_WRITE_FAILED", 1);
            }
        }
        close($fh);
        unless (_write_frame($s, "")) {
            close($s); close($listener);
            return ("EOF_WRITE_FAILED", 1);
        }
        $served++;
    }
    close($s); close($listener);
    return ("OK served=$served token=$token", 0);
}

my ($out, $rc) = ($mode eq "requester") ? run_requester($cfg) : run_source($cfg);
print "$out\n";
exit $rc;
