// Luminum Client for Linux
// by Christopher R. Curzio <ccurzio@luminum.net>

// Base client process: configuration, registration, check-ins, Lumy
// discovery/launch, and the local IPC channel (port 10461) used by
// Lumy modules to talk to the client.
//
// Protocol notes (docs/protocol.md v1.0-draft):
//  - All direct channels use length-prefixed frames: 4-byte big-endian
//    length followed by a JSON envelope (§8.2).
//  - The envelope format is §5.1. The MQTT control channel (Mosquitto) is
//    the home for commands, responses, check-ins, and events (§4); the
//    bootstrap/direct channel to the server listener (LPORT 10465) carries
//    registration and the Lumy newconfig fetch. The bulk data channel
//    (§8.3) and Lumy-namespaced MQTT routing (§6.2) are not implemented yet.
//  - Every outgoing envelope is signed with the client's Ed25519 key
//    over the canonical JSON (§5.3). Server responses are verified
//    against the server signing key extracted from the validated
//    signing certificate (config/server-signing.crt, the bootstrap
//    trust anchor of §7.1); the in-band serverpubkey field is
//    cross-checked against that anchor. Lumy IPC messages are
//    verified against the client's own public key (§3.3, §8.2).

use clap::{Arg, App};
use colored::Colorize;
use chrono::Local;
use chrono::format::strftime::StrftimeItems;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::process;
use std::process::{Command, Stdio};
use std::thread;
use tokio::task::spawn;
use tokio::time;
use gethostname::gethostname;
use etc_os_release::OsRelease;
use local_ip_address::local_ip;
use std::net::{TcpListener, SocketAddr, ToSocketAddrs, TcpStream};
use native_tls::{TlsConnector, TlsStream};
use std::error::Error;
use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::io::{self, Read, Write};
use std::time::{Duration, Instant};
use rusqlite::{params, Connection};
use serde::{Serialize, Deserialize};
use std::path::Path;

use base64ct::Encoding;
use ed25519_dalek::{Signer, Verifier, SigningKey, VerifyingKey, Signature};
use sha2::{Digest, Sha256};

const VER: &str = "0.1.0";
const IPORT: u16 = 10704;
const DPORT: u16 = 10465;
const LPORT: u16 = 10461;
const CHECKIN_SECS: u64 = 300;
// Per-sensor execution cap (protocol §7.3): the safety valve for a single
// sensor script; the server's command deadline (CMDTIMEOUT) governs the
// whole query.
const SENSOR_TIMEOUT_SECS: u64 = 30;
// Bootstrap-channel I/O bounds. The registration path runs on a blocking
// socket; without these, a stalled TCP connect, a wedged TLS handshake, or a
// silent server would hang the client forever. The server's own CONNTIMEOUT
// (30s) bounds the handshake + one request/response, so these match it.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(30);
const IO_TIMEOUT: Duration = Duration::from_secs(30);
// Deregistration probe pacing (protocol §4.1): after the MQTT broker refuses
// the client's credentials, the bootstrap probe may re-ask at most this
// often, and this is the retry interval while the probe reaches no verdict.
const PROBE_EVERY: Duration = Duration::from_secs(900);
const SLOW_RETRY: Duration = Duration::from_secs(900);
// This client's OS platform (protocol §4.2 / §6.1). Used both in the check-in
// payload (osplat) and to build the OS group topic luminum/{SID}/os/{os}/cmd.
const OSPLAT: &str = "Linux";

// Install root; overridable via LUMINUM_HOME for testing.
fn base_path() -> String {
	std::env::var("LUMINUM_HOME").unwrap_or_else(|_| String::from("/opt/Luminum/LuminumClient"))
}

fn cfg_path() -> String { format!("{}/config/client.conf.db", base_path()) }
fn crt_path() -> String { format!("{}/config/server.crt", base_path()) }
fn client_key_path() -> String { format!("{}/config/client.key", base_path()) }
fn client_crt_path() -> String { format!("{}/config/client.crt", base_path()) }
fn signing_crt_path() -> String { format!("{}/config/server-signing.crt", base_path()) }
fn mod_path() -> String { format!("{}/modules", base_path()) }
fn outq_path() -> String { format!("{}/config/outqueue.db", base_path()) }

// ---------------------------------------------------------------------------
// Envelope (protocol §5.1)
// ---------------------------------------------------------------------------

#[derive(Serialize, Deserialize, Debug, Clone)]
struct Envelope {
	v: String,
	id: String,
	ts: i64,
	src: String,
	uid: String,
	lumy: String,
	action: String,
	status: String,
	#[serde(skip_serializing_if = "Option::is_none")]
	err: Option<String>,
	#[serde(skip_serializing_if = "Option::is_none")]
	data: Option<serde_json::Value>,
	#[serde(skip_serializing_if = "Option::is_none")]
	sig: Option<String>,
}

fn new_envelope(src: &str, uid: &str, lumy: &str, action: &str, status: &str, data: Option<serde_json::Value>) -> Envelope {
	Envelope {
		v: String::from("1.0"),
		id: uuid4(),
		ts: Local::now().timestamp(),
		src: String::from(src),
		uid: String::from(uid),
		lumy: String::from(lumy),
		action: String::from(action),
		status: String::from(status),
		err: None,
		data,
		// Signed in place before transmission (sign_envelope, §3.3).
		sig: None,
	}
}

fn uuid4() -> String {
	let mut b = [0u8; 16];
	getrandom::getrandom(&mut b).expect("Error: unable to obtain randomness for UUID");
	b[6] = (b[6] & 0x0f) | 0x40;
	b[8] = (b[8] & 0x3f) | 0x80;
	format!("{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
		b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
}

// ---------------------------------------------------------------------------
// Framing (protocol §8.2): 4-byte big-endian length + JSON payload
// ---------------------------------------------------------------------------

const MAX_FRAME: usize = 16 * 1024 * 1024; // 16 MiB data channel cap

fn frame_write<W: Write>(w: &mut W, env: &Envelope) -> Result<(), Box<dyn Error>> {
	let payload = serde_json::to_vec(env)?;
	if payload.len() > MAX_FRAME {
		return Err(Box::from("Frame payload exceeds maximum size"));
	}
	let len = (payload.len() as u32).to_be_bytes();
	w.write_all(&len)?;
	w.write_all(&payload)?;
	w.flush()?;
	Ok(())
}

fn frame_read<R: Read>(r: &mut R) -> Result<Envelope, Box<dyn Error>> {
	let mut lenbuf = [0u8; 4];
	r.read_exact(&mut lenbuf)?;
	let len = u32::from_be_bytes(lenbuf) as usize;
	if len == 0 || len > MAX_FRAME {
		return Err(Box::from("Invalid frame length"));
	}
	let mut payload = vec![0u8; len];
	r.read_exact(&mut payload)?;
	let env: Envelope = serde_json::from_slice(&payload)?;
	Ok(env)
}

// ---------------------------------------------------------------------------
// Ed25519 signatures (protocol §3.3, §5.3)
// ---------------------------------------------------------------------------

// SPKI/DER encoding of an Ed25519 public key (RFC 8410): a fixed
// 12-byte header followed by the raw 32-byte key.
const SPKI_ED25519_PREFIX: [u8; 12] = [0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00];

fn spki_der(pub_bytes: &[u8; 32]) -> Vec<u8> {
	let mut der = SPKI_ED25519_PREFIX.to_vec();
	der.extend_from_slice(pub_bytes);
	der
}

// Extract the raw 32-byte public key from an SPKI/DER encoding.
fn spki_to_raw(der: &[u8]) -> Option<[u8; 32]> {
	if der.len() != 44 || der[..12] != SPKI_ED25519_PREFIX[..] {
		return None;
	}
	let mut raw = [0u8; 32];
	raw.copy_from_slice(&der[12..]);
	Some(raw)
}

// Fingerprint: lowercase hex SHA-256 of the SPKI/DER public key (§3.1).
fn fingerprint(pub_bytes: &[u8; 32]) -> String {
	let digest = Sha256::digest(spki_der(pub_bytes));
	let mut hex = String::with_capacity(64);
	for b in digest { hex.push_str(&format!("{:02x}", b)); }
	hex
}

// Canonical JSON for signing (§5.3): keys sorted lexicographically at
// every level, no whitespace, RFC 8259 escaping, minimal number form.
// serde_json's Value uses a BTreeMap (byte-ordered keys) and its
// serializer emits exactly this form, so building the Value with the
// `sig` field omitted is sufficient.
fn canonical_json(env: &Envelope) -> String {
	let mut v = serde_json::json!({
		"v": env.v,
		"id": env.id,
		"ts": env.ts,
		"src": env.src,
		"uid": env.uid,
		"lumy": env.lumy,
		"action": env.action,
		"status": env.status,
	});
	if let Some(err) = &env.err { v["err"] = serde_json::json!(err); }
	if let Some(data) = &env.data { v["data"] = data.clone(); }
	serde_json::to_string(&v).expect("Error: unable to serialize canonical envelope")
}

fn sign_envelope(env: &mut Envelope, seed: &[u8; 32]) {
	let key = SigningKey::from_bytes(seed);
	let sig = key.sign(canonical_json(env).as_bytes());
	env.sig = Some(base64ct::Base64::encode_string(sig.to_bytes().as_slice()));
}

fn verify_envelope(env: &Envelope, pub_bytes: &[u8; 32]) -> bool {
	let Some(sig_b64) = env.sig.as_deref() else { return false; };
	let Ok(sig_raw) = base64ct::Base64::decode_vec(sig_b64) else { return false; };
	let Ok(signature) = Signature::from_slice(&sig_raw) else { return false; };
	let Ok(key) = VerifyingKey::from_bytes(pub_bytes) else { return false; };
	key.verify(canonical_json(env).as_bytes(), &signature).is_ok()
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

fn parse_clientconfig(debug: bool) -> HashMap<String, String> {
	let mut clientconfig: HashMap<String, String> = HashMap::new();

	if fs::metadata(cfg_path()).is_ok() {
		let confconn = match Connection::open(cfg_path()) {
			Ok(confconn) => confconn,
			Err(err) => {
				dbout(debug, 1, &format!("Could not open client configuration database: {}", err));
				process::exit(1);
			}
		};
		// The config DB holds the client's private signing key (CLPPRV);
		// enforce 0600 in case the file was created or copied with a looser mode.
		let mode = fs::metadata(cfg_path()).expect("Error: Could not stat configuration database").permissions().mode();
		if mode & 0o777 != 0o600 {
			fs::set_permissions(cfg_path(), fs::Permissions::from_mode(0o600))
				.expect("Error: Could not secure configuration database");
		}
		// CONFIG is keyed by KEY: config_set uses INSERT OR REPLACE, which
		// only replaces when KEY is unique (without the constraint it
		// appends a duplicate row on every write - e.g. each setgroups).
		// Enforce it on open; pre-existing duplicates keep the newest row.
		if confconn.execute("create unique index if not exists IDX_CONFIG_KEY on CONFIG (KEY)", []).is_err() {
			confconn.execute("delete from CONFIG where rowid not in (select max(rowid) from CONFIG group by KEY)", [])
				.expect("Error: Could not deduplicate the CONFIG table.");
			confconn.execute("create unique index if not exists IDX_CONFIG_KEY on CONFIG (KEY)", [])
				.expect("Error: Could not create the unique index on the CONFIG table.");
		}
		let mut stmt = confconn.prepare("select KEY,VALUE from CONFIG").expect("Error: Could not prepare CONFIG query");
		let cfg_iter = stmt.query_map(params![], |row| {
			Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
		}).expect("Error: Unable to parse configuration values");
		for cfg_result in cfg_iter {
			if let Ok((key, value)) = cfg_result {
				clientconfig.insert(key, value);
			}
		}
	} else {
		dbout(debug, 1, "Configuration database not found. Run with --setup first.");
		process::exit(1);
	}
	clientconfig
}

fn config_set(key: &str, value: &str) {
	let confconn = Connection::open(cfg_path()).expect("Error: Could not open configuration database.");
	confconn.execute("insert or replace into CONFIG (KEY,VALUE) values (?1, ?2)", params![key, value])
		.expect("Error: Could not save configuration value.");
	confconn.close().unwrap();
}

fn config_delete(key: &str) {
	let confconn = Connection::open(cfg_path()).expect("Error: Could not open configuration database.");
	confconn.execute("delete from CONFIG where KEY = ?1", params![key])
		.expect("Error: Could not delete configuration value.");
	confconn.close().unwrap();
}

// ---------------------------------------------------------------------------
// Client keypair (protocol §3.1)
// ---------------------------------------------------------------------------

/// Load the client's Ed25519 keypair from the config DB, generating and
/// persisting a new one if absent or corrupt (CLPPRV = base64 32-byte
/// seed, CLPPUB = base64 raw public key, FPNT = fingerprint).
fn client_keypair(debug: bool, ccfg: &HashMap<String, String>) -> ([u8; 32], [u8; 32]) {
	if let (Some(prv), Some(pubk)) = (ccfg.get("CLPPRV"), ccfg.get("CLPPUB")) {
		match (base64ct::Base64::decode_vec(prv), base64ct::Base64::decode_vec(pubk)) {
			(Ok(prv_raw), Ok(pub_raw)) if prv_raw.len() == 32 && pub_raw.len() == 32 => {
				let mut seed = [0u8; 32];
				let mut pubb = [0u8; 32];
				seed.copy_from_slice(&prv_raw);
				pubb.copy_from_slice(&pub_raw);
				return (seed, pubb);
			}
			_ => dbout(debug, 1, "Stored client keypair is invalid. Regenerating..."),
		}
	}
	let mut seed = [0u8; 32];
	getrandom::getrandom(&mut seed).expect("Error: unable to obtain randomness for key generation");
	let key = SigningKey::from_bytes(&seed);
	let pubb = *key.verifying_key().as_bytes();
	config_set("CLPPRV", &base64ct::Base64::encode_string(&seed));
	config_set("CLPPUB", &base64ct::Base64::encode_string(&pubb));
	config_set("FPNT", &fingerprint(&pubb));
	dbout(debug, 3, "Generated new client signing keypair.");
	(seed, pubb)
}

/// The server's signing public key (raw 32 bytes), if stored in config.
fn server_pubkey(ccfg: &HashMap<String, String>) -> Option<[u8; 32]> {
	let raw = base64ct::Base64::decode_vec(ccfg.get("SRVPUB")?).ok()?;
	if raw.len() != 32 { return None; }
	let mut out = [0u8; 32];
	out.copy_from_slice(&raw);
	Some(out)
}

/// The client's install UUID (CLUUID): a UUIDv4 generated on first start
/// and persisted in the config DB alongside the signing keypair. A
/// reinstalled client gets a fresh keypair and a fresh UUID, so it
/// registers as a new endpoint and never collides with the record its
/// predecessor left behind.
fn client_uuid(debug: bool, ccfg: &HashMap<String, String>) -> String {
	if let Some(u) = ccfg.get("CLUUID") {
		if is_uuid4(u) { return u.clone(); }
	}
	let u = uuid4();
	config_set("CLUUID", &u);
	dbout(debug, 3, "Generated new client UUID.");
	u
}

/// The server's Ed25519 signing public key (raw 32 bytes) extracted from
/// the signing certificate distributed out of band (config/server-signing.crt),
/// which is the bootstrap trust anchor (protocol §7.1). The certificate is
/// accepted when it chains to the TLS trust root (config/server.crt - the
/// server certificate issued it) or when it is a valid self-signed
/// Ed25519 certificate (servers with imported TLS certificates cannot
/// issue from their CA). Returns None when no validated anchor exists.
fn server_signing_key(debug: bool) -> Option<[u8; 32]> {
	use openssl::stack::Stack;
	use openssl::x509::store::X509StoreBuilder;
	use openssl::x509::{X509, X509StoreContext};

	let pem = match fs::read(signing_crt_path()) {
		Ok(p) => p,
		Err(_) => {
			dbout(debug, 1, "Server signing certificate not found (config/server-signing.crt); registration requires the trust anchor distributed with the server certificate.");
			return None;
		}
	};
	let cert = match X509::from_pem(&pem) {
		Ok(c) => c,
		Err(_) => { dbout(debug, 1, "Server signing certificate is not a valid X.509 certificate."); return None; }
	};
	let pkey = match cert.public_key() {
		Ok(k) => k,
		Err(_) => { dbout(debug, 1, "Server signing certificate has no usable public key."); return None; }
	};
	if pkey.id() != openssl::pkey::Id::ED25519 {
		dbout(debug, 1, "Server signing certificate is not an Ed25519 certificate.");
		return None;
	}
	// Anchor validation: chain against the TLS trust root, else a valid
	// self-signature.
	let mut trusted = false;
	if let Ok(rootpem) = fs::read(crt_path()) {
		if let Ok(root) = X509::from_pem(&rootpem) {
			let store = X509StoreBuilder::new()
				.and_then(|mut b| { b.add_cert(root)?; Ok(b.build()) })
				.ok();
			if let Some(store) = store {
				if let Ok(chain) = Stack::<X509>::new() {
					if let Ok(mut ctx) = X509StoreContext::new() {
						trusted = matches!(ctx.init(&store, &cert, &chain, |c| c.verify_cert()), Ok(true));
					}
				}
			}
		}
	}
	if !trusted {
		trusted = matches!(cert.issuer_name().try_cmp(cert.subject_name()), Ok(std::cmp::Ordering::Equal))
			&& cert.verify(pkey.as_ref()).map(|ok| ok).unwrap_or(false);
	}
	if !trusted {
		dbout(debug, 1, "Server signing certificate is not trusted: it neither chains to the server certificate nor is it a valid self-signed certificate.");
		return None;
	}
	let raw = pkey.raw_public_key().ok()?;
	if raw.len() != 32 {
		dbout(debug, 1, "Server signing certificate public key has an unexpected length.");
		return None;
	}
	let mut out = [0u8; 32];
	out.copy_from_slice(&raw);
	dbout(debug, 3, "Server signing certificate validated (trust anchor established).");
	Some(out)
}

// ---------------------------------------------------------------------------
// Client TLS keypair + certificate (protocol §7.1 v1.1, docs/p2p.md 4.1)
// ---------------------------------------------------------------------------

// The P2P peer channel (10464) is mutual TLS: the endpoint presents a
// certificate the server issued, with subject CN = luminum-client-{UID}.
// The P-256 keypair is generated here on first use (the private key never
// leaves the endpoint - config/client.key, 0600) and the public key travels
// to the server inside a CSR, which the server signs into the channel
// certificate. The CSR subject is a placeholder: the server overrides it at
// issuance with the UID it assigns (x509 -req -subj).
fn tls_keypair_csr(debug: bool) -> Result<String, String> {
	use openssl::ec::{EcGroup, EcKey};
	use openssl::hash::MessageDigest;
	use openssl::nid::Nid;
	use openssl::pkey::{PKey, Private};
	use openssl::x509::{X509NameBuilder, X509ReqBuilder};

	let stored = fs::read(client_key_path())
		.ok()
		.and_then(|pem| PKey::<Private>::private_key_from_pem(&pem).ok());
	let pkey = match stored {
		Some(k) => k,
		None => {
			if Path::new(&client_key_path()).exists() {
				dbout(debug, 1, "Stored client TLS key is unreadable; generating a new keypair (the stored certificate, if any, will no longer match it).");
			}
			let group = EcGroup::from_curve_name(Nid::X9_62_PRIME256V1)
				.map_err(|e| format!("unable to initialize the P-256 curve: {}", e))?;
			let eckey = EcKey::generate(&group)
				.map_err(|e| format!("unable to generate the client TLS keypair: {}", e))?;
			let pkey = PKey::from_ec_key(eckey)
				.map_err(|e| format!("unable to build the client TLS key: {}", e))?;
			let pem = pkey.private_key_to_pem_pkcs8()
				.map_err(|e| format!("unable to encode the client TLS key: {}", e))?;
			let path = client_key_path();
			fs::write(&path, &pem).map_err(|e| format!("unable to save the client TLS key: {}", e))?;
			fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
				.map_err(|e| format!("unable to secure the client TLS key: {}", e))?;
			dbout(debug, 3, "Generated the client TLS keypair (config/client.key).");
			pkey
		}
	};

	let mut nb = X509NameBuilder::new().map_err(|e| format!("unable to build the CSR subject: {}", e))?;
	nb.append_entry_by_text("CN", "luminum-client-pending")
		.map_err(|e| format!("unable to build the CSR subject: {}", e))?;
	let name = nb.build();
	let mut reqb = X509ReqBuilder::new().map_err(|e| format!("unable to build the CSR: {}", e))?;
	reqb.set_subject_name(&name).map_err(|e| format!("unable to build the CSR: {}", e))?;
	reqb.set_pubkey(&pkey).map_err(|e| format!("unable to build the CSR: {}", e))?;
	reqb.sign(&pkey, MessageDigest::sha256()).map_err(|e| format!("unable to sign the CSR: {}", e))?;
	let req = reqb.build();
	let csr_pem = req.to_pem().map_err(|e| format!("unable to encode the CSR: {}", e))?;
	Ok(String::from_utf8_lossy(&csr_pem).into_owned())
}

// Store the server-issued client TLS certificate (config/client.crt, 0600)
// after checking it parses and carries this endpoint's TLS public key - a
// certificate for a different key would be useless on the P2P channel and
// indicates a server/client desync worth surfacing.
fn store_client_cert(debug: bool, cert_pem: &str) -> Result<(), String> {
	use openssl::pkey::{PKey, Private};
	use openssl::x509::X509;

	let cert = X509::from_pem(cert_pem.as_bytes())
		.map_err(|_| String::from("the issued certificate is not a valid X.509 certificate"))?;
	let certpub = cert.public_key()
		.map_err(|e| format!("the issued certificate has no usable public key: {}", e))?;
	let keypem = fs::read(client_key_path())
		.map_err(|e| format!("client TLS key not found: {}", e))?;
	let key = PKey::<Private>::private_key_from_pem(&keypem)
		.map_err(|e| format!("client TLS key is unreadable: {}", e))?;
	if !certpub.public_eq(&key) {
		return Err(String::from("the issued certificate does not match the client TLS key"));
	}
	let path = client_crt_path();
	fs::write(&path, cert_pem.as_bytes()).map_err(|e| format!("unable to save the client certificate: {}", e))?;
	fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
		.map_err(|e| format!("unable to secure the client certificate: {}", e))?;
	dbout(debug, 3, "Client TLS certificate stored (config/client.crt).");
	Ok(())
}

// Client TLS certificate re-issue (protocol §7.1 v1.1): the fleet upgrade
// path for endpoints registered before P2P. Sent at startup when the
// endpoint is registered but has no client certificate on file. One-shot:
// a failure is logged and retried on the next start.
fn certrenew_with_server(debug: bool, ccfg: &HashMap<String, String>) {
	let uid = match ccfg.get("UID") { Some(u) => u.clone(), None => return };
	let (seed, pubb) = client_keypair(debug, ccfg);
	let csr = match tls_keypair_csr(debug) {
		Ok(c) => c,
		Err(err) => { dbout(debug, 2, &format!("Client TLS certificate re-issue skipped: {}", err)); return; }
	};
	let data = serde_json::json!({
		"fingerprint": fingerprint(&pubb),
		"tls_csr": base64ct::Base64::encode_string(csr.as_bytes())
	});
	let mut msg = new_envelope("client", &uid, "core", "certrenew", "noreg", Some(data));
	sign_envelope(&mut msg, &seed);
	let server_host = ccfg.get("SHOST").unwrap();
	let server_port = ccfg.get("SPORT").unwrap();

	match server_send_once(server_host, server_port, &crt_path(), &msg) {
		Ok(response) => {
			if response.action != "certrenew" {
				dbout(debug, 1, "Unexpected response to certificate re-issue request.");
				return;
			}
			// The response must be signed by the validated server signing
			// key (bootstrap trust anchor, protocol §7.1).
			let anchor = match server_signing_key(debug) {
				Some(k) => k,
				None => return,
			};
			if !verify_envelope(&response, &anchor) {
				dbout(debug, 1, "MSG_AUTH_FAIL: certificate re-issue response signature verification failed.");
				return;
			}
			if response.status != "OK" {
				dbout(debug, 2, &format!("Client TLS certificate re-issue failed: {} {}", response.status, response.err.unwrap_or_default()));
				return;
			}
			let b64cert = match response.data.as_ref().and_then(|d| d.get("clientcert")).and_then(|v| v.as_str()) {
				Some(b) => b,
				None => { dbout(debug, 1, "Certificate re-issue response did not include a certificate."); return; }
			};
			match base64ct::Base64::decode_vec(b64cert) {
				Ok(raw) => {
					let pem = String::from_utf8_lossy(&raw).into_owned();
					if let Err(err) = store_client_cert(debug, &pem) {
						dbout(debug, 1, &format!("Client TLS certificate not stored: {}", err));
					}
				}
				Err(_) => dbout(debug, 1, "Client TLS certificate in the re-issue response is not valid base64."),
			}
		}
		Err(err) => dbout(debug, 2, &format!("Unable to send certificate re-issue to server: {}", err)),
	}
}

// ---------------------------------------------------------------------------
// Server channel (bootstrap/direct, TLS + framed JSON)
// ---------------------------------------------------------------------------

// A hostname may resolve to several addresses (e.g. both IPv6 and IPv4);
// dial each in turn so a family the broker does not listen on cannot wedge
// the connection.
fn connect_any(addrs: &[SocketAddr], debug: bool) -> Result<TcpStream, Box<dyn Error>> {
	let mut last_err = String::new();
	for addr in addrs {
		match TcpStream::connect_timeout(addr, CONNECT_TIMEOUT) {
			Ok(sconn) => {
				dbout(debug, 4, &format!("Connected to Luminum server at {}", addr));
				return Ok(sconn);
			}
			Err(err) => {
				dbout(debug, 4, &format!("Connection to Luminum server failed ({}): {}", addr, err));
				last_err = err.to_string();
			}
		}
	}
	Err(last_err.into())
}

fn server_connect(server_host: &str, server_port: &str, cert_path: &str, debug: bool) -> Result<TlsStream<TcpStream>, Box<dyn Error>> {
	let server_addr_str = format!("{}:{}", server_host, server_port);
	let server_addrs: Vec<SocketAddr> = server_addr_str.to_socket_addrs()?.collect();
	if server_addrs.is_empty() {
		return Err("No addresses found for hostname".into());
	}

	let sconn = loop {
		match connect_any(&server_addrs, debug) {
			Ok(sconn) => break sconn,
			Err(err) => {
				dbout(debug, 2, &format!("Connection to Luminum server failed: {}", err));
				dbout(debug, 4, "Retrying connection in 30 seconds...");
				thread::sleep(Duration::from_secs(30));
			}
		}
	};

	// Bound the TLS handshake and every subsequent read/write on this
	// connection: a stalled handshake or a silent server cannot hang the
	// registration path. These OS-level socket timeouts apply to the
	// handshake's own reads/writes as well as the framed I/O that follows.
	sconn.set_read_timeout(Some(IO_TIMEOUT))?;
	sconn.set_write_timeout(Some(IO_TIMEOUT))?;

	let cert_buffer = fs::read(cert_path)?;
	let mut builder = TlsConnector::builder();
	builder.add_root_certificate(native_tls::Certificate::from_pem(&cert_buffer)?);
	let connector = builder.build()?;
	let server_stream = connector.connect(server_host, sconn)?;
	Ok(server_stream)
}

fn server_send(server_host: &str, server_port: &str, cert_path: &str, message: &Envelope, debug: bool) -> Result<Envelope, Box<dyn Error>> {
	let mut stream = server_connect(server_host, server_port, cert_path, debug)?;
	frame_write(&mut stream, message)?;
	let response = frame_read(&mut stream)?;
	Ok(response)
}

// ---------------------------------------------------------------------------
// Registration / check-in
// ---------------------------------------------------------------------------

fn register_with_server(debug: bool, ccfg: &HashMap<String, String>) {
	let endpointname = gethostname().to_string_lossy().into_owned();
	let ip_address = local_ip().map(|a| a.to_string()).unwrap_or_default();
	let (seed, pubb) = client_keypair(debug, ccfg);

	// Client TLS CSR (protocol §7.1 v1.1): the server signs it into the
	// endpoint's P2P channel certificate at registration. A failure here
	// does not block registration - the server completes it without a
	// clientcert and the client retries via certrenew on a later start.
	let tls_csr = match tls_keypair_csr(debug) {
		Ok(csr) => Some(base64ct::Base64::encode_string(csr.as_bytes())),
		Err(err) => {
			dbout(debug, 2, &format!("Client TLS CSR unavailable ({}); the certificate will be requested via certrenew on a later start.", err));
			None
		}
	};

	let mut data = serde_json::json!({
		"hostname": endpointname,
		"uuid": client_uuid(debug, ccfg),
		"serverkey": ccfg.get("SVRKEY").cloned().unwrap_or_default(),
		"uid": "0",
		"pubkey": base64ct::Base64::encode_string(spki_der(&pubb).as_slice()),
		"fingerprint": fingerprint(&pubb),
		"osplat": "Linux",
		"osrel": get_os_release(),
		"clientver": VER,
		"ipv4": ip_address
	});
	if let Some(csr) = tls_csr {
		data["tls_csr"] = serde_json::json!(csr);
	}

	let mut msg = new_envelope("client", "0", "core", "register", "noreg", Some(data));
	sign_envelope(&mut msg, &seed);
	let server_host = ccfg.get("SHOST").unwrap();
	let server_port = ccfg.get("SPORT").unwrap();

	match server_send(server_host, server_port, &crt_path(), &msg, debug) {
		Ok(response) => {
			if response.action == "register" && response.status == "OK" {
				// Bootstrap trust anchor (protocol §7.1): the server
				// signing key must come from the validated signing
				// certificate, not from the response. The in-band
				// serverpubkey field is a convenience and is
				// cross-checked against the anchor; a mismatch is fatal.
				let anchor = match server_signing_key(debug) {
					Some(k) => k,
					None => return,
				};
				if !verify_envelope(&response, &anchor) {
					dbout(debug, 1, "MSG_AUTH_FAIL: registration response signature verification failed.");
					return;
				}
				if let Some(b64) = response.data.as_ref()
					.and_then(|d| d.get("serverpubkey"))
					.and_then(|v| v.as_str()) {
					let inband = base64ct::Base64::decode_vec(b64).ok()
						.and_then(|der| spki_to_raw(&der));
					match inband {
						Some(raw) if raw == anchor => {}
						_ => {
							dbout(debug, 1, "MSG_AUTH_FAIL: serverpubkey does not match the signing certificate.");
							return;
						}
					}
				}
				config_set("SRVPUB", &base64ct::Base64::encode_string(&anchor));
				let data = response.data.as_ref();
				if let Some(uid) = data.and_then(|d| d.get("uid")).and_then(|v| v.as_str()) {
					config_set("UID", uid);
					dbout(debug, 3, &format!("Registration successful. (UID: {})", uid));
				} else {
					dbout(debug, 1, "Registration response did not include a UID.");
				}
				// MQTT broker credentials (protocol §7.1): the secret is
				// delivered only in this signed bootstrap response, and the
				// config DB's 0600 file mode is its protection at rest.
				if let Some(secret) = data.and_then(|d| d.get("mqttsecret")).and_then(|v| v.as_str()) {
					config_set("MQTTSECRET", secret);
				} else {
					dbout(debug, 1, "Registration response did not include an MQTT secret.");
				}
				if let Some(host) = data.and_then(|d| d.get("mqtthost")).and_then(|v| v.as_str()) {
					config_set("MQTTHOST", host);
				} else {
					dbout(debug, 1, "Registration response did not include an MQTT host.");
				}
				if let Some(port) = data.and_then(|d| d.get("mqttport")).and_then(|v| v.as_str()) {
					config_set("MQTTPORT", port);
				} else {
					dbout(debug, 1, "Registration response did not include an MQTT port.");
				}
				// Luminum Server ID (protocol §4.2): required to build the
				// MQTT topic tree luminum/{SID}/{UID}/... .
				if let Some(sid) = data.and_then(|d| d.get("sid")).and_then(|v| v.as_str()) {
					config_set("SID", sid);
				} else {
					dbout(debug, 1, "Registration response did not include a server ID (SID).");
				}
				// Client TLS certificate (protocol §7.1 v1.1): the server
				// signed the presented CSR into the P2P channel
				// certificate. Absent when the server could not issue one
				// (e.g. no CA material) - certrenew covers that later.
				if let Some(b64cert) = data.and_then(|d| d.get("clientcert")).and_then(|v| v.as_str()) {
					match base64ct::Base64::decode_vec(b64cert) {
						Ok(raw) => {
							let pem = String::from_utf8_lossy(&raw).into_owned();
							if let Err(err) = store_client_cert(debug, &pem) {
								dbout(debug, 1, &format!("Client TLS certificate not stored: {}", err));
							}
						}
						Err(_) => dbout(debug, 1, "Client TLS certificate in the registration response is not valid base64."),
					}
				}
			} else {
				dbout(debug, 1, &format!("Registration failed: {} {}", response.status, response.err.unwrap_or_default()));
			}
		}
		Err(err) => dbout(debug, 2, &format!("Unable to send registration to server: {}", err)),
	}
}

// One-shot variant of server_send for CLI flows (deregistration): a single
// connection attempt instead of the startup retry loop - a one-shot command
// reports an unreachable server instead of retrying for 30 seconds at a time
// until interrupted.
fn server_send_once(server_host: &str, server_port: &str, cert_path: &str, message: &Envelope) -> Result<Envelope, Box<dyn Error>> {
	let server_addr_str = format!("{}:{}", server_host, server_port);
	let server_addrs: Vec<SocketAddr> = server_addr_str.to_socket_addrs()?.collect();
	if server_addrs.is_empty() {
		return Err("No addresses found for hostname".into());
	}
	let mut sconn = connect_any(&server_addrs, false)
		.map_err(|err| format!("Connection to Luminum server failed: {}", err))?;
	// Same I/O bounds as server_connect: a stalled handshake or a silent
	// server must not hang a one-shot command (deregistration) forever.
	sconn.set_read_timeout(Some(IO_TIMEOUT))?;
	sconn.set_write_timeout(Some(IO_TIMEOUT))?;
	let cert_buffer = fs::read(cert_path)?;
	let mut builder = TlsConnector::builder();
	builder.add_root_certificate(native_tls::Certificate::from_pem(&cert_buffer)?);
	let connector = builder.build()?;
	let mut server_stream = connector.connect(server_host, sconn)?;
	frame_write(&mut server_stream, message)?;
	let response = frame_read(&mut server_stream)?;
	Ok(response)
}

// Deregistration probe (protocol §4.1): the MQTT broker's credential
// rejection alone cannot say why the credentials were refused, so ask the
// bootstrap channel - authenticated by per-message signature against the
// stored public key, independent of mosquitto's password_file - whether the
// server still recognizes this endpoint. A signed check-in under the
// client's UID receives:
//   OK                the endpoint is active; the server's MQTT credential
//                     store is out of sync (keep retrying; self-heals)
//   ERR DEACTIVATED   the record was deactivated (client-initiated
//                     unregister)
//   ERR BAD_SIGNATURE the AUTH record is gone (console Deregister)
// A connection that fails, times out, or answers anything else is
// undecidable. As with every server->client message (protocol §3.3), the
// response must verify against the server signing key; an unverifiable
// response is undecidable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DeregProbe { Active, Gone, Unknown }

fn dereg_probe(shost: &str, sport: &str, uid: &str, seed: &[u8; 32], checkin: u64, srvpub: Option<&[u8; 32]>) -> DeregProbe {
	let probe = build_checkin_envelope(uid, seed, checkin);
	match server_send_once(shost, sport, &crt_path(), &probe) {
		Ok(resp) if srvpub.map_or(false, |k| verify_envelope(&resp, k)) => {
			if resp.status == "OK" {
				DeregProbe::Active
			} else {
				match resp.err.as_deref() {
					Some("DEACTIVATED") | Some("BAD_SIGNATURE") => DeregProbe::Gone,
					_ => DeregProbe::Unknown,
				}
			}
		}
		_ => DeregProbe::Unknown,
	}
}

// Deregistration (protocol §6.1, core/unregister): the sanctioned uninstall
// flow. Sends a signed unregister request over the bootstrap channel; the
// server deactivates the endpoint's record (CSTATE = 'DEACT') and revokes
// its MQTT credentials. On a verified OK - or ERR DEACTIVATED, meaning the
// server has already deregistered this endpoint - the local configuration
// database is removed: the next installation starts fresh (new keypair, new
// UUID, new endpoint record). Any other outcome keeps the configuration so
// the operator can retry. The stored keypair is read, never regenerated: a
// client whose keypair is lost cannot authenticate a deregistration.
fn deregister_with_server(debug: bool) {
	let ccfg = parse_clientconfig(debug);
	let uid = match ccfg.get("UID") {
		Some(u) => u.clone(),
		None => {
			dbout(debug, 1, "Endpoint is not registered with the Luminum server. Nothing to deregister.");
			process::exit(1);
		}
	};
	let seed = match ccfg.get("CLPPRV") {
		Some(prv) => match base64ct::Base64::decode_vec(prv) {
			Ok(raw) if raw.len() == 32 => {
				let mut seed = [0u8; 32];
				seed.copy_from_slice(&raw);
				seed
			}
			_ => {
				dbout(debug, 1, "Stored client keypair is invalid; cannot authenticate the deregistration.");
				process::exit(1);
			}
		},
		None => {
			dbout(debug, 1, "No client signing keypair on file; cannot authenticate the deregistration.");
			process::exit(1);
		}
	};

	let mut msg = new_envelope("client", &uid, "core", "unregister", "noreg", None);
	sign_envelope(&mut msg, &seed);
	let server_host = ccfg.get("SHOST").unwrap();
	let server_port = ccfg.get("SPORT").unwrap();

	match server_send_once(server_host, server_port, &crt_path(), &msg) {
		Ok(response) => {
			if response.action != "unregister" {
				dbout(debug, 1, "Unexpected response to deregistration request.");
				process::exit(1);
			}
			// The response must be signed by the validated server signing
			// key (bootstrap trust anchor, protocol §7.1).
			let anchor = match server_signing_key(debug) {
				Some(k) => k,
				None => process::exit(1),
			};
			if !verify_envelope(&response, &anchor) {
				dbout(debug, 1, "MSG_AUTH_FAIL: deregistration response signature verification failed.");
				process::exit(1);
			}
			let already = response.status == "ERR" && response.err.as_deref() == Some("DEACTIVATED");
			if response.status != "OK" && !already {
				dbout(debug, 1, &format!("Deregistration failed: {} {}", response.status, response.err.unwrap_or_default()));
				process::exit(1);
			}
			// Server-side deactivation confirmed: remove the local
			// configuration (keypair, UUID, registration, credentials).
			if let Err(err) = fs::remove_file(cfg_path()) {
				dbout(debug, 1, &format!("Deregistered on the server, but the local configuration could not be removed: {}", err));
				dbout(debug, 1, "Remove the configuration database manually to complete the uninstall.");
				process::exit(1);
			}
			dbout(debug, 3, "Endpoint deregistered. Local configuration removed.");
			dbout(debug, 4, "The next installation will register as a new endpoint.");
		}
		Err(err) => {
			dbout(debug, 1, &format!("Unable to send deregistration to server: {}", err));
			process::exit(1);
		}
	}
}

// ---------------------------------------------------------------------------
// Sensors (protocol §6.1, §7.3)
//
// The client-side home for sensor definitions. The server delivers them in a
// core/config command (data.sensors) immediately before the core/query that
// uses them; the client upserts each entry into the SENSORS table of its
// config DB and later executes the named sensors, answering with their
// output.
// ---------------------------------------------------------------------------

// Ensure the SENSORS table exists in the client config DB.
fn ensure_sensors_table(debug: bool) {
	let conn = match Connection::open(cfg_path()) {
		Ok(conn) => conn,
		Err(err) => {
			dbout(debug, 1, &format!("Could not open the configuration database for the sensor table: {}", err));
			return;
		}
	};
	conn.execute(
		"create table if not exists SENSORS ( SID integer not null primary key, NAME text not null, LSTYPE text not null, LSCRIPT text not null )",
		[],
	).expect("Error: Could not create the SENSORS table.");
	conn.close().unwrap();
}

// The sensors currently on file: SID -> (script type, script) for this
// platform (the SENSORS table stores this client's own pair).
fn sensor_definitions(debug: bool) -> HashMap<i64, (String, String)> {
	let mut defs: HashMap<i64, (String, String)> = HashMap::new();
	let conn = match Connection::open(cfg_path()) {
		Ok(conn) => conn,
		Err(err) => {
			dbout(debug, 1, &format!("Could not open the configuration database for sensors: {}", err));
			return defs;
		}
	};
	let mut stmt = match conn.prepare("select SID, LSTYPE, LSCRIPT from SENSORS") {
		Ok(stmt) => stmt,
		Err(err) => {
			dbout(debug, 1, &format!("Could not read the SENSORS table: {}", err));
			return defs;
		}
	};
	let rows = match stmt.query_map(params![], |row| {
		Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?))
	}) {
		Ok(rows) => rows,
		Err(err) => {
			dbout(debug, 1, &format!("Could not read the SENSORS table: {}", err));
			return defs;
		}
	};
	for row in rows {
		if let Ok((sid, lstype, lscript)) = row {
			defs.insert(sid, (lstype, lscript));
		}
	}
	defs
}

// This client's script pair for one config entry (protocol §7.3): the Linux
// client runs the Linux pair (lstype/lscript) and nothing else.
// Ok(Some(pair)) is a sensor defined for this OS; Ok(None) is a sensor the
// server did not define for this OS (a broadcast config carries the query's
// sensors for every platform, so this is normal and the entry is skipped);
// Err is a pair that is present but malformed (INVALID_DATA).
fn sensor_pair_for_this_os(entry: &serde_json::Value) -> Result<Option<(String, String)>, ()> {
	let lstype = entry.get("lstype").and_then(|v| v.as_str());
	let lscript = entry.get("lscript").and_then(|v| v.as_str());
	match (lstype, lscript) {
		(None, _) | (_, None) => Ok(None),
		(Some(t), Some(s)) => {
			if (t == "shell" || t == "perl" || t == "python") && !s.is_empty() {
				Ok(Some((t.to_string(), s.to_string())))
			} else {
				Err(())
			}
		}
	}
}

// core/config (protocol §6.1, §7.3): the server pushes the sensor
// definitions this endpoint will be asked to run. data.sensors is an array
// of {sid, name, lstype, lscript, mstype, mscript, wstype, wscript}; this
// client stores only the pair for its own OS and skips sensors the server
// did not define for it. Returns an error string for the response envelope,
// or None when applied.
fn apply_sensor_config(env: &Envelope, debug: bool) -> Option<String> {
	let list = match env.data.as_ref().and_then(|d| d.get("sensors")).and_then(|v| v.as_array()) {
		Some(list) => list,
		None => return Some(String::from("INVALID_DATA")),
	};
	let mut defs: Vec<(i64, String, String, String)> = Vec::new();
	for entry in list {
		let sid = match entry.get("sid").and_then(|v| v.as_i64()) {
			Some(s) if s > 0 && s <= i32::MAX as i64 => s,
			_ => return Some(String::from("INVALID_DATA")),
		};
		let name = match entry.get("name").and_then(|v| v.as_str()) {
			Some(n) if !n.is_empty() => n.to_string(),
			_ => return Some(String::from("INVALID_DATA")),
		};
		let (lstype, lscript) = match sensor_pair_for_this_os(entry) {
			Ok(Some(pair)) => pair,
			Ok(None) => continue,
			Err(()) => return Some(String::from("INVALID_DATA")),
		};
		defs.push((sid, name, lstype, lscript));
	}
	let conn = match Connection::open(cfg_path()) {
		Ok(conn) => conn,
		Err(_) => return Some(String::from("DB_ERROR")),
	};
	let mut stmt = match conn.prepare("insert or replace into SENSORS (SID,NAME,LSTYPE,LSCRIPT) values (?1,?2,?3,?4)") {
		Ok(stmt) => stmt,
		Err(_) => return Some(String::from("DB_ERROR")),
	};
	for (sid, name, lstype, lscript) in &defs {
		if stmt.execute(params![sid, name, lstype, lscript]).is_err() {
			return Some(String::from("DB_ERROR"));
		}
	}
	dbout(debug, 3, &format!("sensor definitions applied ({} sensor(s))", defs.len()));
	None
}

// core/setcheckinint (protocol §6.1, §7.2): the server directs the check-in
// interval. data.checkin_secs is the interval in seconds; it is persisted
// (CHECKIN_SECS) so it survives restarts, and applied to the check-in task
// immediately (the next check-in uses the new cadence).
fn apply_checkinint(env: &Envelope, checkin_interval: &Arc<AtomicU64>, debug: bool) -> Option<String> {
	let secs = match env.data.as_ref().and_then(|d| d.get("checkin_secs")).and_then(|v| v.as_u64()) {
		Some(s) if (1..=86400).contains(&s) => s,
		_ => return Some(String::from("INVALID_DATA")),
	};
	config_set("CHECKIN_SECS", &secs.to_string());
	checkin_interval.store(secs, Ordering::SeqCst);
	dbout(debug, 3, &format!("check-in interval set to {}s (server config)", secs));
	None
}

// A UUID v4 in the envelope id format (protocol §5.1).
fn is_uuid4(s: &str) -> bool {
	let b = s.as_bytes();
	b.len() == 36
		&& b[8] == b'-' && b[13] == b'-' && b[18] == b'-' && b[23] == b'-'
		&& b[0..8].iter().all(|c| c.is_ascii_hexdigit())
		&& b[9..13].iter().all(|c| c.is_ascii_hexdigit())
		&& b[14..18].iter().all(|c| c.is_ascii_hexdigit())
		&& b[19..23].iter().all(|c| c.is_ascii_hexdigit())
		&& b[24..36].iter().all(|c| c.is_ascii_hexdigit())
}

// Normalize the script's line endings to LF before running it. The console
// stores scripts with LF endings, but rows saved before that fix (or via
// other input paths) may carry CRLF/CR, and a stray \r breaks a script read
// on the interpreter's stdin ("then\r" and "fi\r" are syntax errors in sh).
fn normalize_newlines(script: &str) -> String {
	script.replace("\r\n", "\n").replace('\r', "\n")
}

// Run one sensor script to completion: $prog is the interpreter for the
// stored LSTYPE, and the script rides on stdin (shell, perl, and python all
// read a script from stdin).
async fn run_sensor_script(prog: &str, script: &str) -> Result<String, Box<dyn Error>> {
	use tokio::io::AsyncWriteExt;
	use tokio::process::Command;
	let mut child = Command::new(prog)
		.stdin(Stdio::piped())
		.stdout(Stdio::piped())
		.stderr(Stdio::piped())
		.kill_on_drop(true)
		.spawn()?;
	if let Some(mut stdin) = child.stdin.take() {
		stdin.write_all(script.as_bytes()).await?;
	}
	let out = child.wait_with_output().await?;
	if !out.status.success() {
		return Err(Box::from(format!("exit status: {}", out.status)));
	}
	Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

// Execute one sensor of a query; returns its results entry: {sid, output}
// on success, {sid, err} on failure (protocol §6.1). Parameter injection
// (§7.3): the server resolved the final values (defaults merged); the client
// substitutes each ${name} point in the script.
async fn run_sensor(sid: i64, params: &HashMap<String, String>, defs: &HashMap<i64, (String, String)>, debug: bool) -> serde_json::Value {
	let (lstype, lscript) = match defs.get(&sid) {
		Some(def) => def,
		None => return serde_json::json!({ "sid": sid, "err": "UNKNOWN_SENSOR" }),
	};
	let prog = match lstype.as_str() {
		"shell" => "/bin/sh",
		"perl" => "perl",
		"python" => "python3",
		_ => return serde_json::json!({ "sid": sid, "err": "UNKNOWN_SENSOR" }),
	};
	let mut script = lscript.clone();
	for (k, v) in params {
		script = script.replace(&format!("${{{}}}", k), v);
	}
	script = normalize_newlines(&script);
	match tokio::time::timeout(Duration::from_secs(SENSOR_TIMEOUT_SECS), run_sensor_script(prog, &script)).await {
		Ok(Ok(output)) => serde_json::json!({ "sid": sid, "output": output }),
		Ok(Err(err)) => {
			dbout(debug, 1, &format!("sensor {} failed to run: {}", sid, err));
			serde_json::json!({ "sid": sid, "err": "EXEC_ERROR" })
		}
		Err(_) => {
			dbout(debug, 1, &format!("sensor {} timed out after {}s", sid, SENSOR_TIMEOUT_SECS));
			serde_json::json!({ "sid": sid, "err": "TIMEOUT" })
		}
	}
}

// Compare a sensor output to a condition value (protocol §7.3): numerically
// when both sides parse as finite numbers, otherwise as case-insensitive
// strings, with =~ / !~ as substring tests.
fn cond_compare(out: &str, op: &str, value: &str) -> bool {
	let a = out.trim();
	let b = value.trim();
	let (na, nb): (Option<f64>, Option<f64>) = (
		a.parse::<f64>().ok().filter(|x| x.is_finite()),
		b.parse::<f64>().ok().filter(|x| x.is_finite()),
	);
	let numeric = na.is_some() && nb.is_some();
	let (la, lb) = (a.to_ascii_lowercase(), b.to_ascii_lowercase());
	match op {
		"==" => { if numeric { na.unwrap() == nb.unwrap() } else { la == lb } }
		"!=" => { if numeric { na.unwrap() != nb.unwrap() } else { la != lb } }
		"=~" => la.contains(&lb),
		"!~" => !la.contains(&lb),
		">" => { if numeric { na.unwrap() > nb.unwrap() } else { la > lb } }
		">=" => { if numeric { na.unwrap() >= nb.unwrap() } else { la >= lb } }
		"<" => { if numeric { na.unwrap() < nb.unwrap() } else { la < lb } }
		"<=" => { if numeric { na.unwrap() <= nb.unwrap() } else { la <= lb } }
		_ => false, // an unknown operator cannot match
	}
}

// Evaluate a query condition tree against this endpoint (protocol §7.3).
// A leaf runs its condition sensor and compares the output to the value; a
// leaf whose sensor is unknown to the endpoint or fails to run evaluates
// false, so the endpoint stays silent rather than answering a query it
// cannot filter.
async fn eval_condition(node: &serde_json::Value, defs: &HashMap<i64, (String, String)>, debug: bool) -> bool {
	if let Some(logic) = node.get("logic").and_then(|v| v.as_str()) {
		let (left, right) = match (node.get("left"), node.get("right")) {
			(Some(l), Some(r)) => (l, r),
			_ => return false,
		};
		let l = Box::pin(eval_condition(left, defs, debug)).await;
		let r = Box::pin(eval_condition(right, defs, debug)).await;
		return if logic == "AND" { l && r } else { l || r };
	}
	let sid = match node.get("sid").and_then(|v| v.as_i64()) {
		Some(s) if s > 0 => s,
		_ => return false,
	};
	let op = match node.get("op").and_then(|v| v.as_str()) {
		Some(o) => o.to_string(),
		None => return false,
	};
	let value = match node.get("value").and_then(|v| v.as_str()) {
		Some(v) => v.to_string(),
		None => return false,
	};
	let mut params: HashMap<String, String> = HashMap::new();
	if let Some(obj) = node.get("params").and_then(|v| v.as_object()) {
		for (k, v) in obj {
			if let Some(s) = v.as_str() { params.insert(k.clone(), s.to_string()); }
		}
	}
	match run_sensor(sid, &params, defs, debug).await.get("output").and_then(|v| v.as_str()) {
		Some(out) => cond_compare(out, &op, &value),
		None => {
			dbout(debug, 3, &format!("condition sensor {} did not run; treating as non-matching", sid));
			false
		}
	}
}

// core/query (protocol §6.1, §7.3): execute the named sensors and build the
// answer envelope (action=answer, data.qid echoed, one results entry per
// sensor). A malformed query is answered with the qid echoed when it is
// recoverable, so the server can still correlate it. An answer that would
// exceed the 64 KiB MQTT cap comes back as ERR/OUTPUT_TOO_LARGE until the
// data channel (§8.3) is in place. When the query carries a condition tree
// that evaluates false on this endpoint, a NO_MATCH answer is returned
// (data.qid echoed, no results): the server records it so it knows this
// endpoint processed the query (§7.3).
async fn apply_query(env: &Envelope, uid: &str, debug: bool) -> Option<Envelope> {
	let (qid, sensors) = match env.data.as_ref() {
		Some(d) => {
			let qid = match d.get("qid").and_then(|v| v.as_str()).filter(|q| is_uuid4(q)) {
				Some(q) => q.to_string(),
				None => return Some(query_err(uid, None, "INVALID_DATA")),
			};
			match d.get("sensors").and_then(|v| v.as_array()) {
				Some(list) if !list.is_empty() => (qid, list.clone()),
				_ => return Some(query_err(uid, Some(&qid), "INVALID_DATA")),
			}
		}
		None => return Some(query_err(uid, None, "INVALID_DATA")),
	};
	let defs = sensor_definitions(debug);
	// Condition filtering (§7.3): before running any retrieve sensor, an
	// endpoint on which the tree evaluates false answers NO_MATCH (no
	// results) so the server knows it processed the query.
	if let Some(conds) = env.data.as_ref().and_then(|d| d.get("conditions")) {
		if !eval_condition(conds, &defs, debug).await {
			dbout(debug, 3, &format!("query {} conditions not met on this endpoint; answering NO_MATCH", qid));
			return Some(query_no_match(uid, &qid));
		}
	}
	let mut results: Vec<serde_json::Value> = Vec::new();
	let mut ok_count = 0usize;
	for entry in sensors {
		let sid = match entry.get("sid").and_then(|v| v.as_i64()).filter(|s| *s > 0) {
			Some(sid) => sid,
			None => {
				results.push(serde_json::json!({
					"sid": entry.get("sid").cloned().unwrap_or(serde_json::Value::Null),
					"err": "INVALID_DATA"
				}));
				continue;
			}
		};
		let mut params: HashMap<String, String> = HashMap::new();
		let params_ok = match entry.get("params") {
			None | Some(serde_json::Value::Null) => true,
			Some(serde_json::Value::Object(obj)) => {
				let mut ok = true;
				for (k, v) in obj {
					if k.is_empty() || k.len() > 64 || !k.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
						ok = false;
						break;
					}
					match v.as_str() {
						Some(s) if s.len() <= 1024 => { params.insert(k.clone(), s.to_string()); }
						_ => { ok = false; break; }
					}
				}
				ok
			}
			Some(_) => false,
		};
		if !params_ok {
			results.push(serde_json::json!({ "sid": sid, "err": "INVALID_DATA" }));
			continue;
		}
		let result = run_sensor(sid, &params, &defs, debug).await;
		if result.get("output").is_some() {
			ok_count += 1;
		}
		results.push(result);
	}
	let status = if ok_count == results.len() { "OK" } else if ok_count > 0 { "PARTIAL" } else { "ERR" };
	let mut resp = new_envelope("client", uid, "core", "answer", status, Some(serde_json::json!({ "qid": qid, "results": results })));
	if status == "ERR" {
		resp.err = Some(String::from("SENSOR_ERROR"));
	}
	let payload = serde_json::to_vec(&resp).expect("Error: unable to serialize the answer envelope");
	if payload.len() > 65536 {
		let mut oob = new_envelope("client", uid, "core", "answer", "ERR", Some(serde_json::json!({ "qid": qid })));
		oob.err = Some(String::from("OUTPUT_TOO_LARGE"));
		dbout(debug, 1, &format!("answer for qid {} is {} bytes, over the MQTT limit; reporting OUTPUT_TOO_LARGE", qid, payload.len()));
		return Some(oob);
	}
	Some(resp)
}

// A malformed query is answered on the answer action, echoing the qid when
// one was recoverable so the server can still correlate by data.qid.
fn query_err(uid: &str, qid: Option<&str>, err: &str) -> Envelope {
	let mut resp = new_envelope("client", uid, "core", "answer", "ERR", qid.map(|q| serde_json::json!({ "qid": q })));
	resp.err = Some(err.to_string());
	resp
}

// The no-match answer (protocol §7.3): the query's condition tree evaluated
// false on this endpoint, so it carries the qid (for correlation) and no
// results. The server records it per endpoint; it is not an answer, so it
// does not complete the command.
fn query_no_match(uid: &str, qid: &str) -> Envelope {
	new_envelope("client", uid, "core", "answer", "NO_MATCH", Some(serde_json::json!({ "qid": qid })))
}

// ---------------------------------------------------------------------------
// MQTT control channel (protocol §4)
// ---------------------------------------------------------------------------

// Check-in interval (seconds). The server is the source of truth (protocol
// §7.2): once it has delivered an interval, the persisted CHECKIN_SECS wins.
// Until the first delivery, LUMINUM_CHECKIN_SECS (testing) or the built-in
// default applies. Protocol §4.4: status check-ins are QoS 0, retained.
fn checkin_secs(ccfg: &HashMap<String, String>) -> u64 {
	if let Some(secs) = ccfg.get("CHECKIN_SECS").and_then(|v| v.parse().ok()) {
		if secs > 0 { return secs; }
	}
	std::env::var("LUMINUM_CHECKIN_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(CHECKIN_SECS)
}

// Build and sign a check-in envelope (protocol §6.1: action=checkin,
// status=OK). checkin is the interval the client is currently using
// (seconds); the server compares it with its own CHECKININT and pushes a
// correction when they differ (protocol §7.2).
fn build_checkin_envelope(uid: &str, seed: &[u8; 32], checkin: u64) -> Envelope {
	let endpointname = gethostname().to_string_lossy().into_owned();
	let ip_address = local_ip().map(|a| a.to_string()).unwrap_or_default();
	let data = serde_json::json!({
		"hostname": endpointname,
		"osplat": OSPLAT,
		"osrel": get_os_release(),
		"clientver": VER,
		"ipv4": ip_address,
		"checkin_secs": checkin
	});
	let mut msg = new_envelope("client", uid, "core", "checkin", "OK", Some(data));
	sign_envelope(&mut msg, seed);
	msg
}

// The check-in envelope's JSON wire bytes (the MQTT status topic payload).
fn build_checkin(uid: &str, seed: &[u8; 32], checkin: u64) -> Vec<u8> {
	serde_json::to_vec(&build_checkin_envelope(uid, seed, checkin)).expect("Error: unable to serialize check-in envelope")
}

// Build the MQTT control channel client (protocol §4): connection
// parameters, the pre-signed offline LWT, and the TLS trust anchor. Returns
// the AsyncClient (cloneable; shared with the data channel's report path),
// the event loop that drives it, and the shared connection flag. None when
// the control channel cannot start (missing parameters or trust anchor);
// the client keeps running (IPC, Lumys, data listener).
fn mqtt_client(debug: bool, ccfg: &HashMap<String, String>) -> Option<(rumqttc::AsyncClient, rumqttc::EventLoop, Arc<AtomicBool>)> {
	use rumqttc::{AsyncClient, LastWill, MqttOptions, QoS, Transport};

	// MQTT connection parameters (protocol §4.1). A missing value means the
	// control channel cannot start.
	let uid = match ccfg.get("UID") { Some(v) => v.clone(), None => return None };
	let sid = match ccfg.get("SID") { Some(v) => v.clone(), None => { dbout(debug, 1, "No server ID (SID) on file; MQTT control channel unavailable."); return None; } };
	let secret = match ccfg.get("MQTTSECRET") { Some(v) => v.clone(), None => { dbout(debug, 1, "No MQTT secret on file; MQTT control channel unavailable."); return None; } };
	let host = match ccfg.get("MQTTHOST") { Some(v) => v.clone(), None => { dbout(debug, 1, "No MQTT host on file; MQTT control channel unavailable."); return None; } };
	let port: u16 = match ccfg.get("MQTTPORT").and_then(|p| p.parse().ok()) { Some(p) => p, None => { dbout(debug, 1, "No valid MQTT port on file; MQTT control channel unavailable."); return None; } };

	let (seed, _clpub) = client_keypair(debug, ccfg);

	// LWT: a pre-signed offline envelope (protocol §7.5), retained, QoS 1.
	// Re-sent in the CONNECT packet on every (re)connect.
	let status_topic = format!("luminum/{}/{}/status", sid, uid);
	let mut offline = new_envelope("client", &uid, "core", "checkin", "offline", None);
	sign_envelope(&mut offline, &seed);
	let offline_payload = serde_json::to_vec(&offline).expect("Error: unable to serialize LWT envelope");
	let will = LastWill::new(&status_topic, offline_payload, QoS::AtLeastOnce, true);

	// TLS trust anchor: the server certificate (config/server.crt).
	let ca = match fs::read(crt_path()) {
		Ok(c) => c,
		Err(_) => { dbout(debug, 1, "Server certificate not found (config/server.crt); MQTT control channel unavailable."); return None; }
	};

	let mut mopts = MqttOptions::new(&uid, &host, port);
	mopts.set_transport(Transport::tls(ca, None, None));
	mopts.set_credentials(&uid, &secret);
	mopts.set_clean_session(false);
	mopts.set_keep_alive(Duration::from_secs(60));
	mopts.set_max_packet_size(65536, 65536);
	mopts.set_last_will(will);

	let (client, eventloop) = AsyncClient::new(mopts, 100);
	let connected = Arc::new(AtomicBool::new(false));
	Some((client, eventloop, connected))
}

// The client's long-lived MQTT control channel (protocol §4): connects to the
// broker over TLS with username/password auth, a persistent session, and a
// pre-signed offline LWT; subscribes to its command topic; publishes periodic
// check-ins on the status topic; and processes incoming commands. Reconnects
// automatically on failure (poll() re-establishes the connection).
async fn mqtt_run(debug: bool, ccfg: HashMap<String, String>, mqtt: Option<(rumqttc::AsyncClient, rumqttc::EventLoop, Arc<AtomicBool>)>) {
	use rumqttc::{ConnectReturnCode, ConnectionError, Event, Packet, QoS};

	// A missing control channel (unregistered endpoint, missing parameters)
	// is a no-op: the client keeps running (IPC, Lumys, data listener).
	let (client, mut eventloop, connected) = match mqtt {
		Some(m) => m,
		None => return,
	};

	// MQTT connection parameters (protocol §4.1).
	let uid = match ccfg.get("UID") { Some(v) => v.clone(), None => return };
	let sid = match ccfg.get("SID") { Some(v) => v.clone(), None => return };

	let (seed, _clpub) = client_keypair(debug, &ccfg);
	let srvpub = server_pubkey(&ccfg);

	// Topic tree (protocol §4.2). The client subscribes to its own command
	// topic plus the group command topics it belongs to: all endpoints, its OS,
	// and any custom groups (GROUPS = comma-separated names, set by the server
	// via a setgroups command). Groups carry commands only (server -> client);
	// responses/check-ins always go to the per-UID topics below.
	let status_topic = format!("luminum/{}/{}/status", sid, uid);
	let resp_topic = format!("luminum/{}/{}/resp", sid, uid);
	let events_topic = format!("luminum/{}/{}/events", sid, uid);
	let mut cmd_topics: Vec<String> = vec![
		format!("luminum/{}/{}/cmd", sid, uid),
		format!("luminum/{}/all/cmd", sid),
		format!("luminum/{}/os/{}/cmd", sid, OSPLAT.to_lowercase()),
	];
	if let Some(groups) = ccfg.get("GROUPS") {
		for g in groups.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()) {
			cmd_topics.push(format!("luminum/{}/grp/{}/cmd", sid, g));
		}
	}

	// Check-in interval (seconds), shared with the check-in subtask. The
	// server can change it via core/setcheckinint (protocol §7.2); the
	// persisted value (CHECKIN_SECS) is the source of truth once delivered.
	let checkin_interval = Arc::new(AtomicU64::new(checkin_secs(&ccfg)));

	// Periodic check-ins (protocol §4.4). Gated on connection state so no
	// check-ins accumulate in the request channel while offline. The interval
	// is re-read every tick so a server-directed change applies from the next
	// check-in (protocol §7.2).
	let checkin_client = client.clone();
	let checkin_seed = seed;
	let checkin_uid = uid.clone();
	let checkin_topic = status_topic.clone();
	let checkin_flag = connected.clone();
	let checkin_interval_task = checkin_interval.clone();
	spawn(async move {
		let mut interval = time::interval(Duration::from_secs(checkin_interval_task.load(Ordering::SeqCst)));
		loop {
			interval.tick().await;
			let current = checkin_interval_task.load(Ordering::SeqCst);
			if interval.period().as_secs() != current {
				interval.reset_after(Duration::from_secs(current));
			}
			if !checkin_flag.load(Ordering::SeqCst) { continue; }
			let payload = build_checkin(&checkin_uid, &checkin_seed, current);
			let _ = checkin_client.publish(checkin_topic.clone(), QoS::AtMostOnce, true, payload).await;
		}
	});

	// Command deduplication (protocol §9.2): bounded ring of recent message ids.
	let mut seen: VecDeque<String> = VecDeque::with_capacity(1024);

	// Deregistration probe state (protocol §4.1): last probe time and the
	// verdict it reached, so a persistent credential refusal neither re-logs
	// nor re-probes on every 30s retry.
	let mut last_probe: Option<Instant> = None;
	let mut last_verdict: DeregProbe = DeregProbe::Unknown;

	let host = ccfg.get("MQTTHOST").map(|s| s.as_str()).unwrap_or("?");
	let port = ccfg.get("MQTTPORT").map(|s| s.as_str()).unwrap_or("?");
	dbout(debug, 3, &format!("MQTT control channel starting ({}:{}, UID {})", host, port, uid));
	loop {
		match eventloop.poll().await {
			Ok(Event::Incoming(Packet::ConnAck(_))) => {
				connected.store(true, Ordering::SeqCst);
				dbout(debug, 3, &format!("MQTT connected; subscribing to {} command topic(s)", cmd_topics.len()));
				for topic in &cmd_topics {
					if let Err(err) = client.subscribe(topic, QoS::AtLeastOnce).await {
						dbout(debug, 1, &format!("MQTT subscribe failed ({}): {}", topic, err));
					}
				}
				// Immediate check-in on (re)connect: lets the server see us
				// promptly and overwrites any stale retained offline status.
				let payload = build_checkin(&uid, &seed, checkin_interval.load(Ordering::SeqCst));
				let _ = client.publish(&status_topic, QoS::AtMostOnce, true, payload).await;
				// Flush any events queued while the control channel was down
				// (protocol §9.1): re-publish to the per-UID events topic, then
				// mark them sent.
				drain_outqueue(&client, &events_topic, &uid, &seed, debug).await;
			}
			Ok(Event::Incoming(Packet::Publish(p))) => {
				if !cmd_topics.contains(&p.topic) { continue; }
				let Ok(text) = std::str::from_utf8(&p.payload) else { continue };
				let Ok(env) = serde_json::from_str::<Envelope>(text) else { continue };
				// Verify the server's signature (protocol §3.3).
				let Some(srvpub) = &srvpub else {
					dbout(debug, 1, "No server signing key on file; cannot verify command.");
					continue;
				};
				if !verify_envelope(&env, srvpub) {
					dbout(debug, 1, "MSG_AUTH_FAIL: command signature verification failed.");
					continue;
				}
				// Deduplicate by message id (protocol §9.2).
				if seen.contains(&env.id) { continue; }
				seen.push_back(env.id.clone());
				while seen.len() > 1024 { seen.pop_front(); }
				dbout(debug, 3, &format!("MQTT command received: lumy={} action={}", env.lumy, env.action));
				// Apply the command (protocol 6) and build the response
				// envelope; the response is signed and published on the
				// per-UID resp topic (the server's worker correlates it back
				// to the outbox: setgroups/config by action, answers by
				// data.qid). A query whose conditions do not match on this
				// endpoint is answered NO_MATCH (§7.3).
				if let Some(mut resp) = handle_command(&client, &mut cmd_topics, &env, &uid, &sid, &checkin_interval, debug).await {
					sign_envelope(&mut resp, &seed);
					let payload = serde_json::to_vec(&resp).expect("Error: unable to serialize response");
					if let Err(err) = client.publish(&resp_topic, QoS::AtLeastOnce, false, payload).await {
						dbout(debug, 1, &format!("MQTT response publish failed: {}", err));
					}
				}
			}
			Ok(_) => {}
			Err(ConnectionError::ConnectionRefused(code)) => {
				connected.store(false, Ordering::SeqCst);
				// Both credential-refusal connack codes: 4 (bad username or
				// password) and 5 (not authorized) - brokers differ on which
				// they send for a rejected password_file entry.
				let credential_refusal = matches!(code, ConnectReturnCode::BadUserNamePassword | ConnectReturnCode::NotAuthorized);
				if !credential_refusal {
					// Protocol version, client id, or broker unavailability:
					// a configuration or broker-state problem, not a
					// credential revocation - retry as before.
					dbout(debug, 1, &format!("MQTT connection refused (code {:?}); check credentials.", code));
					time::sleep(Duration::from_secs(30)).await;
					continue;
				}
				// A credential refusal is the broker's authoritative "this
				// identity is not accepted"; retrying the same secret cannot
				// change it. Ask the bootstrap channel (signature-
				// authenticated, independent of the MQTT password store)
				// what the server thinks of this endpoint, rate-limited so a
				// persistent refusal cannot turn the probe into its own
				// retry loop.
				let due = last_probe.map_or(true, |t| Instant::now().duration_since(t) >= PROBE_EVERY);
				if due {
					last_probe = Some(Instant::now());
					let (shost, sport) = (ccfg.get("SHOST").cloned(), ccfg.get("SPORT").cloned());
					last_verdict = match (shost, sport) {
						(Some(h), Some(p)) => {
							let (uid, seed, checkin, srv) = (uid.clone(), seed, checkin_interval.load(Ordering::SeqCst), srvpub);
							// server_send_once is blocking (bounded by
							// CONNECT_TIMEOUT/IO_TIMEOUT); keep it off the
							// async runtime.
							tokio::task::spawn_blocking(move || dereg_probe(&h, &p, &uid, &seed, checkin, srv.as_ref()))
								.await
								.unwrap_or(DeregProbe::Unknown)
						}
						_ => DeregProbe::Unknown,
					};
				}
				match last_verdict {
					DeregProbe::Gone => {
						dbout(debug, 1, "MQTT credentials rejected and the server no longer recognizes this endpoint: it has been deregistered. The MQTT control channel will not retry; reinstall or re-provision the client to register a new endpoint.");
						break;
					}
					DeregProbe::Active => {
						if due {
							dbout(debug, 1, "MQTT credentials rejected, but the server accepted the bootstrap check-in: the server's MQTT credential store is likely out of sync. Retrying.");
						}
						time::sleep(Duration::from_secs(30)).await;
					}
					DeregProbe::Unknown => {
						if due {
							dbout(debug, 1, "MQTT credentials rejected and the bootstrap probe reached no verdict. Retrying slowly.");
						}
						time::sleep(SLOW_RETRY).await;
					}
				}
			}
			Err(err) => {
				connected.store(false, Ordering::SeqCst);
				dbout(debug, 2, &format!("MQTT connection error: {} (reconnecting)", err));
				time::sleep(Duration::from_secs(5)).await;
			}
		}
	}
}

// Dispatch a verified command and build its response envelope (protocol 6).
// The response is signed and published by the caller. Core actions:
// setgroups/setcheckinint/config/query are applied (a query whose conditions
// do not match is answered NO_MATCH, §7.3); deploy awaits the data channel
// (§8.3); client-originated actions and unknown actions/lumys are rejected
// per §6.3. Lumy namespaces are routed over MQTT as a follow-on (§6.2);
// until then a non-core lumy is answered UNKNOWN_LUMY.
async fn handle_command(
	client: &rumqttc::AsyncClient,
	cmd_topics: &mut Vec<String>,
	env: &Envelope,
	uid: &str,
	sid: &str,
	checkin_interval: &Arc<AtomicU64>,
	debug: bool,
) -> Option<Envelope> {
	if env.lumy != "core" {
		return Some(cmd_error(uid, &env.lumy, &env.action, "UNKNOWN_LUMY"));
	}
	match env.action.as_str() {
		"setgroups" => match apply_setgroups(client, cmd_topics, env, sid, debug).await {
			Some(err) => Some(cmd_error(uid, &env.lumy, &env.action, &err)),
			None => Some(cmd_ok(uid, &env.lumy, &env.action)),
		},
		"setcheckinint" => match apply_checkinint(env, checkin_interval, debug) {
			Some(err) => Some(cmd_error(uid, &env.lumy, &env.action, &err)),
			None => Some(cmd_ok(uid, &env.lumy, &env.action)),
		},
		"config" => match apply_sensor_config(env, debug) {
			Some(err) => Some(cmd_error(uid, &env.lumy, &env.action, &err)),
			None => Some(cmd_ok(uid, &env.lumy, &env.action)),
		},
		// A query whose conditions do not match is answered NO_MATCH (§7.3).
		"query" => apply_query(env, uid, debug).await,
		// The transfer runs on the data channel (10704, docs/p2p.md 3): the
		// server pushes under the grant embedded in the command's ref, and
		// the data session reports the outcome (p2p_fetch_ok/fail). The
		// command is acknowledged here; a command without the grant form is
		// rejected.
		"deploy" => {
			let refv = env.data.as_ref().and_then(|d| d.get("ref"));
			let ok = refv.and_then(|r| r.get("channel")).and_then(|c| c.as_str()) == Some("p2p")
				&& refv.and_then(|r| r.get("grant")).is_some();
			if ok {
				Some(cmd_ok(uid, &env.lumy, &env.action))
			} else {
				Some(cmd_error(uid, &env.lumy, &env.action, "INVALID_DATA"))
			}
		}
		// Client-originated actions (protocol §6.1): never valid on a cmd topic.
		"register" | "checkin" | "unregister" | "report" | "answer" => {
			Some(cmd_error(uid, &env.lumy, &env.action, "INVALID_DIRECTION"))
		}
		_ => Some(cmd_error(uid, &env.lumy, &env.action, "UNKNOWN_ACTION")),
	}
}

// An OK response echoing the command's lumy/action (§6).
fn cmd_ok(uid: &str, lumy: &str, action: &str) -> Envelope {
	new_envelope("client", uid, lumy, action, "OK", None)
}

// An ERR response echoing the command's lumy/action, with the given error.
fn cmd_error(uid: &str, lumy: &str, action: &str, err: &str) -> Envelope {
	let mut resp = new_envelope("client", uid, lumy, action, "ERR", None);
	resp.err = Some(err.to_string());
	resp
}

// core/setgroups (protocol 4.2): the server pushes the endpoint's full
// group-membership list. Applies it immediately (subscribes to newly-added
// group command topics, unsubscribes from the ones left behind) and persists
// it (GROUPS in the config DB) so the membership survives restarts. Returns
// an error string for the response envelope, or None when applied.
async fn apply_setgroups(
	client: &rumqttc::AsyncClient,
	cmd_topics: &mut Vec<String>,
	env: &Envelope,
	sid: &str,
	debug: bool,
) -> Option<String> {
	// data.groups: array of strings, the full replacement list. Each name
	// must match the charset the server's ACL generation uses
	// (Luminum::MQTT::gen_acl); anything else is rejected as a whole.
	let groups = match env.data.as_ref().and_then(|d| d.get("groups")).and_then(|v| v.as_array()) {
		Some(list) => {
			let mut out = Vec::new();
			for g in list {
				match g.as_str() {
					Some(s) if !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-')) => {
						if !out.iter().any(|x| x == s) { out.push(s.to_string()); }
					}
					_ => return Some(String::from("INVALID_DATA")),
				}
			}
			out
		}
		None => return Some(String::from("INVALID_DATA")),
	};

	let old: Vec<String> = cmd_topics.iter().filter(|t| t.contains("/grp/")).cloned().collect();
	let new: Vec<String> = groups.iter().map(|g| format!("luminum/{}/grp/{}/cmd", sid, g)).collect();

	// Unsubscribe from the groups we no longer belong to; subscribe to the
	// new ones. Subscribes happen before the receipt acknowledgment, so a
	// response the server sees on the resp topic means the membership is
	// already in effect (and in the config DB, below).
	for t in &old {
		if !new.contains(t) {
			if let Err(err) = client.unsubscribe(t).await {
				dbout(debug, 1, &format!("MQTT unsubscribe failed ({}): {}", t, err));
			}
		}
	}
	for t in &new {
		if !old.contains(t) {
			if let Err(err) = client.subscribe(t, rumqttc::QoS::AtLeastOnce).await {
				dbout(debug, 1, &format!("MQTT subscribe failed ({}): {}", t, err));
			}
		}
	}
	cmd_topics.retain(|t| !t.contains("/grp/"));
	cmd_topics.extend(new);

	if groups.is_empty() {
		config_delete("GROUPS");
	} else {
		config_set("GROUPS", &groups.join(","));
	}
	dbout(debug, 3, &format!("setgroups applied: {}",
		if groups.is_empty() { String::from("(no groups)") } else { groups.join(",") }));
	None
}

// ---------------------------------------------------------------------------
// Local IPC (Lumy channel, port 10461)
// ---------------------------------------------------------------------------

fn handle_ipc(stream: TcpStream, debug: bool) -> Result<(), Box<dyn Error>> {
	let mut stream = stream;
	let ccfg = parse_clientconfig(debug);
	let uid = ccfg.get("UID").cloned().unwrap_or_default();
	let (seed, clpub) = client_keypair(debug, &ccfg);

	let env = frame_read(&mut stream)?;
	dbout(debug, 4, &format!("IPC message from {}: action={}", env.lumy, env.action));

	// Lumy traffic is signed with the client's key (§8.2); reject
	// anything that does not verify.
	if env.src != "lumy" || !verify_envelope(&env, &clpub) {
		dbout(debug, 1, &format!("MSG_AUTH_FAIL: IPC message from {} rejected (src={}, signature={})",
			env.lumy, env.src, if verify_envelope(&env, &clpub) { "valid" } else { "invalid" }));
		let mut resp = new_envelope("client", &uid, &env.lumy, &env.action, "ERR", None);
		resp.err = Some(if env.src != "lumy" { String::from("INVALID_SRC") } else { String::from("BAD_SIGNATURE") });
		sign_envelope(&mut resp, &seed);
		frame_write(&mut stream, &resp)?;
		return Ok(());
	}

	match (env.lumy.to_lowercase().as_str(), env.action.as_str()) {
		// Lumy has no local configuration and is requesting its
		// configuration set from the server.
		(_, "newconfig") => {
			dbout(debug, 4, &format!("Received newconfig request from {} Lumy", env.lumy));
			let data = serde_json::json!({
				"hostname": gethostname().to_string_lossy().into_owned(),
				"uid": uid
			});
			let mut req = new_envelope("client", &uid, &env.lumy.to_lowercase(), "newconfig", "new", Some(data));
			sign_envelope(&mut req, &seed);
			let server_host = ccfg.get("SHOST").cloned().unwrap_or_default();
			let server_port = ccfg.get("SPORT").cloned().unwrap_or_default();

			match server_send(&server_host, &server_port, &crt_path(), &req, debug) {
				Ok(response) => {
					// The server's configuration payload must verify
					// before it is handed to the Lumy.
					match server_pubkey(&ccfg) {
						Some(srvpub) if verify_envelope(&response, &srvpub) => {}
						Some(_) => {
							dbout(debug, 1, "MSG_AUTH_FAIL: server configuration response failed signature verification.");
							let mut resp = new_envelope("client", &uid, &env.lumy.to_lowercase(), "setconfig", "ERR", None);
							resp.err = Some(String::from("MSG_AUTH_FAIL"));
							sign_envelope(&mut resp, &seed);
							frame_write(&mut stream, &resp)?;
							return Ok(());
						}
						None => dbout(debug, 2, "No server signing public key on file; configuration response not verified."),
					}
					if response.status == "OK" {
						dbout(debug, 4, &format!("Configuration received from server for {} Lumy", env.lumy));
						let mut resp = new_envelope("client", &uid, &env.lumy.to_lowercase(), "setconfig", "OK", response.data);
						sign_envelope(&mut resp, &seed);
						frame_write(&mut stream, &resp)?;
						dbout(debug, 3, &format!("New configuration sent to {} Lumy", env.lumy));
					} else {
						let mut resp = new_envelope("client", &uid, &env.lumy.to_lowercase(), "setconfig", "ERR", None);
						resp.err = Some(response.err.unwrap_or_else(|| String::from("CONFIG_ERROR")));
						sign_envelope(&mut resp, &seed);
						frame_write(&mut stream, &resp)?;
					}
				}
				Err(err) => {
					dbout(debug, 2, &format!("Failed to send {} configuration request to server: {}", env.lumy, err));
					let mut resp = new_envelope("client", &uid, &env.lumy.to_lowercase(), "setconfig", "ERR", None);
					resp.err = Some(String::from("SERVER_UNREACHABLE"));
					sign_envelope(&mut resp, &seed);
					frame_write(&mut stream, &resp)?;
				}
			}
		}
		// Lumy alert (e.g., Integrity filesystem change). Events are
		// destined for the server events channel; until MQTT is in
		// place, alerts are persisted to the local out-queue for
		// bulk transmission and logged.
		(_, "alert") => {
			dbout(debug, 3, &format!("Alert received from {} Lumy", env.lumy));
			queue_alert(&env, debug);
			let mut resp = new_envelope("client", &uid, &env.lumy.to_lowercase(), "alert", "OK", None);
			sign_envelope(&mut resp, &seed);
			frame_write(&mut stream, &resp)?;
		}
		// Unknown action for a known Lumy (§6.3)
		(_, action) => {
			let mut resp = new_envelope("client", &uid, &env.lumy.to_lowercase(), action, "ERR", None);
			resp.err = Some(String::from("UNKNOWN_ACTION"));
			sign_envelope(&mut resp, &seed);
			frame_write(&mut stream, &resp)?;
		}
	}
	Ok(())
}

fn queue_alert(env: &Envelope, debug: bool) {
	if let Some(parent) = Path::new(&outq_path()).parent() {
		fs::create_dir_all(parent).ok();
	}
	let conn = match Connection::open(outq_path()) {
		Ok(conn) => conn,
		Err(err) => {
			dbout(debug, 1, &format!("Could not open out-queue database: {}", err));
			return;
		}
	};
	conn.execute(
		"create table if not exists OUTQUEUE ( ID integer primary key autoincrement, TS integer not null, LUMY text not null, ACTION text not null, PAYLOAD text not null, SENT integer not null default 0 )",
		[],
	).expect("Error: Could not create OUTQUEUE table");
	let payload = serde_json::to_string(&env.data).unwrap_or_default();
	conn.execute(
		"insert into OUTQUEUE (TS, LUMY, ACTION, PAYLOAD) values (?1, ?2, ?3, ?4)",
		params![env.ts, env.lumy.to_lowercase(), env.action, payload],
	).expect("Error: Could not queue alert");
	conn.close().unwrap();
}

// Re-publish events that were queued while the control channel was down
// (protocol §9.1). The out-queue persists client->server events to disk when
// the MQTT session is unavailable; on (re)connect they are flushed to the
// per-UID events topic (signed, QoS 1) in ID order and marked SENT. Bounded
// per drain (up to 100) so a large backlog cannot stall the connect path; a
// publish failure stops the flush and leaves the remaining rows un-sent so a
// later drain retries them, preserving order.
async fn drain_outqueue(
	client: &rumqttc::AsyncClient,
	events_topic: &str,
	uid: &str,
	seed: &[u8; 32],
	debug: bool,
) {
	let conn = match Connection::open(outq_path()) {
		Ok(c) => c,
		Err(_) => return,   // no out-queue yet; nothing to flush
	};
	let rows: Vec<(i64, String, String, String)> = match conn
		.prepare("select ID, LUMY, ACTION, PAYLOAD from OUTQUEUE where SENT = 0 order by ID limit 100")
	{
		Ok(mut sth) => match sth.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))) {
			Ok(it) => it.filter_map(|r| r.ok()).collect(),
			Err(_) => return,   // OUTQUEUE table not created yet
		},
		Err(_) => return,
	};
	if rows.is_empty() {
		conn.close().ok();
		return;
	}
	let mut flushed = 0;
	for (id, lumy, action, payload) in rows {
		let data: serde_json::Value = serde_json::from_str(&payload).unwrap_or(serde_json::Value::Null);
		let mut env = new_envelope("client", uid, &lumy, &action, "OK", Some(data));
		sign_envelope(&mut env, seed);
		let bytes = match serde_json::to_vec(&env) {
			Ok(b) => b,
			Err(_) => continue,
		};
		match client.publish(events_topic, rumqttc::QoS::AtLeastOnce, false, bytes).await {
			Ok(_) => {
				let _ = conn.execute("update OUTQUEUE set SENT = 1 where ID = ?", params![id]);
				flushed += 1;
			}
			Err(err) => {
				dbout(debug, 1, &format!("out-queue flush stopped (publish failed): {}", err));
				break;
			}
		}
	}
	if flushed > 0 {
		dbout(debug, 3, &format!("Flushed {} queued event(s) to the events topic", flushed));
	}
	conn.close().ok();
}

// ---------------------------------------------------------------------------
// P2P data channel (10704) - the seed path (docs/p2p.md 3, 6, 8)
// ---------------------------------------------------------------------------
//
// The server (source) connects to this endpoint's 10704 listener, presents
// the signed transfer grant as the first frame, and streams the grant's
// files in order. The session is self-contained: the grant is
// self-authenticating (server-signed, verified under the stored SRVPUB), so
// it does not depend on the deploy command having been processed. Files are
// staged under Downloads/{token}/, verified (size + SHA-256), moved to
// Packages/{pkgid}/{path}, and recorded in the local manifest
// (config/p2p.db). The terminal outcome is reported to the server as a
// core/report envelope (p2p_fetch_ok / p2p_fetch_fail); throttled
// p2p_progress reports ride the same path (docs/p2p.md 6.2).

const P2P_IO_TIMEOUT: Duration = Duration::from_secs(60);
const P2P_CHUNK_MAX: usize = 16 * 1024 * 1024;
const P2P_PROGRESS_EVERY_SECS: u64 = 5;
const P2P_PROGRESS_EVERY_PCT: u64 = 10;

fn p2p_db_path() -> String { format!("{}/config/p2p.db", base_path()) }

// --- Local file manifest (docs/p2p.md 8.1) ----------------------------------

// Open the manifest database (config/p2p.db, 0600), creating the table when
// absent. The manifest is the endpoint's record of what it holds.
fn manifest_conn() -> Option<Connection> {
	let path = p2p_db_path();
	if let Some(parent) = Path::new(&path).parent() {
		fs::create_dir_all(parent).ok();
	}
	let conn = Connection::open(&path).ok()?;
	conn.execute_batch(
		"create table if not exists MANIFEST ( FILEID integer primary key, PKGID integer not null, OS text not null, PATH text not null, SIZE integer not null, SHA256 text not null, TS integer not null )",
	).ok()?;
	// The manifest names servable content; keep it owner-only like the
	// configuration database.
	if let Ok(md) = fs::metadata(&path) {
		if md.permissions().mode() & 0o777 != 0o600 {
			fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).ok();
		}
	}
	Some(conn)
}

fn manifest_upsert(fileid: i64, pkgid: i64, os: &str, path: &str, size: i64, sha: &str) {
	if let Some(conn) = manifest_conn() {
		let _ = conn.execute(
			"insert into MANIFEST (FILEID,PKGID,OS,PATH,SIZE,SHA256,TS) values (?1,?2,?3,?4,?5,?6,?7)
			 on conflict(FILEID) do update set PKGID=excluded.PKGID, OS=excluded.OS, PATH=excluded.PATH, SIZE=excluded.SIZE, SHA256=excluded.SHA256, TS=excluded.TS",
			params![fileid, pkgid, os, path, size, sha, Local::now().timestamp()],
		);
		conn.close().ok();
	}
}

// --- Used-token ring (docs/p2p.md 5.3 item 5) --------------------------------

// In-memory bounded ring of consumed grant tokens: a token completed (or
// failed) on this endpoint is never accepted again here.
type TokenRing = Arc<Mutex<VecDeque<String>>>;

fn token_ring_new() -> TokenRing {
	Arc::new(Mutex::new(VecDeque::with_capacity(1000)))
}

fn token_seen(ring: &TokenRing, token: &str) -> bool {
	ring.lock().unwrap().contains(&token.to_string())
}

fn token_consume(ring: &TokenRing, token: &str) {
	let mut q = ring.lock().unwrap();
	q.push_back(token.to_string());
	while q.len() > 1000 {
		q.pop_front();
	}
}

// --- rustls acceptor (docs/p2p.md 4.4) ----------------------------------------

// Client-certificate verifier for the 10704 acceptor: the connecting peer
// is the server, and its certificate is verified chain-to-root + validity
// against the stored anchor (config/server.crt) - the same trust anchor as
// the bootstrap channel (docs/p2p.md 4.4). In generate mode the anchor is
// the Luminum CA and the server presents the leaf it issued; in import mode
// the anchor is the self-signed server certificate, which is its own end
// entity. Hostname verification is replaced by this anchor check: peers are
// addressed by IP, and the identity binding is "the peer is the server this
// endpoint already trusts".
#[derive(Debug)]
struct ServerChainVerifier {
	roots: rustls::RootCertStore,
	algs: rustls::crypto::WebPkiSupportedAlgorithms,
}

impl rustls::server::danger::ClientCertVerifier for ServerChainVerifier {
	fn root_hint_subjects(&self) -> &[rustls::DistinguishedName] {
		&[]
	}
	fn verify_client_cert(
		&self,
		end_entity: &rustls::pki_types::CertificateDer<'_>,
		intermediates: &[rustls::pki_types::CertificateDer<'_>],
		now: rustls::pki_types::UnixTime,
	) -> Result<rustls::server::danger::ClientCertVerified, rustls::Error> {
		let parsed = rustls::server::ParsedCertificate::try_from(end_entity)?;
		rustls::client::verify_server_cert_signed_by_trust_anchor(
			&parsed, &self.roots, intermediates, now, &self.algs.all,
		)?;
		Ok(rustls::server::danger::ClientCertVerified::assertion())
	}
	fn verify_tls12_signature(
		&self,
		message: &[u8],
		cert: &rustls::pki_types::CertificateDer<'_>,
		dss: &rustls::DigitallySignedStruct,
	) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
		rustls::crypto::verify_tls12_signature(message, cert, dss, &self.algs)
	}
	fn verify_tls13_signature(
		&self,
		message: &[u8],
		cert: &rustls::pki_types::CertificateDer<'_>,
		dss: &rustls::DigitallySignedStruct,
	) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
		rustls::crypto::verify_tls13_signature(message, cert, dss, &self.algs)
	}
	fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
		self.algs.supported_schemes()
	}
}

// Build the 10704 acceptor configuration: the server-issued client
// certificate (config/client.crt + client.key) plus the anchor verifier.
// None when the endpoint is not yet certificated (the listener stays bound;
// sessions are refused until the certificate exists).
fn p2p_acceptor_config(debug: bool) -> Option<Arc<rustls::ServerConfig>> {
	// The default crypto provider (aws-lc-rs, matching rumqttc's
	// tokio-rustls) must be installed before any rustls object is built.
	let _ = rustls::crypto::CryptoProvider::install_default(rustls::crypto::aws_lc_rs::default_provider());

	let crt_pem = match fs::read(client_crt_path()) {
		Ok(p) => p,
		Err(_) => {
			dbout(debug, 3, "No client TLS certificate on file (config/client.crt); the data channel will refuse sessions until the endpoint is certificated.");
			return None;
		}
	};
	let key_pem = match fs::read(client_key_path()) {
		Ok(p) => p,
		Err(err) => { dbout(debug, 1, &format!("Client TLS key unreadable (config/client.key): {}", err)); return None; }
	};
	let mut rd = std::io::Cursor::new(crt_pem);
	let certs: Vec<rustls::pki_types::CertificateDer<'static>> = rustls_pemfile::certs(&mut rd).filter_map(|c| c.ok()).collect();
	if certs.is_empty() {
		dbout(debug, 1, "Client TLS certificate is not a valid PEM certificate (config/client.crt); the data channel is unavailable.");
		return None;
	}
	let mut rd = std::io::Cursor::new(key_pem);
	let key = match rustls_pemfile::pkcs8_private_keys(&mut rd).next() {
		Some(Ok(k)) => k,
		_ => { dbout(debug, 1, "Client TLS key is not a valid PKCS#8 PEM (config/client.key); the data channel is unavailable."); return None; }
	};
	let anchor_pem = match fs::read(crt_path()) {
		Ok(p) => p,
		Err(_) => { dbout(debug, 1, "Server certificate not found (config/server.crt); the data channel is unavailable."); return None; }
	};
	let mut rd = std::io::Cursor::new(anchor_pem);
	let anchor = match rustls_pemfile::certs(&mut rd).next() {
		Some(Ok(a)) => a,
		_ => { dbout(debug, 1, "Server certificate is not a valid PEM certificate (config/server.crt); the data channel is unavailable."); return None; }
	};
	let mut roots = rustls::RootCertStore::empty();
	if roots.add(anchor).is_err() {
		dbout(debug, 1, "Server certificate is not a usable trust anchor (config/server.crt); the data channel is unavailable.");
		return None;
	}
	// The signature-verification algorithms come from the installed crypto
	// provider (aws-lc-rs, the same one rumqttc's tokio-rustls uses).
	let provider = match rustls::crypto::CryptoProvider::get_default() {
		Some(p) => p,
		None => { dbout(debug, 1, "No default rustls crypto provider; the data channel is unavailable."); return None; }
	};
	let algs = provider.signature_verification_algorithms;
	let config = rustls::ServerConfig::builder()
		.with_client_cert_verifier(Arc::new(ServerChainVerifier { roots, algs }))
		.with_single_cert(certs, key.into())
		.ok()?;
	Some(Arc::new(config))
}

// --- Grant validation (docs/p2p.md 5.3, client side) ---------------------------

#[derive(Debug)]
struct GrantFile {
	fileid: u64,
	path: String,
	size: u64,
	sha256: String,
}

#[derive(Debug)]
struct ValidGrant {
	token: String,
	pkgid: u64,
	aid: String,
	files: Vec<GrantFile>,
}

// The grant's install paths are server-assigned and sanitized at upload;
// this is the client-side re-validation (docs/p2p.md 11): relative, no
// ".." components, no absolute paths.
fn is_safe_rel_path(p: &str) -> bool {
	if p.is_empty() || p.starts_with('/') {
		return false;
	}
	!p.split('/').any(|c| c == "..")
}

// Validate a received transfer grant. Returns the parsed grant or a
// machine-readable error code (docs/p2p.md 5.3).
fn validate_grant(env: &Envelope, uid: &str, srvpub: &[u8; 32], ring: &TokenRing, now: i64) -> Result<ValidGrant, String> {
	if env.src != "server" || env.lumy != "core" || env.action != "p2pgrant" || env.status != "OK" {
		return Err(String::from("BAD_GRANT"));
	}
	if !verify_envelope(env, srvpub) {
		return Err(String::from("BAD_GRANT"));
	}
	if env.uid != uid {
		return Err(String::from("UID_MISMATCH"));
	}
	let data = match &env.data {
		Some(d) => d,
		None => return Err(String::from("BAD_GRANT")),
	};
	let token = data.get("token").and_then(|v| v.as_str()).unwrap_or("").to_string();
	if !is_uuid4(&token) {
		return Err(String::from("BAD_GRANT"));
	}
	if token_seen(ring, &token) {
		return Err(String::from("GRANT_USED"));
	}
	let exp = data.get("exp").and_then(|v| v.as_u64()).unwrap_or(0) as i64;
	if exp <= now {
		return Err(String::from("GRANT_EXPIRED"));
	}
	let pkgid = match data.get("pkgid").and_then(|v| v.as_u64()) {
		Some(p) if p > 0 => p,
		_ => return Err(String::from("BAD_GRANT")),
	};
	let aid = data.get("aid").and_then(|v| v.as_str()).unwrap_or("").to_string();
	let files_arr = match data.get("files").and_then(|v| v.as_array()) {
		Some(a) if !a.is_empty() => a,
		_ => return Err(String::from("BAD_GRANT")),
	};
	let mut files = Vec::new();
	for f in files_arr {
		let fileid = match f.get("fileid").and_then(|v| v.as_u64()) {
			Some(id) => id,
			None => return Err(String::from("BAD_GRANT")),
		};
		let path = f.get("path").and_then(|v| v.as_str()).unwrap_or("").to_string();
		if !is_safe_rel_path(&path) {
			return Err(String::from("BAD_GRANT"));
		}
		let size = match f.get("size").and_then(|v| v.as_u64()) {
			Some(s) => s,
			None => return Err(String::from("BAD_GRANT")),
		};
		let sha = f.get("sha256").and_then(|v| v.as_str()).unwrap_or("").to_string();
		if sha.len() != 64 || !sha.chars().all(|c| c.is_ascii_hexdigit()) {
			return Err(String::from("BAD_GRANT"));
		}
		files.push(GrantFile { fileid, path, size, sha256: sha.to_ascii_lowercase() });
	}
	Ok(ValidGrant { token, pkgid, aid, files })
}

// --- Reports (docs/p2p.md 6.2, 10) ---------------------------------------------

// Publish a core/report envelope on the per-UID resp topic. Terminal
// reports (qos1) fall back to the out-queue when the control channel is
// down (protocol §9.1); progress reports are loss-tolerant and dropped.
fn publish_report(
	mqtt: &Option<rumqttc::AsyncClient>,
	handle: &tokio::runtime::Handle,
	connected: &Arc<AtomicBool>,
	resp_topic: &str,
	uid: &str,
	seed: &[u8; 32],
	data: serde_json::Value,
	qos1: bool,
	debug: bool,
) {
	let mut env = new_envelope("client", uid, "core", "report", "OK", Some(data));
	sign_envelope(&mut env, seed);
	let bytes = match serde_json::to_vec(&env) {
		Ok(b) => b,
		Err(err) => { dbout(debug, 1, &format!("Unable to serialize report: {}", err)); return; }
	};
	if let Some(client) = mqtt {
		if connected.load(Ordering::SeqCst) {
			let qos = if qos1 { rumqttc::QoS::AtLeastOnce } else { rumqttc::QoS::AtMostOnce };
			let client = client.clone();
			let topic = resp_topic.to_string();
			if handle.block_on(client.publish(topic, qos, false, bytes)).is_ok() {
				return;
			}
		}
	}
	if qos1 {
		queue_alert(&env, debug);
	}
}

// --- The session ----------------------------------------------------------------

// Read one raw data frame: 4-byte big-endian length + bytes. A zero-length
// frame terminates the file's stream (docs/p2p.md 6). Returns Ok(None) at
// EOF, Ok(Some(bytes)) for a chunk, Err on failure.
fn raw_frame_read<R: Read>(r: &mut R) -> io::Result<Option<Vec<u8>>> {
	let mut lenbuf = [0u8; 4];
	r.read_exact(&mut lenbuf)?;
	let len = u32::from_be_bytes(lenbuf) as usize;
	if len == 0 {
		return Ok(None);
	}
	if len > P2P_CHUNK_MAX {
		return Err(io::Error::new(io::ErrorKind::InvalidData, "raw frame exceeds the maximum size"));
	}
	let mut buf = vec![0u8; len];
	r.read_exact(&mut buf)?;
	Ok(Some(buf))
}

// Receive one file: read the source's signed p2pfetch response, stream the
// raw frames into the staging path, verify size + SHA-256, and move the
// file to its final path under Packages/. Returns Ok(()) on success,
// Err(code) otherwise; the staging tree is deleted on failure.
fn receive_file(
	tls: &mut rustls::StreamOwned<rustls::ServerConnection, TcpStream>,
	base: &str,
	token: &str,
	pkgid: u64,
	file: &GrantFile,
	seed: &[u8; 32],
	srvpub: &[u8; 32],
	uid: &str,
	mqtt: &Option<rumqttc::AsyncClient>,
	handle: &tokio::runtime::Handle,
	connected: &Arc<AtomicBool>,
	resp_topic: &str,
	aid: &str,
	debug: bool,
) -> Result<(), String> {
	// Per-file handshake: the source's signed p2pfetch response.
	let resp = match frame_read(tls) {
		Ok(e) => e,
		Err(err) => return Err(format!("STREAM_ERROR: {}", err)),
	};
	if resp.lumy != "core" || resp.action != "p2pfetch" || resp.status != "OK"
		|| !verify_envelope(&resp, srvpub)
		|| resp.data.as_ref().and_then(|d| d.get("token")).and_then(|v| v.as_str()) != Some(token)
		|| resp.data.as_ref().and_then(|d| d.get("fileid")).and_then(|v| v.as_u64()) != Some(file.fileid)
	{
		return Err(String::from("BAD_GRANT"));
	}

	// Stage under Downloads/{token}/{path}.
	let stage_dir = format!("{}/Downloads/{}", base, token);
	let stage_path = format!("{}/{}", stage_dir, file.path);
	if let Some(parent) = Path::new(&stage_path).parent() {
		fs::create_dir_all(parent).map_err(|e| format!("STAGING_ERROR: {}", e))?;
	}
	let mut out = fs::File::create(&stage_path).map_err(|e| format!("STAGING_ERROR: {}", e))?;
	let mut hasher = Sha256::new();
	let mut received: u64 = 0;
	let mut last_report = Instant::now();
	let mut last_report_pct: u64 = 0;
	loop {
		match raw_frame_read(tls) {
			Ok(Some(chunk)) => {
				out.write_all(&chunk).map_err(|e| format!("STAGING_ERROR: {}", e))?;
				hasher.update(&chunk);
				received += chunk.len() as u64;
				let pct = if file.size > 0 { received * 100 / file.size } else { 100 };
				let due = last_report.elapsed() >= Duration::from_secs(P2P_PROGRESS_EVERY_SECS)
					|| pct.saturating_sub(last_report_pct) >= P2P_PROGRESS_EVERY_PCT;
				if due {
					last_report = Instant::now();
					last_report_pct = pct;
					publish_report(
						mqtt, handle, connected, resp_topic, uid, seed,
						serde_json::json!({
							"event": "p2p_progress",
							"aid": aid,
							"fileid": file.fileid,
							"state": "FETCHING",
							"received": received,
							"total": file.size,
							"srcuid": 0,
						}),
						false, debug,
					);
				}
			}
			Ok(None) => break,   // zero-length frame: EOF
			Err(err) => return Err(format!("STREAM_ERROR: {}", err)),
		}
	}
	out.flush().ok();
	drop(out);

	// Verify total size and SHA-256 (docs/p2p.md 6). A mismatch aborts the
	// session: the staged file is deleted, nothing is installed.
	let digest = hex_of(&hasher.finalize());
	if received != file.size || digest != file.sha256 {
		let _ = fs::remove_file(&stage_path);
		return Err(String::from("HASH_MISMATCH"));
	}

	// Install under Packages/{pkgid}/{path} and record the manifest row.
	let final_dir = format!("{}/Packages/{}", base, pkgid);
	let final_path = format!("{}/{}", final_dir, file.path);
	if let Some(parent) = Path::new(&final_path).parent() {
		fs::create_dir_all(parent).map_err(|e| format!("INSTALL_ERROR: {}", e))?;
	}
	fs::rename(&stage_path, &final_path).map_err(|e| format!("INSTALL_ERROR: {}", e))?;
	manifest_upsert(file.fileid as i64, pkgid as i64, OSPLAT, &file.path, file.size as i64, &file.sha256);
	Ok(())
}

// Lowercase hex of a digest.
fn hex_of(bytes: &[u8]) -> String {
	let mut s = String::with_capacity(bytes.len() * 2);
	for b in bytes {
		s.push_str(&format!("{:02x}", b));
	}
	s
}

// The 10704 inbound data session (docs/p2p.md 3, 6; protocol 8.3, 8.4).
// Runs on its own thread per connection.
fn handle_data_session(
	stream: TcpStream,
	config: Arc<rustls::ServerConfig>,
	uid: String,
	seed: [u8; 32],
	srvpub: [u8; 32],
	mqtt: Option<rumqttc::AsyncClient>,
	handle: tokio::runtime::Handle,
	connected: Arc<AtomicBool>,
	ring: TokenRing,
	resp_topic: String,
	debug: bool,
) {
	let base = base_path();
	stream.set_read_timeout(Some(P2P_IO_TIMEOUT)).ok();
	stream.set_write_timeout(Some(P2P_IO_TIMEOUT)).ok();
	// The TLS handshake (1.2 or 1.3) completes transparently on the first
	// read/write through the StreamOwned (rustls 0.23 has no blocking
	// acceptor helper).
	let conn = match rustls::ServerConnection::new(config) {
		Ok(c) => c,
		Err(err) => {
			dbout(debug, 2, &format!("Data channel: unable to start the TLS session: {}", err));
			return;
		}
	};
	let mut tls = rustls::StreamOwned::new(conn, stream);

	// The grant: server-signed, presented verbatim as the first frame.
	let grant = match frame_read(&mut tls) {
		Ok(e) => e,
		Err(err) => {
			dbout(debug, 2, &format!("Data channel: unable to read the grant frame: {}", err));
			return;
		}
	};
	let valid = match validate_grant(&grant, &uid, &srvpub, &ring, Local::now().timestamp()) {
		Ok(g) => g,
		Err(code) => {
			dbout(debug, 1, &format!("Data channel: grant rejected ({}); closing the session", code));
			let token = grant.data.as_ref().and_then(|d| d.get("token")).and_then(|v| v.as_str()).unwrap_or("");
			let mut resp = new_envelope("client", &uid, "core", "p2pfetch", "ERR", Some(serde_json::json!({ "token": token })));
			resp.err = Some(code.clone());
			sign_envelope(&mut resp, &seed);
			frame_write(&mut tls, &resp).ok();
			return;
		}
	};
	dbout(debug, 3, &format!("Data channel: grant {} accepted ({} file(s), package {})", valid.token, valid.files.len(), valid.pkgid));

	// Handshake response: the file sizes, signed by this endpoint.
	let sizes: Vec<u64> = valid.files.iter().map(|f| f.size).collect();
	let mut resp = new_envelope("client", &uid, "core", "p2pfetch", "OK", Some(serde_json::json!({ "token": valid.token, "files": sizes })));
	sign_envelope(&mut resp, &seed);
	if frame_write(&mut tls, &resp).is_err() {
		dbout(debug, 2, "Data channel: unable to write the handshake response");
		return;
	}

	// Receive the files in grant order.
	for file in &valid.files {
		// Per-file request: signed by this endpoint (the requester).
		let mut req = new_envelope("client", &uid, "core", "p2pfetch", "OK", Some(serde_json::json!({ "token": valid.token, "fileid": file.fileid })));
		sign_envelope(&mut req, &seed);
		if frame_write(&mut tls, &req).is_err() {
			fail_session(&mut tls, &uid, &seed, &valid.token, valid.pkgid, "STREAM_ERROR", &mqtt, &handle, &connected, &resp_topic, &ring, debug);
			return;
		}
		if let Err(code) = receive_file(
			&mut tls, &base, &valid.token, valid.pkgid, file, &seed, &srvpub, &uid,
			&mqtt, &handle, &connected, &resp_topic, &valid.aid, debug,
		) {
			fail_session(&mut tls, &uid, &seed, &valid.token, valid.pkgid, &code, &mqtt, &handle, &connected, &resp_topic, &ring, debug);
			return;
		}
	}

	// Session complete: report the outcome and consume the token.
	let fileids: Vec<u64> = valid.files.iter().map(|f| f.fileid).collect();
	publish_report(
		&mqtt, &handle, &connected, &resp_topic, &uid, &seed,
		serde_json::json!({
			"event": "p2p_fetch_ok",
			"token": valid.token,
			"pkgid": valid.pkgid,
			"srcuid": 0,
			"files": fileids,
		}),
		true, debug,
	);
	token_consume(&ring, &valid.token);
	// The staging tree is per token; the files are installed now, remove it.
	let stage_dir = format!("{}/Downloads/{}", base, &valid.token);
	fs::remove_dir_all(&stage_dir).ok();
	dbout(debug, 0, &format!("Data channel: package {} received ({} file(s), grant {})", valid.pkgid, valid.files.len(), valid.token));
}

// Fail the session: answer the source's ERR, clean the per-token staging
// tree, report p2p_fetch_fail (terminal, out-queue backed), and consume the
// token (a failed walk consumes the grant, docs/p2p.md 7.2; a re-pushed
// grant with the same token is refused on this endpoint).
fn fail_session(
	tls: &mut rustls::StreamOwned<rustls::ServerConnection, TcpStream>,
	uid: &str,
	seed: &[u8; 32],
	token: &str,
	pkgid: u64,
	err: &str,
	mqtt: &Option<rumqttc::AsyncClient>,
	handle: &tokio::runtime::Handle,
	connected: &Arc<AtomicBool>,
	resp_topic: &str,
	ring: &TokenRing,
	debug: bool,
) {
	dbout(debug, 1, &format!("Data channel: session failed ({}); reporting p2p_fetch_fail", err));
	let mut resp = new_envelope("client", uid, "core", "p2pfetch", "ERR", Some(serde_json::json!({ "token": token })));
	resp.err = Some(err.to_string());
	sign_envelope(&mut resp, seed);
	frame_write(tls, &resp).ok();
	// The staging tree is per token; remove it whole.
	let stage_dir = format!("{}/Downloads/{}", base_path(), token);
	fs::remove_dir_all(&stage_dir).ok();
	publish_report(
		mqtt, handle, connected, resp_topic, uid, seed,
		serde_json::json!({
			"event": "p2p_fetch_fail",
			"token": token,
			"pkgid": pkgid,
			"srcuid": 0,
			"err": err,
		}),
		true, debug,
	);
	token_consume(ring, token);
}

// ---------------------------------------------------------------------------
// Lumy discovery and launch
// ---------------------------------------------------------------------------

fn discover_lumys(debug: bool) -> HashMap<String, String> {
	let mut lumys: HashMap<String, String> = HashMap::new();
	let modpath = mod_path();
	if !Path::new(&modpath).is_dir() {
		dbout(debug, 4, &format!("No modules directory at {}", modpath));
		return lumys;
	}
	if let Ok(entries) = fs::read_dir(&modpath) {
		for entry in entries.flatten() {
			let dir = entry.path();
			if !dir.is_dir() { continue; }
			let name = entry.file_name().to_string_lossy().to_string();
			// Find the Lumy_<Name> binary in the module directory, matching
			// case-insensitively since module dir names are lowercase but
			// binary names may be capitalized (e.g. integrity/Lumy_Integrity).
			if let Ok(bin_entries) = fs::read_dir(&dir) {
				for bin in bin_entries.flatten() {
					let bin_name = bin.file_name().to_string_lossy().to_string();
					if bin.path().is_file()
					&& bin_name.to_lowercase() == format!("lumy_{}", name).to_lowercase() {
						dbout(debug, 4, &format!("Found Lumy: {}", name));
						lumys.insert(name, bin.path().to_string_lossy().into_owned());
						break;
					}
				}
			}
		}
	}
	lumys
}

fn start_lumy(lumy: &str, cmd: &str, debug: bool) {
	dbout(debug, 0, &format!("Starting \"{}\" Lumy", lumy));
	match Command::new(cmd).stdout(Stdio::null()).stderr(Stdio::null()).spawn() {
		Ok(_child) => dbout(debug, 3, &format!("Successfully started \"{}\" Lumy", lumy)),
		Err(err) => dbout(debug, 1, &format!("Unable to start \"{}\" Lumy: {}", lumy, err)),
	}
}

// ---------------------------------------------------------------------------
// Setup (text wizard)
// ---------------------------------------------------------------------------

fn clientsetup() {
	println!("Luminum Client (Linux)\nby Christopher R. Curzio <ccurzio@luminum.net>\n");
	println!("Client Configuration\n--------------------");

	let mut ui_server = String::new();
	print!("Enter Luminum server hostname or IP address: ");
	io::stdout().flush().unwrap();
	io::stdin().read_line(&mut ui_server).expect("Error reading user input");
	let server = ui_server.trim().to_string();

	let mut port: u16 = DPORT;
	loop {
		let mut ui_port = String::new();
		print!("Enter server port [{}]: ", DPORT);
		io::stdout().flush().unwrap();
		io::stdin().read_line(&mut ui_port).unwrap();
		let ui_port = ui_port.trim();
		match ui_port.parse::<u16>() {
			Ok(num) if num >= 1 => { port = num; break; }
			_ => {
				if ui_port.is_empty() { break; }
				println!("Invalid port: {}\n", ui_port);
			}
		}
	}

	let mut ui_server_key = String::new();
	print!("Enter Luminum server key: ");
	io::stdout().flush().unwrap();
	io::stdin().read_line(&mut ui_server_key).expect("Error reading user input");
	let server_key = ui_server_key.trim().to_string();

	// Server certificate: the TLS trust anchor for the bootstrap channel.
	// Validated before anything is written so a bad path leaves no
	// partial configuration behind.
	let mut ui_cert = String::new();
	print!("Enter path to Luminum server certificate: ");
	io::stdout().flush().unwrap();
	io::stdin().read_line(&mut ui_cert).expect("Error reading user input");
	let cert_src = ui_cert.trim().to_string();
	let cert_pem = match fs::read(&cert_src) {
		Ok(pem) if String::from_utf8_lossy(&pem).contains("BEGIN CERTIFICATE") => pem,
		_ => {
			println!("Invalid server certificate: {}", cert_src);
			process::exit(1);
		}
	};

	// Server signing certificate: the bootstrap trust anchor for
	// verifying server→client signatures (protocol §7.1). Optional
	// here, but registration will not succeed without it.
	let mut ui_signing = String::new();
	print!("Enter path to Luminum server signing certificate [blank to skip]: ");
	io::stdout().flush().unwrap();
	io::stdin().read_line(&mut ui_signing).expect("Error reading user input");
	let signing_src = ui_signing.trim().to_string();
	let signing_pem = if signing_src.is_empty() {
		None
	} else {
		match fs::read(&signing_src) {
			Ok(pem) if String::from_utf8_lossy(&pem).contains("BEGIN CERTIFICATE") => Some(pem),
			_ => {
				println!("Invalid server signing certificate: {}", signing_src);
				process::exit(1);
			}
		}
	};

	let fpnt = write_client_config(&server, port, &server_key, &cert_pem, signing_pem.as_deref());

	println!("\nLuminum Server: {}", server);
	println!("Server port: {}", port);
	println!("Server certificate: {}", cert_src);
	if signing_pem.is_some() {
		println!("Server signing certificate: {}", signing_src);
	} else {
		println!("Server signing certificate: (none provided - registration requires it)");
	}
	println!("Client fingerprint: {}\n", fpnt);
	println!("Luminum Client configuration complete.");
	process::exit(0);
}

// Shared configuration writer (wizard + provisioning import): persists the
// server trust anchors (TLS cert, and the signing cert when provided), seeds
// the config DB with the server connection parameters, generates the client
// signing keypair + fingerprint (protocol §3.1), and secures the DB to 0600.
// Returns the client fingerprint. Both setup paths call this so the on-disk
// layout they produce cannot drift apart.
fn write_client_config(
	server: &str,
	port: u16,
	server_key: &str,
	cert_pem: &[u8],
	signing_pem: Option<&[u8]>,
) -> String {
	if let Some(parent) = Path::new(&cfg_path()).parent() {
		fs::create_dir_all(parent).expect("Error: Could not create configuration directory");
	}
	fs::write(crt_path(), cert_pem).expect("Error: Could not save server certificate");
	if let Some(pem) = signing_pem {
		fs::write(signing_crt_path(), pem).expect("Error: Could not save server signing certificate");
	}
	let confconn = Connection::open(cfg_path()).expect("Error: Could not initialize configuration database");
	// KEY is unique: config_set relies on INSERT OR REPLACE semantics.
	confconn.execute("create table if not exists CONFIG ( KEY text not null unique, VALUE text not null )", [])
		.expect("Error: Could not create CONFIG table in configuration database");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["SHOST", server])
		.expect("Error: Could not insert SHOST into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["SPORT", &port.to_string()])
		.expect("Error: Could not insert SPORT into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["SVRKEY", server_key])
		.expect("Error: Could not insert SVRKEY into CONFIG table.");

	// Client signing keypair + fingerprint (protocol §3.1).
	let mut seed = [0u8; 32];
	getrandom::getrandom(&mut seed).expect("Error: unable to obtain randomness for key generation");
	let key = SigningKey::from_bytes(&seed);
	let pubb = *key.verifying_key().as_bytes();
	let fpnt = fingerprint(&pubb);
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["CLPPRV", base64ct::Base64::encode_string(&seed)])
		.expect("Error: Could not insert CLPPRV into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["CLPPUB", base64ct::Base64::encode_string(&pubb)])
		.expect("Error: Could not insert CLPPUB into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["FPNT", &fpnt])
		.expect("Error: Could not insert FPNT into CONFIG table.");
	confconn.close().unwrap();
	// The config DB holds the client's private signing key (CLPPRV).
	fs::set_permissions(&cfg_path(), fs::Permissions::from_mode(0o600))
		.expect("Error: Could not secure configuration database");
	fpnt
}

// ---------------------------------------------------------------------------
// Provisioning import (out-of-band setup)
// ---------------------------------------------------------------------------

// The infra-specific provisioning file (config.ini): a single self-contained
// JSON document carrying everything the client needs to register and talk to
// the server. The server-side generator (mkprovision.pl) emits it from an
// installed server's SYSTEM.CONFIG and certificates.
#[derive(Deserialize)]
struct ProvisionServer {
	host: String,
	port: u16,
	key: String,
}

#[derive(Deserialize)]
struct ProvisionCerts {
	server: String,
	signing: String,
}

#[derive(Deserialize)]
struct ProvisionFile {
	v: String,
	server: ProvisionServer,
	certificates: ProvisionCerts,
}

// Validate a provisioning certificate before import: it must parse as an
// X.509 certificate and must not be expired. An expired certificate leaves a
// client that cannot connect (server cert) or register (signing cert), so the
// import is refused rather than leaving a broken configuration behind. Returns
// an error message when either check fails.
fn check_cert_validity(label: &str, pem: &str) -> Result<(), String> {
	use openssl::asn1::Asn1Time;
	use openssl::x509::X509;
	let cert = match X509::from_pem(pem.as_bytes()) {
		Ok(c) => c,
		Err(_) => return Err(format!("Provisioning file {} certificate is not a valid X.509 certificate.", label)),
	};
	let now = match Asn1Time::days_from_now(0) {
		Ok(n) => n,
		Err(_) => return Err(String::from("Unable to determine the current time.")),
	};
	if cert.not_after() < now {
		return Err(format!("Provisioning file {} certificate is expired.", label));
	}
	Ok(())
}

// Import a provisioning file in place of the interactive wizard. The file is
// validated fully before anything is written, so a bad file leaves no partial
// configuration behind. Exits the process on success (mirrors clientsetup).
fn clientimport(path: &str, debug: bool) {
	let raw = match fs::read_to_string(path) {
		Ok(r) => r,
		Err(err) => {
			dbout(debug, 1, &format!("Could not read provisioning file {}: {}", path, err));
			process::exit(1);
		}
	};
	let prov: ProvisionFile = match serde_json::from_str(&raw) {
		Ok(p) => p,
		Err(err) => {
			dbout(debug, 1, &format!("Provisioning file {} is not valid JSON: {}", path, err));
			process::exit(1);
		}
	};

	// Version gate (protocol §10): accept the same MAJOR (1.x).
	if !prov.v.starts_with("1.") {
		dbout(debug, 1, &format!("Unsupported provisioning file version: {}", prov.v));
		process::exit(1);
	}
	if prov.server.host.trim().is_empty() {
		dbout(debug, 1, "Provisioning file is missing the server host.");
		process::exit(1);
	}
	if prov.server.port == 0 {
		dbout(debug, 1, "Provisioning file has an invalid server port.");
		process::exit(1);
	}
	// SKEY charset (server validates ^[A-Za-z0-9]+$ at registration).
	if prov.server.key.is_empty() || !prov.server.key.chars().all(|c| c.is_ascii_alphanumeric()) {
		dbout(debug, 1, "Provisioning file has an invalid server key.");
		process::exit(1);
	}
	// Both certificates are required: the file must carry everything needed to
	// register (the signing cert is the bootstrap trust anchor, protocol §7.1).
	let cert_ok = prov.certificates.server.contains("BEGIN CERTIFICATE");
	let sign_ok = prov.certificates.signing.contains("BEGIN CERTIFICATE");
	if !cert_ok || !sign_ok {
		dbout(debug, 1, "Provisioning file is missing a valid server certificate and/or signing certificate.");
		process::exit(1);
	}
	// An expired certificate leaves a client that cannot connect (server cert)
	// or register (signing cert), so refuse to import rather than leave a
	// broken configuration behind.
	if let Err(msg) = check_cert_validity("server", &prov.certificates.server) {
		dbout(debug, 1, &msg);
		process::exit(1);
	}
	if let Err(msg) = check_cert_validity("signing", &prov.certificates.signing) {
		dbout(debug, 1, &msg);
		process::exit(1);
	}

	let fpnt = write_client_config(
		prov.server.host.trim(),
		prov.server.port,
		&prov.server.key,
		prov.certificates.server.as_bytes(),
		Some(prov.certificates.signing.as_bytes()),
	);

	dbout(debug, 0, "Luminum Client provisioning imported.");
	dbout(debug, 0, &format!("Luminum Server: {}:{}", prov.server.host, prov.server.port));
	dbout(debug, 0, &format!("Client fingerprint: {}", fpnt));
	dbout(debug, 0, "Luminum Client configuration complete.");
	process::exit(0);
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

fn get_os_release() -> String {
	// The server validates osrel against ^[A-Za-z0-9\s\.\-]+$ (protocol
	// 6.1), so strip anything outside that set from the pretty name.
	match OsRelease::open() {
		Ok(result) => result
			.pretty_name()
			.chars()
			.map(|c| if c.is_ascii_alphanumeric() || matches!(c, ' ' | '.' | '-') { c } else { ' ' })
			.collect::<String>()
			.split_whitespace()
			.collect::<Vec<_>>()
			.join(" "),
		Err(_) => String::from("Unknown"),
	}
}

fn dbout(debug: bool, outlvl: i32, output: &str) {
	let dateformat = StrftimeItems::new("%Y-%m-%d %H:%M:%S");
	let current_datetime = Local::now();
	let formatted_datetime = current_datetime.format_with_items(dateformat).to_string();
	let mut etype = String::new();

	if debug {
		if outlvl == 0 { etype = "PROC".cyan().to_string(); }
		else if outlvl == 1 { etype = "FAIL".red().to_string(); }
		else if outlvl == 2 { etype = "WARN".yellow().to_string(); }
		else if outlvl == 3 { etype = " OK ".green().to_string(); }
		else if outlvl == 4 { etype = "INFO".to_string(); }
		println!("{} [{}] {}", formatted_datetime, etype, output);
	} else {
		if outlvl == 1 { println!("{}", output); }
	}
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() {
	let matches = App::new("Luminum Client (Linux)")
		.version(VER)
		.author("Christopher R. Curzio <ccurzio@luminum.net>")
		.arg(Arg::with_name("setup")
			.short('s')
			.long("setup")
			.help("Set client configuration parameters")
			.takes_value(false))
		.arg(Arg::with_name("debug")
			.short('d')
			.long("debug")
			.help("Enables debug mode")
			.takes_value(false))
		.arg(Arg::with_name("import")
			.short('i')
			.long("import")
			.help("Import a provisioning file (config.ini) instead of the wizard")
			.takes_value(true))
		.arg(Arg::with_name("deregister")
			.long("deregister")
			.help("Deregister this endpoint from the server and remove the local configuration")
			.takes_value(false))
		.get_matches();

	let setup = matches.is_present("setup");
	let debug = matches.is_present("debug");
	let import = matches.value_of("import");
	let deregister = matches.is_present("deregister");

	// Break handler
	let running = Arc::new(AtomicBool::new(true));
	let r = running.clone();
	ctrlc::set_handler(move || {
		r.store(false, Ordering::SeqCst);
		print!("\r\x1B[K");
		io::stdout().flush().unwrap_or(());
		dbout(false, 0, "Received BREAK signal.");
		dbout(false, 0, "Luminum Client Terminated.");
		process::exit(1);
	}).expect("Error creating break handler");

	// Setup routine
	if setup {
		dbout(debug, 4, "Starting client setup...");
		if fs::metadata(cfg_path()).is_err() {
			clientsetup();
		} else {
			dbout(debug, 1, "Client configuration already exists. Aborting.");
			process::exit(1);
		}
	} else if let Some(path) = import {
		dbout(debug, 4, "Starting client provisioning import...");
		if fs::metadata(cfg_path()).is_err() {
			clientimport(path, debug);
		} else {
			dbout(debug, 1, "Client configuration already exists. Aborting.");
			process::exit(1);
		}
	} else if deregister {
		dbout(debug, 4, "Starting endpoint deregistration...");
		if fs::metadata(cfg_path()).is_err() {
			dbout(debug, 1, "Client configuration not found. Nothing to deregister.");
			process::exit(1);
		}
		deregister_with_server(debug);
		process::exit(0);
	}

	// Client startup
	dbout(debug, 0, &format!("Starting Luminum Client v{}...", VER));

	let ccfg = parse_clientconfig(debug);

	// Register with the server if not yet registered
	if ccfg.get("UID").is_none() {
		dbout(debug, 4, "Endpoint is not registered with the Luminum server. Sending registration request...");
		register_with_server(debug, &ccfg);
	} else {
		dbout(debug, 3, &format!("Endpoint is registered with UID {}", ccfg.get("UID").unwrap()));
	}

	// Re-read the configuration: registration (above) writes UID/SID/MQTT* to
	// the config DB, which the in-memory snapshot does not reflect.
	let ccfg = parse_clientconfig(debug);

	// Client TLS certificate (protocol §7.1 v1.1): a registered endpoint
	// without a channel certificate on file (fleet upgrade to P2P, or a
	// registration the server could not certificate) requests a re-issue.
	if ccfg.get("UID").is_some() && !Path::new(&client_crt_path()).exists() {
		dbout(debug, 4, "No client TLS certificate on file. Requesting a certificate re-issue...");
		certrenew_with_server(debug, &ccfg);
	}

	// Sensor definitions table (protocol §7.3): the home for sensor scripts
	// pushed by the server in core/config commands.
	ensure_sensors_table(debug);

	// MQTT control channel (protocol §4): persistent session, LWT, periodic
	// check-ins, and command handling. The client is built here so the data
	// channel's report path can share it; None when the endpoint is not yet
	// registered or lacks MQTT parameters (the client keeps running: IPC,
	// Lumys, data listener).
	let mqtt = mqtt_client(debug, &ccfg);
	// The data channel shares the MQTT client for transfer reports; extract
	// the clones before the control channel takes ownership of the client.
	let p2p_mqtt = mqtt.as_ref().map(|(c, _, _)| c.clone());
	let p2p_connected = mqtt.as_ref().map(|(_, _, f)| f.clone()).unwrap_or_else(|| Arc::new(AtomicBool::new(false)));
	spawn(mqtt_run(debug, ccfg.clone(), mqtt));

	// Local IPC listener (Lumy channel)
	let ipc_addr: SocketAddr = format!("127.0.0.1:{}", LPORT).parse().expect("Invalid IPC socket address");
	let ipclistener = match TcpListener::bind(ipc_addr) {
		Ok(l) => {
			dbout(debug, 3, &format!("Local IPC configured on port {}", LPORT));
			l
		}
		Err(err) => {
			dbout(debug, 1, &format!("Unable to configure local IPC: {}", err));
			process::exit(1);
		}
	};

	// Inbound data listener (server -> client bulk data, protocol §2, §8.3;
	// the P2P seed path, docs/p2p.md 3). Bound at startup like the IPC
	// listener; each connection is served on its own thread.
	let ip_address = local_ip().map(|a| a.to_string()).unwrap_or_default();
	let data_addr: SocketAddr = format!("{}:{}", ip_address, IPORT).parse().expect("Invalid data socket address");
	let datalistener = match TcpListener::bind(data_addr) {
		Ok(l) => {
			dbout(debug, 3, &format!("Incoming data connection configured on port {}", IPORT));
			l
		}
		Err(err) => {
			dbout(debug, 1, &format!("Unable to configure incoming data connection: {}", err));
			process::exit(1);
		}
	};
	// Session state shared with the data handler: the rustls acceptor
	// configuration (needs the client certificate), the MQTT client for
	// transfer reports, and the used-token ring. An unregistered endpoint
	// (no UID) or one without the server signing key cannot validate a
	// grant; its sessions are refused.
	let p2p_cfg = p2p_acceptor_config(debug);
	let (p2p_uid, p2p_seed, p2p_srvpub) = match (ccfg.get("UID"), server_pubkey(&ccfg)) {
		(Some(uid), Some(srvpub)) => {
			let (seed, _pubb) = client_keypair(debug, &ccfg);
			(uid.clone(), seed, srvpub)
		}
		_ => (String::new(), [0u8; 32], [0u8; 32]),
	};
	let p2p_ring = token_ring_new();
	let p2p_resp_topic = format!("luminum/{}/{}/resp", ccfg.get("SID").cloned().unwrap_or_default(), p2p_uid);
	let p2p_handle = tokio::runtime::Handle::current();
	let dbc = debug;
	thread::spawn(move || {
		for stream in datalistener.incoming() {
			match stream {
				Ok(stream) => {
					let (cfg, uid, seed, srvpub, mqtt, connected, ring, topic, handle) = (
						p2p_cfg.clone(), p2p_uid.clone(), p2p_seed, p2p_srvpub,
						p2p_mqtt.clone(), p2p_connected.clone(), p2p_ring.clone(),
						p2p_resp_topic.clone(), p2p_handle.clone(),
					);
					thread::spawn(move || {
						if let Some(cfg) = cfg {
							handle_data_session(stream, cfg, uid, seed, srvpub, mqtt, handle, connected, ring, topic, dbc);
						} else {
							dbout(dbc, 2, "Data channel connection dropped: no client TLS certificate on file (the P2P channel is unavailable until the endpoint is certificated).");
						}
					});
				}
				Err(err) => {
					dbout(dbc, 2, &format!("Error establishing data connection: {}", err));
				}
			}
		}
	});

	// Discover and launch Lumys
	let lumys = discover_lumys(debug);
	for (lumy, lpath) in &lumys {
		start_lumy(lumy, lpath, debug);
		if lumys.len() > 1 { thread::sleep(Duration::from_secs(2)); }
	}

	// IPC accept loop. Runs on its own thread so the main task can keep
	// the tokio runtime alive (worker threads run the check-in task).
	thread::spawn(move || {
		for stream in ipclistener.incoming() {
			match stream {
				Ok(stream) => {
					thread::spawn(move || {
						if let Err(err) = handle_ipc(stream, dbc) {
							dbout(dbc, 2, &format!("Error handling IPC connection: {}", err));
						}
					});
				}
				Err(err) => {
					dbout(dbc, 2, &format!("Error establishing IPC connection: {}", err));
				}
			}
		}
	});

	// Keep the client process (and runtime) alive.
	time::sleep(std::time::Duration::MAX).await;
}

#[cfg(test)]
mod sensorpair_tests {
	use super::*;

	fn entry(lstype: Option<&str>, lscript: Option<&str>) -> serde_json::Value {
		let mut v = serde_json::json!({ "sid": 1, "name": "Test" });
		if let Some(t) = lstype { v["lstype"] = serde_json::json!(t); }
		if let Some(s) = lscript { v["lscript"] = serde_json::json!(s); }
		v
	}

	#[test]
	fn pair_defined_for_linux() {
		for t in ["shell", "perl", "python"] {
			assert_eq!(
				sensor_pair_for_this_os(&entry(Some(t), Some("echo hi"))),
				Ok(Some((t.to_string(), "echo hi".to_string())))
			);
		}
	}

	#[test]
	fn pair_missing_for_linux_is_skipped() {
		// A sensor defined only for other platforms (the server stores NULL
		// for disabled platforms) is skipped, not an error.
		assert_eq!(sensor_pair_for_this_os(&entry(None, None)), Ok(None));
		assert_eq!(sensor_pair_for_this_os(&entry(Some("shell"), None)), Ok(None));
		assert_eq!(sensor_pair_for_this_os(&entry(None, Some("echo hi"))), Ok(None));
	}

	#[test]
	fn pair_present_but_malformed_is_invalid() {
		assert_eq!(sensor_pair_for_this_os(&entry(Some("powershell"), Some("x"))), Err(()));
		assert_eq!(sensor_pair_for_this_os(&entry(Some("shell"), Some(""))), Err(()));
	}

	#[test]
	fn newlines_normalized_to_lf() {
		assert_eq!(normalize_newlines("if true\r\nthen echo hi\r\nfi"), "if true\nthen echo hi\nfi");
		assert_eq!(normalize_newlines("a\rb\nc"), "a\nb\nc");
		assert_eq!(normalize_newlines("a\nb\nc"), "a\nb\nc");
	}
}

#[cfg(test)]
mod provision_cert_tests {
	use super::*;
	use std::path::PathBuf;

	// Run the openssl CLI (present in the dev container); return its stdout,
	// failing the test on a nonzero exit.
	fn openssl(args: &[&str]) -> String {
		let out = Command::new("openssl")
			.args(args)
			.output()
			.expect("openssl CLI is required for this test");
		assert!(
			out.status.success(),
			"openssl {} failed: {}",
			args.join(" "),
			String::from_utf8_lossy(&out.stderr)
		);
		String::from_utf8_lossy(&out.stdout).into_owned()
	}

	// A self-signed certificate with an explicit validity window (OpenSSL 3.x
	// -not_before/-not_after); returns its PEM.
	fn make_cert(d: &PathBuf, name: &str, not_before: &str, not_after: &str) -> String {
		let key = d.join(format!("{}.key", name));
		let csr = d.join(format!("{}.csr", name));
		let crt = d.join(format!("{}.crt", name));
		openssl(&[
			"req", "-newkey", "rsa:2048", "-nodes",
			"-keyout", &key.to_string_lossy(),
			"-out", &csr.to_string_lossy(),
			"-subj", "/CN=luminum-test",
		]);
		openssl(&[
			"x509", "-req", "-in", &csr.to_string_lossy(),
			"-signkey", &key.to_string_lossy(),
			"-not_before", not_before, "-not_after", not_after,
			"-out", &crt.to_string_lossy(),
		]);
		fs::read_to_string(&crt).expect("read generated cert")
	}

	#[test]
	fn cert_validity_cases() {
		let d = std::env::temp_dir().join(format!(
			"luminum-provcert-{}-{}",
			std::process::id(),
			std::time::SystemTime::now()
				.duration_since(std::time::UNIX_EPOCH)
				.map(|x| x.as_nanos())
				.unwrap_or(0)
		));
		fs::create_dir_all(&d).expect("create temp dir");

		// A currently-valid certificate passes.
		let valid = make_cert(&d, "valid", "20200101000000Z", "20990101000000Z");
		assert_eq!(check_cert_validity("server", &valid), Ok(()), "valid certificate must pass");

		// An expired certificate is rejected with an expiry message naming it.
		let expired = make_cert(&d, "expired", "20200101000000Z", "20210101000000Z");
		let err = check_cert_validity("signing", &expired).unwrap_err();
		assert!(err.contains("expired"), "expired certificate must be reported as expired, got: {}", err);
		assert!(err.contains("signing"), "the message must name the certificate, got: {}", err);

		// A non-certificate is rejected as invalid.
		let err = check_cert_validity("server", "not a certificate").unwrap_err();
		assert!(err.contains("not a valid X.509"), "a non-certificate must be reported as invalid, got: {}", err);

		let _ = fs::remove_dir_all(&d);
	}
}

#[cfg(test)]
mod connect_any_tests {
	use super::*;

	#[test]
	fn falls_back_to_next_address_when_first_fails() {
		// An IPv4-only listener: the address list leads with the IPv6
		// loopback on the same port (refused, or unreachable on a box
		// without IPv6), so the dial must fall through to the IPv4 one.
		let listener = TcpListener::bind("127.0.0.1:0").expect("bind IPv4 loopback");
		let port = listener.local_addr().expect("listener addr").port();
		let v6: SocketAddr = format!("[::1]:{}", port).parse().expect("parse IPv6 addr");
		let v4: SocketAddr = format!("127.0.0.1:{}", port).parse().expect("parse IPv4 addr");
		let mut sconn = connect_any(&[v6, v4], false).expect("must fall back to the IPv4 address");
		let (mut peer, _) = listener.accept().expect("accept");
		sconn.write_all(b"x").expect("write");
		let mut buf = [0u8; 1];
		assert_eq!(peer.read(&mut buf).expect("read"), 1);
		assert_eq!(buf, [b'x']);
	}

	#[test]
	fn all_addresses_failing_returns_err() {
		// A port nothing listens on (taken and released by a listener):
		// every dial is refused and the error surfaces.
		let listener = TcpListener::bind("127.0.0.1:0").expect("bind IPv4 loopback");
		let port = listener.local_addr().expect("listener addr").port();
		drop(listener);
		let a: SocketAddr = format!("127.0.0.1:{}", port).parse().expect("parse addr");
		let b: SocketAddr = format!("[::1]:{}", port).parse().expect("parse addr");
		assert!(connect_any(&[a, b], false).is_err());
	}
}

#[cfg(test)]
mod p2p_tests {
	use super::*;

	const SEED: [u8; 32] = [7u8; 32];
	const OTHER_SEED: [u8; 32] = [9u8; 32];

	fn pub_of(seed: [u8; 32]) -> [u8; 32] {
		SigningKey::from_bytes(&seed).verifying_key().to_bytes()
	}

	fn valid_files() -> serde_json::Value {
		serde_json::json!([
			{ "fileid": 1, "path": "bin/tool", "size": 100, "sha256": "ab".repeat(32) },
			{ "fileid": 2, "path": "lib/helper.so", "size": 200, "sha256": "cd".repeat(32) },
		])
	}

	// A grant envelope of the seed form (server-only source list), signed by
	// $seed.
	fn grant(uid: &str, token: &str, exp: i64, files: serde_json::Value, seed: &[u8; 32]) -> Envelope {
		let mut env = new_envelope("server", uid, "core", "p2pgrant", "OK", Some(serde_json::json!({
			"token": token,
			"pkgid": 7,
			"os": "Linux",
			"aid": "cmd-123",
			"files": files,
			"sources": [{ "uid": 0, "ip": "10.0.0.1", "port": 10704 }],
			"exp": exp,
		})));
		sign_envelope(&mut env, seed);
		env
	}

	#[test]
	fn safe_rel_path_cases() {
		assert!(is_safe_rel_path("bin/tool"));
		assert!(is_safe_rel_path("a/b/c"));
		assert!(is_safe_rel_path("a/..b/c"));   // a component that merely starts with ".."
		assert!(!is_safe_rel_path(""));
		assert!(!is_safe_rel_path("/abs"));
		assert!(!is_safe_rel_path("a/../b"));
		assert!(!is_safe_rel_path(".."));
	}

	#[test]
	fn grant_valid() {
		let ring = token_ring_new();
		let now = Local::now().timestamp();
		let env = grant("42", &uuid4(), now + 300, valid_files(), &SEED);
		let g = validate_grant(&env, "42", &pub_of(SEED), &ring, now).expect("valid grant");
		assert_eq!(g.pkgid, 7);
		assert_eq!(g.aid, "cmd-123");
		assert_eq!(g.files.len(), 2);
		assert_eq!(g.files[0].fileid, 1);
		assert_eq!(g.files[1].path, "lib/helper.so");
	}

	#[test]
	fn grant_bad_signature() {
		let ring = token_ring_new();
		let now = Local::now().timestamp();
		let env = grant("42", &uuid4(), now + 300, valid_files(), &OTHER_SEED);
		let err = validate_grant(&env, "42", &pub_of(SEED), &ring, now).unwrap_err();
		assert_eq!(err, "BAD_GRANT");
	}

	#[test]
	fn grant_wrong_uid() {
		let ring = token_ring_new();
		let now = Local::now().timestamp();
		let env = grant("99", &uuid4(), now + 300, valid_files(), &SEED);
		let err = validate_grant(&env, "42", &pub_of(SEED), &ring, now).unwrap_err();
		assert_eq!(err, "UID_MISMATCH");
	}

	#[test]
	fn grant_expired() {
		let ring = token_ring_new();
		let now = Local::now().timestamp();
		let env = grant("42", &uuid4(), now - 1, valid_files(), &SEED);
		let err = validate_grant(&env, "42", &pub_of(SEED), &ring, now).unwrap_err();
		assert_eq!(err, "GRANT_EXPIRED");
	}

	#[test]
	fn grant_used() {
		let ring = token_ring_new();
		let now = Local::now().timestamp();
		let token = uuid4();
		token_consume(&ring, &token);
		let env = grant("42", &token, now + 300, valid_files(), &SEED);
		let err = validate_grant(&env, "42", &pub_of(SEED), &ring, now).unwrap_err();
		assert_eq!(err, "GRANT_USED");
	}

	#[test]
	fn grant_unsafe_path() {
		let ring = token_ring_new();
		let now = Local::now().timestamp();
		let files = serde_json::json!([{ "fileid": 1, "path": "a/../../etc/passwd", "size": 10, "sha256": "ab".repeat(32) }]);
		let env = grant("42", &uuid4(), now + 300, files, &SEED);
		let err = validate_grant(&env, "42", &pub_of(SEED), &ring, now).unwrap_err();
		assert_eq!(err, "BAD_GRANT");
	}

	#[test]
	fn grant_wrong_action() {
		let ring = token_ring_new();
		let now = Local::now().timestamp();
		let mut env = grant("42", &uuid4(), now + 300, valid_files(), &SEED);
		env.action = String::from("p2pfetch");
		let err = validate_grant(&env, "42", &pub_of(SEED), &ring, now).unwrap_err();
		assert_eq!(err, "BAD_GRANT");
	}

	#[test]
	fn grant_empty_files() {
		let ring = token_ring_new();
		let now = Local::now().timestamp();
		let env = grant("42", &uuid4(), now + 300, serde_json::json!([]), &SEED);
		let err = validate_grant(&env, "42", &pub_of(SEED), &ring, now).unwrap_err();
		assert_eq!(err, "BAD_GRANT");
	}

	#[test]
	fn grant_bad_sha() {
		let ring = token_ring_new();
		let now = Local::now().timestamp();
		let files = serde_json::json!([{ "fileid": 1, "path": "bin/tool", "size": 10, "sha256": "zz".repeat(32) }]);
		let env = grant("42", &uuid4(), now + 300, files, &SEED);
		let err = validate_grant(&env, "42", &pub_of(SEED), &ring, now).unwrap_err();
		assert_eq!(err, "BAD_GRANT");
	}

	#[test]
	fn raw_frame_chunk_and_eof() {
		let mut buf = Vec::new();
		buf.extend_from_slice(&3u32.to_be_bytes());
		buf.extend_from_slice(b"abc");
		buf.extend_from_slice(&0u32.to_be_bytes());   // zero-length frame: EOF
		let mut r = std::io::Cursor::new(buf);
		assert_eq!(raw_frame_read(&mut r).unwrap(), Some(vec![b'a', b'b', b'c']));
		assert_eq!(raw_frame_read(&mut r).unwrap(), None);
	}

	#[test]
	fn raw_frame_oversized() {
		let mut buf = Vec::new();
		buf.extend_from_slice(&u32::MAX.to_be_bytes());
		let mut r = std::io::Cursor::new(buf);
		assert!(raw_frame_read(&mut r).is_err());
	}

	#[test]
	fn token_ring_consume() {
		let ring = token_ring_new();
		assert!(!token_seen(&ring, "t1"));
		token_consume(&ring, "t1");
		assert!(token_seen(&ring, "t1"));
		assert!(!token_seen(&ring, "t2"));
	}

	#[test]
	fn manifest_upsert_roundtrip() {
		// LUMINUM_HOME is process-global; this is the only test using it.
		let home = format!("/tmp/luminum_p2p_manifest_{}", std::process::id());
		std::env::set_var("LUMINUM_HOME", &home);
		manifest_upsert(11, 7, "Linux", "bin/tool", 100, &"ab".repeat(32));
		let conn = manifest_conn().expect("manifest db");
		let (pkgid, path, size, sha): (i64, String, i64, String) = conn.query_row(
			"select PKGID, PATH, SIZE, SHA256 from MANIFEST where FILEID = 11",
			[], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
		).expect("row");
		assert_eq!((pkgid, path, size, sha), (7, "bin/tool".to_string(), 100, "ab".repeat(32)));
		// Re-upsert with a different package: the row is updated, not duplicated.
		manifest_upsert(11, 8, "Linux", "bin/tool2", 101, &"cd".repeat(32));
		let n: i64 = conn.query_row("select count(*) from MANIFEST where FILEID = 11", [], |r| r.get(0)).unwrap();
		assert_eq!(n, 1);
		let pkgid2: i64 = conn.query_row("select PKGID from MANIFEST where FILEID = 11", [], |r| r.get(0)).unwrap();
		assert_eq!(pkgid2, 8);
		conn.close().ok();
		fs::remove_dir_all(&home).ok();
		std::env::remove_var("LUMINUM_HOME");
	}
}
