#!/usr/bin/perl
#
# brokertest.pl - offline test harness for Luminum::Protocol
#
# Exercises the Perl protocol layer the broker uses: canonical JSON
# (docs/protocol.md 5.3), Ed25519 envelope signing/verification (3.3),
# SPKI/DER key helpers (3.1), envelope validation (5.1), length-prefixed
# framing (8.2), and a simulated client->broker->client registration
# exchange. Also verifies the shared cross-implementation test vector
# (tests/testvector.json) so the Perl side stays locked to the Rust
# client (ed25519-dalek).
#
# Usage: perl tests/brokertest.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../server/lib";

use JSON::PP ();
use Crypt::Perl::Ed25519 ();
use Crypt::Perl::Ed25519::PrivateKey ();
use Crypt::Perl::Ed25519::PublicKey ();
use Digest::SHA qw(sha256_hex);
use MIME::Base64 qw(decode_base64 encode_base64);

use Luminum::Protocol;

my $FAILURES = 0;
sub check {
    my ($name, $ok, $detail) = @_;
    if ($ok) {
        print "ok   - $name\n";
    } else {
        $FAILURES++;
        print "FAIL - $name" . (defined $detail ? " ($detail)" : "") . "\n";
    }
}

# ---------------------------------------------------------------------------
# 1. canonical_json (protocol 5.3)
# ---------------------------------------------------------------------------
check("canonical_json sorts keys",
    Luminum::Protocol::canonical_json({ b => 1, a => 2 }) eq '{"a":2,"b":1}');

check("canonical_json sorts nested keys recursively",
    Luminum::Protocol::canonical_json({ z => { d => 1, c => 2 }, a => 3 })
    eq '{"a":3,"z":{"c":2,"d":1}}');

check("canonical_json escapes quotes/backslashes",
    Luminum::Protocol::canonical_json({ m => 'a"b\\c' }) eq '{"m":"a\\"b\\\\c"}');

check("canonical_json omits sig",
    Luminum::Protocol::canonical_json({ a => 1, sig => "xxx" }) eq '{"a":1}');

# ---------------------------------------------------------------------------
# 2. Shared cross-implementation test vector (tests/testvector.json)
# ---------------------------------------------------------------------------
my $vecfile = "$Bin/testvector.json";
if (-f $vecfile) {
    my $vecraw = do {
        open my $fh, "<:raw", $vecfile or die "open $vecfile: $!";
        local $/; <$fh>
    };
    my $vec = JSON::PP->new->utf8->decode($vecraw);

    check("vector: canonical form matches",
        Luminum::Protocol::canonical_json($vec->{envelope}) eq $vec->{canonical});

    my $seed = pack("H*", $vec->{seed});
    my $env  = Luminum::Protocol::sign_envelope($vec->{envelope}, $seed);
    check("vector: Perl signature matches Rust (ed25519-dalek) signature",
        $env->{sig} eq $vec->{sig}, "got " . ($env->{sig} // "undef"));

    my $pub  = Luminum::Protocol::spki_to_raw(pack("H*", $vec->{pubkey_spki_der}));
    check("vector: signature verifies under vector public key",
        Luminum::Protocol::verify_envelope($env, $pub) == 1);

    check("vector: fingerprint matches",
        Luminum::Protocol::fingerprint($pub) eq $vec->{fingerprint});
} else {
    check("vector: tests/testvector.json present", 0, $vecfile);
}

# ---------------------------------------------------------------------------
# 3. Sign / verify round trip + negative cases
# ---------------------------------------------------------------------------
my $seed = join "", map { chr int(rand 256) } 1 .. 32;
my $pkey = Crypt::Perl::Ed25519::PrivateKey->new($seed);
my $pub  = $pkey->get_public_key;
my $pubraw = Luminum::Protocol::spki_to_raw($pub->to_der);
check("spki_to_raw returns 32 raw bytes", length($pubraw) == 32);

my $env = Luminum::Protocol::new_envelope(
    src => "client", uid => "451", lumy => "core", action => "register", status => "OK",
);
$env->{data} = { hostname => "h1", ipv4 => "10.0.0.1" };
Luminum::Protocol::sign_envelope($env, $seed);
check("round trip: signature verifies", Luminum::Protocol::verify_envelope($env, $pubraw) == 1);

my $other = Crypt::Perl::Ed25519::PrivateKey->new(join "", map { chr int(rand 256) } 1 .. 32);
my $otherpub = Luminum::Protocol::spki_to_raw($other->get_public_key->to_der);
check("rejects signature under wrong key",
    Luminum::Protocol::verify_envelope($env, $otherpub) == 0);

my $tampered = { %$env, data => { hostname => "EVIL" } };
check("rejects tampered envelope", Luminum::Protocol::verify_envelope($tampered, $pubraw) == 0);

check("rejects envelope with missing sig",
    Luminum::Protocol::verify_envelope({ %$env, sig => undef }, $pubraw) == 0);
check("rejects envelope with empty sig",
    Luminum::Protocol::verify_envelope({ %$env, sig => "" }, $pubraw) == 0);
check("rejects envelope with non-base64 sig",
    Luminum::Protocol::verify_envelope({ %$env, sig => "!!!" }, $pubraw) == 0);
check("rejects non-hash envelope",
    Luminum::Protocol::verify_envelope("not a hash", $pubraw) == 0);

# ---------------------------------------------------------------------------
# 4. SPKI / DER helpers (protocol 3.1)
# ---------------------------------------------------------------------------
check("raw_to_spki -> spki_to_raw round trip",
    Luminum::Protocol::spki_to_raw(Luminum::Protocol::raw_to_spki($pubraw)) eq $pubraw);
check("spki_to_raw rejects undef", !defined Luminum::Protocol::spki_to_raw(undef));
check("spki_to_raw rejects short input", !defined Luminum::Protocol::spki_to_raw("short"));
check("spki_to_raw rejects bad prefix",
    !defined Luminum::Protocol::spki_to_raw("\x00" x 44));
check("raw_to_spki rejects 31-byte input",
    !defined Luminum::Protocol::raw_to_spki("x" x 31));

# ---------------------------------------------------------------------------
# 5. Fingerprint (protocol 3.1)
# ---------------------------------------------------------------------------
check("fingerprint is 64 lowercase hex chars",
    Luminum::Protocol::fingerprint($pubraw) =~ /^[0-9a-f]{64}$/);
check("fingerprint rejects bad input", !defined Luminum::Protocol::fingerprint("x" x 31));

# ---------------------------------------------------------------------------
# 6. validate_envelope (protocol 5.1)
# ---------------------------------------------------------------------------
my $good = Luminum::Protocol::new_envelope(
    src => "client", uid => "451", lumy => "core", action => "register", status => "OK",
);
$good->{sig} = "sig";
my ($ok, $err) = Luminum::Protocol::validate_envelope($good);
check("valid envelope passes", $ok == 1, $err);

my @badcases = (
    ["non-hash envelope",            "not a hash",              "MALFORMED_ENVELOPE"],
    ["missing v",                    { %$good, v => undef },    "MALFORMED_ENVELOPE"],
    ["bad v format",                 { %$good, v => "1" },      "MALFORMED_ENVELOPE"],
    ["major version mismatch",       { %$good, v => "2.0" },    "PROTO_VERSION_MISMATCH"],
    ["bad id",                       { %$good, id => "nope" },  "MALFORMED_ENVELOPE"],
    ["missing ts",                   { %$good, ts => undef },   "MALFORMED_ENVELOPE"],
    ["non-numeric ts",               { %$good, ts => "abc" },   "MALFORMED_ENVELOPE"],
    ["bad src",                      { %$good, src => "x" },    "MALFORMED_ENVELOPE"],
    ["bad uid",                      { %$good, uid => "abc" },  "MALFORMED_ENVELOPE"],
    ["bad lumy",                     { %$good, lumy => "Core" }, "MALFORMED_ENVELOPE"],
    ["bad action",                   { %$good, action => "Go" }, "MALFORMED_ENVELOPE"],
    ["missing status",               { %$good, status => undef }, "MALFORMED_ENVELOPE"],
    ["missing sig",                  { %$good, sig => undef },  "MALFORMED_ENVELOPE"],
    ["binary err",                   { %$good, err => "a\x01b" }, "MALFORMED_ENVELOPE"],
    ["array data",                   { %$good, data => [1] },   "MALFORMED_ENVELOPE"],
);
for my $c (@badcases) {
    my ($label, $envb, $want) = @$c;
    my ($okb, $errb) = Luminum::Protocol::validate_envelope($envb);
    check("validate: $label -> $want", $okb == 0 && $errb eq $want, "got " . ($errb // "ok"));
}

my $nodata = Luminum::Protocol::new_envelope(
    src => "server", uid => "451", lumy => "core", action => "ack", status => "OK",
);
$nodata->{sig} = "sig";
($ok, $err) = Luminum::Protocol::validate_envelope($nodata);
check("data is optional", $ok == 1, $err);

my $witherr = { %$good, err => "plain error text" };
($ok, $err) = Luminum::Protocol::validate_envelope($witherr);
check("printable err accepted", $ok == 1, $err);

# ---------------------------------------------------------------------------
# 7. new_envelope
# ---------------------------------------------------------------------------
my $ne = Luminum::Protocol::new_envelope(
    src => "client", uid => "7", lumy => "core", action => "checkin", status => "OK",
);
check("new_envelope: v is 1.0", $ne->{v} eq "1.0");
check("new_envelope: id is UUIDv4",
    $ne->{id} =~ /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    $ne->{id});
check("new_envelope: ts is current epoch",
    abs($ne->{ts} - time()) < 10);
check("new_envelope: no sig field", !exists $ne->{sig});

# ---------------------------------------------------------------------------
# 8. Framing (protocol 8.2)
# ---------------------------------------------------------------------------
my $fenv = { v => "1.0", msg => "hello framing" };
my $frame = Luminum::Protocol::frame_encode($fenv);
check("frame_encode: 4-byte length prefix",
    defined $frame && length($frame) >= 4);
if (defined $frame) {
    my ($len, $body) = $frame =~ /^(.{4})(.*)$/s;
    check("frame_encode: length field matches body",
        unpack("N", $len) == length($body));
    my ($rok, $denv) = Luminum::Protocol::frame_decode($frame);
    check("frame round trip", $rok == 1 && defined $denv && $denv->{msg} eq "hello framing");
}

check("frame_encode: oversize returns undef",
    !defined Luminum::Protocol::frame_encode($fenv, 10));

my ($rok, $ferr);
($rok, $ferr) = Luminum::Protocol::frame_decode("abc");
check("frame_decode: short input -> SHORT_FRAME",
    $rok == 0 && $ferr eq "SHORT_FRAME", $ferr);

($rok, $ferr) = Luminum::Protocol::frame_decode(pack("N", 0) . "x");
check("frame_decode: zero length -> INVALID_FRAME_LENGTH",
    $rok == 0 && $ferr eq "INVALID_FRAME_LENGTH", $ferr);

($rok, $ferr) = Luminum::Protocol::frame_decode(pack("N", 1000) . "x", 100);
check("frame_decode: length over max -> INVALID_FRAME_LENGTH",
    $rok == 0 && $ferr eq "INVALID_FRAME_LENGTH", $ferr);

($rok, $ferr) = Luminum::Protocol::frame_decode(substr($frame, 0, length($frame) - 1));
check("frame_decode: truncated body -> SHORT_FRAME",
    $rok == 0 && $ferr eq "SHORT_FRAME", $ferr);

($rok, $ferr) = Luminum::Protocol::frame_decode(pack("N", 3) . "[1]");
check("frame_decode: non-object JSON -> MALFORMED_JSON",
    $rok == 0 && $ferr eq "MALFORMED_JSON", $ferr);

# ---------------------------------------------------------------------------
# 9. new_uuid4
# ---------------------------------------------------------------------------
my %seen;
my $uuids_ok = 1;
for (1 .. 1000) {
    my $u = Luminum::Protocol::new_uuid4();
    $uuids_ok = 0 unless $u =~ /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
    $seen{$u} = 1;
}
check("new_uuid4: 1000 unique well-formed UUIDv4", $uuids_ok && scalar(keys %seen) == 1000);

# ---------------------------------------------------------------------------
# 10. Simulated registration flow (protocol 8.2)
# ---------------------------------------------------------------------------
sub pub_from_seed {
    my ($s) = @_;
    return Luminum::Protocol::spki_to_raw(
        Crypt::Perl::Ed25519::PrivateKey->new($s)->get_public_key->to_der
    );
}

my $clientseed = join "", map { chr int(rand 256) } 1 .. 32;
my $serverseed = join "", map { chr int(rand 256) } 1 .. 32;
my $clientpub  = pub_from_seed($clientseed);
my $serverpub  = pub_from_seed($serverseed);

# Client -> broker: signed, framed register envelope.
my $reg = Luminum::Protocol::new_envelope(
    src => "client", uid => "451", lumy => "core", action => "register", status => "OK",
);
$reg->{data} = {
    hostname => "web-01", ipv4 => "172.16.0.10", osplat => "Linux",
    osrel => "Debian 12.10", clientver => "0.0.1",
};
Luminum::Protocol::sign_envelope($reg, $clientseed);
my $regframe = Luminum::Protocol::frame_encode($reg);

my ($dok, $dreg) = Luminum::Protocol::frame_decode($regframe);
check("flow: broker decodes client frame", $dok == 1);
my ($vok, $verr) = Luminum::Protocol::validate_envelope($dreg);
check("flow: broker validates client envelope", $vok == 1, $verr);
check("flow: broker verifies client signature",
    Luminum::Protocol::verify_envelope($dreg, $clientpub) == 1);
check("flow: client sig rejected under server key",
    Luminum::Protocol::verify_envelope($dreg, $serverpub) == 0);

# Broker -> client: signed, framed response.
my $resp = Luminum::Protocol::new_envelope(
    src => "server", uid => "451", lumy => "core", action => "ack", status => "OK",
);
$resp->{data} = { session => "s-123" };
Luminum::Protocol::sign_envelope($resp, $serverseed);
my $respframe = Luminum::Protocol::frame_encode($resp);

my ($rok2, $dresp) = Luminum::Protocol::frame_decode($respframe);
check("flow: client decodes broker frame", $rok2 == 1);
my ($vok2, $verr2) = Luminum::Protocol::validate_envelope($dresp);
check("flow: client validates broker envelope", $vok2 == 1, $verr2);
check("flow: client verifies broker signature",
    Luminum::Protocol::verify_envelope($dresp, $serverpub) == 1);
check("flow: broker sig rejected under client key",
    Luminum::Protocol::verify_envelope($dresp, $clientpub) == 0);

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
