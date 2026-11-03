#
# Luminum Protocol Module v0.0.1
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Pure wire-protocol logic for the Luminum protocol (docs/protocol.md
# v1.0-draft): envelope canonicalization and Ed25519 signing/verification
# (protocol 3.3, 5.3), SPKI/DER key helpers and fingerprinting (3.1),
# envelope validation (5.1, 6.3), and length-prefixed framing (8.2).
#
# No I/O and no database access: this module is unit-testable in
# isolation (tests/brokertest.pl) and is shared by the broker process.

package Luminum::Protocol;

use strict;
use warnings;
use JSON::PP;
use MIME::Base64;
use Digest::SHA qw(sha256_hex);
use Crypt::Perl::Ed25519::PrivateKey;
use Crypt::Perl::Ed25519::PublicKey;

our $VERSION = "0.0.1";

# SPKI/DER prefix for a raw 32-byte Ed25519 public key (RFC 8410).
my $SPKI_PREFIX = pack("H*", "302a300506032b6570032100");

# Canonical JSON for signing (protocol 5.3): object keys sorted
# lexicographically, no whitespace, RFC 8259 escaping (no Unicode
# escaping of non-ASCII), minimal number form. The `sig` field is
# excluded. JSON::PP's canonical encoder produces exactly this form;
# agreement with the Rust implementation is enforced by the shared
# test vector (tests/testvector.json).
sub canonical_json {
	my $env = shift;
	my %canon = %$env;
	delete $canon{sig};
	my $json = JSON::PP->new->canonical->utf8;
	return $json->encode(\%canon);
	}

# Sign an envelope in place with a raw 32-byte Ed25519 seed
# (protocol 3.3). Returns the envelope.
sub sign_envelope {
	my $env = shift;
	my $seed = shift;
	my $priv = Crypt::Perl::Ed25519::PrivateKey->new($seed);
	$env->{sig} = encode_base64($priv->sign(canonical_json($env)), "");
	return $env;
	}

# Verify an envelope's signature against a raw 32-byte Ed25519 public
# key (protocol 3.3). Returns 1 (valid) or 0 (invalid/missing).
sub verify_envelope {
	my $env = shift;
	my $pubraw = shift;
	return 0 unless ref($env) eq "HASH" && defined $env->{sig} && $env->{sig} ne "";
	my $sig = eval { decode_base64($env->{sig}) };
	return 0 unless defined $sig && length($sig) == 64;
	my $pub = Crypt::Perl::Ed25519::PublicKey->new($pubraw);
	return $pub->verify(canonical_json($env), $sig) ? 1 : 0;
	}

# Extract the raw 32-byte public key from an SPKI/DER encoding.
# Returns undef if the encoding is not a 44-byte Ed25519 SPKI key.
sub spki_to_raw {
	my $der = shift;
	return undef unless defined $der && length($der) == 44 && substr($der, 0, 12) eq $SPKI_PREFIX;
	return substr($der, 12);
	}

# Build the 44-byte SPKI/DER encoding of a raw 32-byte public key.
# Returns undef on invalid input.
sub raw_to_spki {
	my $raw = shift;
	return undef unless defined $raw && length($raw) == 32;
	return $SPKI_PREFIX . $raw;
	}

# Fingerprint: lowercase hex SHA-256 of the SPKI/DER public key
# (protocol 3.1). Returns undef on invalid input.
sub fingerprint {
	my $raw = shift;
	my $der = raw_to_spki($raw);
	return undef unless defined $der;
	return sha256_hex($der);
	}

# Envelope validation (protocol 5.1, 6.3).
# Returns (1) on success, (0, $err) on failure. $err is one of:
#   PROTO_VERSION_MISMATCH  major version differs (drop, no response)
#   MALFORMED_ENVELOPE      a required field is missing or invalid
sub validate_envelope {
	my $env = shift;
	return (0, "MALFORMED_ENVELOPE") unless ref($env) eq "HASH";

	my $v = $env->{v};
	return (0, "MALFORMED_ENVELOPE") unless defined $v && !ref($v) && $v =~ /^\d+\.\d+$/;
	my ($major) = split(/\./, $v);
	return (0, "PROTO_VERSION_MISMATCH") if $major != 1;

	return (0, "MALFORMED_ENVELOPE") unless defined $env->{id} && $env->{id} =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
	return (0, "MALFORMED_ENVELOPE") unless defined $env->{ts} && !ref($env->{ts}) && $env->{ts} =~ /^\d+$/;
	return (0, "MALFORMED_ENVELOPE") unless defined $env->{src} && $env->{src} =~ /^(client|server|lumy)$/;
	return (0, "MALFORMED_ENVELOPE") unless defined $env->{uid} && $env->{uid} =~ /^[0-9]+$/;
	return (0, "MALFORMED_ENVELOPE") unless defined $env->{lumy} && $env->{lumy} =~ /^[a-z]+$/;
	return (0, "MALFORMED_ENVELOPE") unless defined $env->{action} && $env->{action} =~ /^[a-z]+$/;
	return (0, "MALFORMED_ENVELOPE") unless defined $env->{status} && !ref($env->{status}) && $env->{status} ne "";
	return (0, "MALFORMED_ENVELOPE") unless defined $env->{sig} && $env->{sig} ne "";
	if (exists $env->{err} && (ref($env->{err}) || $env->{err} !~ /^[\x20-\x7e]+$/)) { return (0, "MALFORMED_ENVELOPE"); }
	if (exists $env->{data} && ref($env->{data}) ne "HASH") { return (0, "MALFORMED_ENVELOPE"); }

	return (1);
	}

# Build an unsigned response/protocol envelope (protocol 5.1).
sub new_envelope {
	my %a = @_;
	return {
		v => "1.0",
		id => new_uuid4(),
		ts => time(),
		src => $a{src},
		uid => $a{uid},
		lumy => $a{lumy},
		action => $a{action},
		status => $a{status},
		};
	}

# Length-prefixed frame (protocol 8.2): 4-byte big-endian length
# followed by the JSON payload. The wire encoding is not canonical;
# the signature covers the canonical form, not the wire form.
# Returns the framed bytes, or undef if the payload exceeds $max
# (default 16 MiB data-channel cap).
sub frame_encode {
	my $env = shift;
	my $max = defined($_[0]) ? $_[0] : 16*1024*1024;
	my $json = JSON::PP->new->utf8;
	my $payload = $json->encode($env);
	return undef if length($payload) > $max;
	return pack("N", length($payload)) . $payload;
	}

# Decode a length-prefixed frame. Returns (1, $env) or (0, $err).
sub frame_decode {
	my $bytes = shift;
	my $max = defined($_[0]) ? $_[0] : 16*1024*1024;
	return (0, "SHORT_FRAME") unless defined $bytes && length($bytes) >= 4;
	my ($len) = unpack("N", substr($bytes, 0, 4));
	return (0, "INVALID_FRAME_LENGTH") if $len == 0 || $len > $max;
	return (0, "SHORT_FRAME") if length($bytes) < 4 + $len;
	my $payload = substr($bytes, 4, $len);
	my $env = eval { JSON::PP->new->utf8->decode($payload) };
	return (0, "MALFORMED_JSON") if $@ || ref($env) ne "HASH";
	return (1, $env);
	}

# UUIDv4 (protocol 5.1 message id format).
sub new_uuid4 {
	my $b;
	if (open(my $ur, "<", "/dev/urandom")) {
		read($ur, $b, 16);
		close($ur);
		}
	$b = join("", map { chr(int(rand(256))) } 1..16) unless defined $b && length($b) == 16;
	my @o = unpack("C16", $b);
	$o[6] = ($o[6] & 0x0f) | 0x40;
	$o[8] = ($o[8] & 0x3f) | 0x80;
	return sprintf("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x", @o);
	}

1;
