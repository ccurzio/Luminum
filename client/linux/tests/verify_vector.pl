#!/usr/bin/perl -w
# Cross-implementation check for the shared Ed25519 test vector
# (docs/protocol.md section 5.3). Rebuilds the canonical envelope form,
# signs it with Crypt::Perl::Ed25519 under the fixed seed, and compares
# against the vector produced by the Rust client (ed25519-dalek).
#
# Usage: perl verify_vector.pl [path/to/testvector.json]
use strict;
use warnings;
use FindBin qw($Bin);
use JSON::PP;
use MIME::Base64;
use Crypt::Perl::Ed25519::PrivateKey;
use Crypt::Perl::Ed25519::PublicKey;

my $path = shift || "$Bin/../../../tests/testvector.json";
open(my $fh, "<", $path) or die "cannot read $path: $!\n";
my $vec = decode_json(do { local $/; <$fh> });
close($fh);

my $failures = 0;
sub check {
	my ($ok, $what) = @_;
	print(($ok ? "ok" : "FAIL") . " - $what\n");
	$failures++ unless $ok;
	}

# Canonical form per section 5.3: keys sorted, no whitespace, sig omitted.
my %env = %{ $vec->{envelope} };
delete $env{sig};
my $canon = JSON::PP->new->canonical->utf8->encode(\%env);
check($canon eq $vec->{canonical}, "canonical form matches vector");

# Signing the canonical form with the fixed seed reproduces the vector signature.
my $seed = pack("H*", $vec->{seed});
my $priv = Crypt::Perl::Ed25519::PrivateKey->new($seed);
my $sig = $priv->sign($canon);
my $sig_b64 = encode_base64($sig, "");
check($sig_b64 eq $vec->{sig}, "signature matches vector");

# The signature verifies under the vector public key.
my $pub = Crypt::Perl::Ed25519::PublicKey->new(pack("H*", $vec->{pubkey}));
check($pub->verify($canon, $sig) ? 1 : 0, "signature verifies under vector public key");

print $failures ? "FAILED ($failures)\n" : "ALL PASSED\n";
exit($failures ? 1 : 0);
