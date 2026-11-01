// Generate the shared Ed25519 test vector (docs/protocol.md §5.3).
// The vector locks cross-implementation compatibility: the Rust client
// (ed25519-dalek) and the Perl server (Crypt::Perl::Ed25519) MUST both
// reproduce `sig` for `seed` + `envelope`.
//
// Usage: cargo run --example gentestvector
// Output: prints the vector to stdout; save it as the repo-shared
// tests/testvector.json (from the repo root).


use base64ct::Encoding;
use ed25519_dalek::{Signer, SigningKey};
use sha2::{Digest, Sha256};

const SPKI_ED25519_PREFIX: [u8; 12] = [0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00];

fn hex(bytes: impl AsRef<[u8]>) -> String {
	bytes.as_ref().iter().map(|b| format!("{:02x}", b)).collect()
}

fn main() {
	// Fixed 32-byte seed: 0x00..0x1f
	let seed: [u8; 32] = (0..32u8).collect::<Vec<u8>>().try_into().unwrap();
	let key = SigningKey::from_bytes(&seed);
	let pub_raw = key.verifying_key().to_bytes();

	let mut spki = SPKI_ED25519_PREFIX.to_vec();
	spki.extend_from_slice(&pub_raw);
	let fingerprint = hex(Sha256::digest(&spki));

	// Fixed envelope (ASCII only, per §5.3).
	let envelope = serde_json::json!({
		"v": "1.0",
		"id": "00000000-0000-4000-8000-000000000000",
		"ts": 1735689600,
		"src": "client",
		"uid": "451",
		"lumy": "core",
		"action": "checkin",
		"status": "OK",
		"data": {
			"hostname": "testhost",
			"osplat": "Linux",
			"osrel": "Debian 12.10",
			"clientver": "0.0.1",
			"ipv4": "172.16.0.10"
		}
	});

	// Canonical form: serde_json Value uses a BTreeMap (sorted keys)
	// and emits no whitespace (§5.3).
	let canonical = serde_json::to_string(&envelope).unwrap();
	let sig = key.sign(canonical.as_bytes());

	let vector = serde_json::json!({
		"desc": "Luminum shared Ed25519 test vector (protocol 5.3)",
		"seed": hex(seed),
		"pubkey": hex(pub_raw),
		"pubkey_spki_der": hex(spki),
		"fingerprint": fingerprint,
		"envelope": envelope,
		"canonical": canonical,
		"sig": base64ct::Base64::encode_string(sig.to_bytes().as_slice())
	});
	println!("{}", serde_json::to_string_pretty(&vector).unwrap());
}
