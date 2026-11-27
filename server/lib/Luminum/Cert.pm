#
# Luminum Certificate Module v0.0.1
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Client TLS certificate issuance (protocol 7.1 v1.1, docs/p2p.md 4.1).
# The P2P channel (10464) is mutual TLS: every endpoint presents a
# certificate the server issued, with subject CN = luminum-client-{UID} -
# the UID is the channel identity, and the serving peer requires
# peer-cert UID == grant requester UID so a transfer grant cannot be
# forwarded to a third party.
#
# The client generates a P-256 ECDSA keypair and CSR at first run (the
# private key never leaves the endpoint) and presents the CSR in the
# register request (tls_csr) or in a certrenew request (existing
# endpoints upgrading to P2P). This module validates the CSR and issues
# the certificate with the key that issued the server TLS certificate:
#   - generate mode: luminum-ca.crt / luminum-ca.key next to the server
#     certificate (the dedicated CA, protocol 7.1 shape)
#   - import mode: the server certificate's own key - the imported
#     certificate is its own trust anchor (mirrors the prepare_signing
#     fallback in Luminum::Setup)
# The issued certificate is verified before it is returned: subject,
# issuer, public key, and chain.
#
# Issuance shells out to the openssl CLI (the same binary the installer
# uses). `x509 -req -subj` - overriding the issued subject, which the
# client cannot know yet (the UID is assigned at registration) - requires
# OpenSSL 3.0 or newer; on older releases issuance is refused with a
# clear error and the registration completes without a clientcert (the
# client retries via certrenew on a later start).
#
# Known limitation (import mode): an imported anchor certificate without
# basicConstraints CA:TRUE cannot pass `openssl verify` as an issuer.
# That is expected and tolerated in import mode only - the P2P channel
# verifies with rustls on both ends, whose trust anchors are not subject
# to the CA:TRUE check (docs/p2p.md 4.4). In generate mode the CA always
# carries CA:TRUE and any chain failure is fatal.

package Luminum::Cert;

use strict;
use warnings;
use File::Temp qw(tempfile);
use File::Basename qw(dirname);

our $VERSION = "0.0.1";

# Issued certificate validity (protocol 7.1 v1.1: 1 year).
use constant CERT_DAYS => 365;

# Cached OpenSSL major.minor (undef = not yet checked).
my $openssl_ver;

# OpenSSL version as (major, minor), or (0, 0) when the binary is
# missing or unparseable.
sub openssl_version {
	return @$openssl_ver if defined $openssl_ver;
	my $out = `openssl version 2>/dev/null`;
	my @v = (0, 0);
	if ($out =~ /^OpenSSL (\d+)\.(\d+)/) { @v = ($1, $2); }
	$openssl_ver = \@v;
	return @v;
	}

# The issuing (anchor certificate, anchor key, mode) pair for the
# installed server certificate. Mode is 'ca' (the dedicated Luminum CA
# is present) or 'server' (import-mode fallback: the server certificate
# is its own anchor).
sub ca_material {
	my ($sslcert, $sslprvkey) = @_;
	my $ssldir = dirname($sslcert);
	my ($cacert, $cakey) = ("$ssldir/luminum-ca.crt", "$ssldir/luminum-ca.key");
	if (-e $cacert && -e $cakey) {
		return ($cacert, $cakey, "ca");
		}
	return ($sslcert, $sslprvkey, "server");
	}

# Validate a client CSR: it must parse, carry a valid request signature,
# and hold a P-256 EC public key. Returns (1, $pubkey_pem) or
# (0, $reason).
sub _check_csr {
	my ($csrfile) = @_;
	my $chk = `openssl req -in "$csrfile" -verify -noout 2>&1`;
	if ($? != 0 || $chk !~ /verify OK/i) {
		return (0, "invalid certificate signing request: " . trim($chk));
		}
	my $pub = `openssl req -in "$csrfile" -noout -pubkey 2>/dev/null`;
	return (0, "cannot extract the public key from the CSR") if $? != 0 || $pub eq "";
	# Key type from the CSR itself (the public key PEM cannot be piped
	# through /bin/sh -c: it starts with dashes, which sh takes as its
	# own options).
	my $txt = `openssl req -in "$csrfile" -noout -text 2>&1`;
	unless ($txt =~ /Public Key Algorithm: id-ecPublicKey/ && $txt =~ /Public-Key: \(256 bit\)/) {
		return (0, "the CSR key must be an EC P-256 key");
		}
	return (1, $pub);
	}

sub trim {
	my ($s) = @_;
	$s = "" unless defined $s;
	$s =~ s/^\s+|\s+$//g;
	return $s;
	}

# Collapse all whitespace (public key PEM comparison).
sub _flat {
	my ($s) = @_;
	$s = "" unless defined $s;
	$s =~ s/\s+//g;
	return $s;
	}

# Issue a client TLS certificate for a CSR (protocol 7.1 v1.1).
#
#   $csr_pem    PEM CSR from the client (tls_csr, base64-decoded)
#   $uid       numeric endpoint UID (the certificate subject)
#   $sslcert   installed server certificate path (SYSTEM.CONFIG SSLCERT)
#   $sslprvkey installed server private key path (SYSTEM.CONFIG SSLPRVKEY)
#   $log       coderef($msg), optional
#
# Returns (1, $cert_pem) on success, (0, $reason) on failure.
sub sign_client_csr {
	my ($csr_pem, $uid, $sslcert, $sslprvkey, $log) = @_;
	$log ||= sub { };
	return (0, "invalid UID") unless defined $uid && $uid =~ /^[0-9]+$/;
	return (0, "empty CSR") unless defined $csr_pem && $csr_pem =~ /-----BEGIN CERTIFICATE REQUEST-----/;

	my ($maj, $min) = openssl_version();
	if ($maj < 3) {
		my $found = ($maj == 0) ? "none" : "$maj.$min";
		return (0, "OpenSSL 3.0 or newer is required for client certificate issuance (found: $found)");
		}
	my ($cacert, $cakey, $mode) = ca_material($sslcert, $sslprvkey);
	return (0, "issuing certificate not found: $cacert") unless -e $cacert;
	return (0, "issuing key not found: $cakey") unless -e $cakey;

	my ($cfh, $cfile) = tempfile("luminum-csr-XXXXXX", SUFFIX => ".csr");
	return (0, "cannot write temp CSR: $!") unless defined $cfile;
	print $cfh $csr_pem;
	close($cfh);
	my @tmp = ($cfile);
	my $cleanup = sub { unlink(@tmp) };

	my ($ok, $pub) = _check_csr($cfile);
	unless ($ok) { $cleanup->(); return (0, $pub); }

	# Random serial (8 bytes) - no -CAcreateserial state file.
	my $serial;
	open(my $ur, "<", "/dev/urandom") or do { $cleanup->(); return (0, "cannot read /dev/urandom: $!"); };
	read($ur, $serial, 8);
	close($ur);
	$serial = sprintf("0x%s", unpack("H*", $serial));

	my ($ofh, $ofile) = tempfile("luminum-crt-XXXXXX", SUFFIX => ".crt");
	return (0, "cannot write temp certificate: $!") unless defined $ofile;
	push @tmp, $ofile;
	close($ofh);

	my $cmd = sprintf(
		'openssl x509 -req -in "%s" -CA "%s" -CAkey "%s" -set_serial %s -days %d -subj "/CN=luminum-client-%s" -out "%s" 2>&1',
		$cfile, $cacert, $cakey, $serial, CERT_DAYS, $uid, $ofile);
	my $out = `$cmd`;
	if ($? != 0) {
		$cleanup->();
		return (0, "certificate issuance failed: " . trim($out));
		}

	# Verify what was issued before handing it out.
	my $subject = `openssl x509 -in "$ofile" -noout -subject 2>/dev/null`;
	unless ($subject =~ /CN\s*=\s*luminum-client-$uid\b/) {
		$cleanup->();
		return (0, "issued certificate subject is wrong: " . trim($subject));
		}
	my $issuerout = `openssl x509 -in "$ofile" -noout -issuer 2>/dev/null`;
	my $issuer = trim($issuerout);
	my $anchorsubjout = `openssl x509 -in "$cacert" -noout -subject 2>/dev/null`;
	my $anchor_subj = trim($anchorsubjout);
	$issuer =~ s/^issuer=//;
	$anchor_subj =~ s/^subject=//;
	unless ($issuer ne "" && $issuer eq $anchor_subj) {
		$cleanup->();
		return (0, "issued certificate issuer does not match the anchor");
		}
	# Capture the command output in a statement first: backticks used
	# directly as a call argument evaluate in list context (split on
	# newlines), and _flat would receive only the PEM header line.
	my $certpubout = `openssl x509 -in "$ofile" -noout -pubkey 2>/dev/null`;
	my $certpub = _flat($certpubout);
	my $csrpub = _flat($pub);
	unless ($certpub ne "" && $certpub eq $csrpub) {
		$cleanup->();
		return (0, "issued certificate public key does not match the CSR");
		}
	my $verify = `openssl verify -CAfile "$cacert" "$ofile" 2>&1`;
	if ($? != 0) {
		if ($mode eq "server" && $verify =~ /invalid CA certificate/) {
			# Import-mode anchor without CA:TRUE - expected; the P2P
			# channel verifies with rustls, whose trust anchors are not
			# subject to the CA:TRUE check (module header).
			$log->("  note: anchor certificate lacks CA:TRUE; the issued client certificate will verify on the rustls P2P channel only");
		}
		else {
			$cleanup->();
			return (0, "issued certificate failed chain verification: " . trim($verify));
		}
		}

	my $certpem;
	unless (open(my $rf, "<", $ofile)) {
		$cleanup->();
		return (0, "cannot read issued certificate: $!");
		}
	else {
		local $/;
		$certpem = <$rf>;
		close($rf);
		}
	$cleanup->();
	return (1, $certpem);
	}

1;
