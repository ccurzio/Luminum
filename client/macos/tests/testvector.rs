// Shared Ed25519 test vector check (docs/protocol.md §5.3).
//
// Locks cross-implementation compatibility: this test asserts that
// ed25519-dalek reproduces the fixed signature for the fixed seed +
// envelope; tests/verify_vector.pl asserts the same for Perl's
// Crypt::Perl::Ed25519. The vector lives in the repo-shared
// tests/testvector.json. Regenerate it with:
//   cargo run --example gentestvector
//
// Usage: cargo test --test testvector

use base64ct::Encoding;
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::path::Path;

const SPKI_ED25519_PREFIX: [u8; 12] = [0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00];

fn hex(bytes: &[u8]) -> String {
	bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn hex_to_bytes(s: &str) -> Vec<u8> {
	(0..s.len())
		.step_by(2)
		.map(|i| u8::from_str_radix(&s[i..i + 2], 16).expect("vector hex is malformed"))
		.collect()
}

fn load_vector() -> Value {
	let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/testvector.json");
	let raw = std::fs::read_to_string(&path)
		.unwrap_or_else(|e| panic!("cannot read {}: {}", path.display(), e));
	serde_json::from_str(&raw).expect("testvector.json is not valid JSON")
}

// Canonical form per §5.3: the envelope with `sig` omitted, keys sorted
// lexicographically at every level, no whitespace. serde_json::Value uses
// a BTreeMap, so serializing the sig-stripped envelope yields exactly this.
fn canonical(envelope: &Value) -> String {
	let mut v = envelope.clone();
	v.as_object_mut().expect("envelope is an object").remove("sig");
	serde_json::to_string(&v).expect("canonical serialization failed")
}

#[test]
fn vector_reproduces() {
	let vec = load_vector();

	// Canonical form matches the vector byte-for-byte.
	let canon = canonical(&vec["envelope"]);
	assert_eq!(canon, vec["canonical"].as_str().unwrap(), "canonical form mismatch");

	// Signing the canonical form with the fixed seed reproduces the vector signature.
	let seed: [u8; 32] = hex_to_bytes(vec["seed"].as_str().unwrap())
		.try_into()
		.expect("seed is 32 bytes");
	let key = SigningKey::from_bytes(&seed);
	let sig = key.sign(canon.as_bytes());
	let sig_b64 = base64ct::Base64::encode_string(sig.to_bytes().as_slice());
	assert_eq!(sig_b64, vec["sig"].as_str().unwrap(), "signature mismatch");

	// The public key, SPKI/DER encoding, and fingerprint derive as recorded.
	let pub_raw = key.verifying_key().to_bytes();
	assert_eq!(hex(&pub_raw), vec["pubkey"].as_str().unwrap(), "public key mismatch");
	let mut spki = SPKI_ED25519_PREFIX.to_vec();
	spki.extend_from_slice(&pub_raw);
	assert_eq!(hex(&spki), vec["pubkey_spki_der"].as_str().unwrap(), "SPKI/DER mismatch");
	assert_eq!(
		hex(&Sha256::digest(&spki)),
		vec["fingerprint"].as_str().unwrap(),
		"fingerprint mismatch"
	);

	// The recorded signature verifies under the recorded public key.
	let verifying = VerifyingKey::from_bytes(&pub_raw).expect("public key is valid");
	let sig_raw = base64ct::Base64::decode_vec(vec["sig"].as_str().unwrap()).expect("sig is base64");
	let signature = Signature::from_slice(&sig_raw).expect("sig is 64 bytes");
	verifying
		.verify(canon.as_bytes(), &signature)
		.expect("recorded signature failed verification");
}
