// Luminum Client for Linux
// by Christopher R. Curzio <ccurzio@luminum.net>

// Base client process: configuration, registration, check-ins, Lumy
// discovery/launch, and the local IPC channel (port 10461) used by
// Lumy modules to talk to the client.
//
// Protocol notes (docs/protocol.md v1.0-draft):
//  - All direct channels use length-prefixed frames: 4-byte big-endian
//    length followed by a JSON envelope (§8.2).
//  - The envelope format is §5.1. MQTT transport is not yet available
//    (Mosquitto + broker integration pending), so registration,
//    check-ins, and Lumy traffic currently ride the bootstrap/direct
//    channel to the server listener (LPORT 10465).
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
use std::sync::atomic::{AtomicBool, Ordering};
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
use std::collections::HashMap;
use std::sync::Arc;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::io::{self, Read, Write};
use std::time::Duration;
use rusqlite::{params, Connection};
use serde::{Serialize, Deserialize};
use std::path::Path;

use base64ct::Encoding;
use ed25519_dalek::{Signer, Verifier, SigningKey, VerifyingKey, Signature};
use sha2::{Digest, Sha256};

const VER: &str = "0.0.1";
const IPORT: u16 = 10704;
const DPORT: u16 = 10465;
const LPORT: u16 = 10461;
const CHECKIN_SECS: u64 = 300;
// This client's OS platform (protocol §4.2 / §6.1). Used both in the check-in
// payload (osplat) and to build the OS group topic luminum/{SID}/os/{os}/cmd.
const OSPLAT: &str = "Linux";

// Install root; overridable via LUMINUM_HOME for testing.
fn base_path() -> String {
	std::env::var("LUMINUM_HOME").unwrap_or_else(|_| String::from("/opt/Luminum/LuminumClient"))
}

fn cfg_path() -> String { format!("{}/config/client.conf.db", base_path()) }
fn crt_path() -> String { format!("{}/config/server.crt", base_path()) }
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
// Server channel (bootstrap/direct, TLS + framed JSON)
// ---------------------------------------------------------------------------

fn server_connect(server_host: &str, server_port: &str, cert_path: &str, debug: bool) -> Result<TlsStream<TcpStream>, Box<dyn Error>> {
	let server_addr_str = format!("{}:{}", server_host, server_port);
	let server_addr = server_addr_str.to_socket_addrs()?.next().ok_or("No addresses found for hostname")?;

	let sconn = loop {
		match TcpStream::connect(server_addr) {
			Ok(sconn) => break sconn,
			Err(err) => {
				dbout(debug, 2, &format!("Connection to Luminum server failed: {}", err));
				dbout(debug, 4, "Retrying connection in 30 seconds...");
				thread::sleep(Duration::from_secs(30));
			}
		}
	};

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

	let data = serde_json::json!({
		"hostname": endpointname,
		"serverkey": ccfg.get("SVRKEY").cloned().unwrap_or_default(),
		"uid": "0",
		"pubkey": base64ct::Base64::encode_string(spki_der(&pubb).as_slice()),
		"fingerprint": fingerprint(&pubb),
		"osplat": "Linux",
		"osrel": get_os_release(),
		"clientver": VER,
		"ipv4": ip_address
	});

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
			} else {
				dbout(debug, 1, &format!("Registration failed: {} {}", response.status, response.err.unwrap_or_default()));
			}
		}
		Err(err) => dbout(debug, 2, &format!("Unable to send registration to server: {}", err)),
	}
}

// ---------------------------------------------------------------------------
// MQTT control channel (protocol §4)
// ---------------------------------------------------------------------------

// Check-in interval (seconds); overridable via LUMINUM_CHECKIN_SECS for
// testing. Protocol §4.4: status check-ins are QoS 0, retained.
fn checkin_secs() -> u64 {
	std::env::var("LUMINUM_CHECKIN_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(CHECKIN_SECS)
}

// Build and sign a check-in envelope (protocol §6.1: action=checkin,
// status=OK) and return its JSON wire bytes.
fn build_checkin(uid: &str, seed: &[u8; 32]) -> Vec<u8> {
	let endpointname = gethostname().to_string_lossy().into_owned();
	let ip_address = local_ip().map(|a| a.to_string()).unwrap_or_default();
	let data = serde_json::json!({
		"hostname": endpointname,
		"osplat": OSPLAT,
		"osrel": get_os_release(),
		"clientver": VER,
		"ipv4": ip_address
	});
	let mut msg = new_envelope("client", uid, "core", "checkin", "OK", Some(data));
	sign_envelope(&mut msg, seed);
	serde_json::to_vec(&msg).expect("Error: unable to serialize check-in envelope")
}

// The client's long-lived MQTT control channel (protocol §4): connects to the
// broker over TLS with username/password auth, a persistent session, and a
// pre-signed offline LWT; subscribes to its command topic; publishes periodic
// check-ins on the status topic; and processes incoming commands. Reconnects
// automatically on failure (poll() re-establishes the connection).
async fn mqtt_run(debug: bool, ccfg: HashMap<String, String>) {
	use rumqttc::{AsyncClient, ConnectionError, Event, LastWill, MqttOptions, Packet, QoS, Transport};
	use std::collections::VecDeque;

	// MQTT connection parameters (protocol §4.1). A missing value means the
	// control channel cannot start; the client keeps running (IPC, Lumys).
	let uid = match ccfg.get("UID") { Some(v) => v.clone(), None => return };
	let sid = match ccfg.get("SID") { Some(v) => v.clone(), None => { dbout(debug, 1, "No server ID (SID) on file; MQTT control channel unavailable."); return; } };
	let secret = match ccfg.get("MQTTSECRET") { Some(v) => v.clone(), None => { dbout(debug, 1, "No MQTT secret on file; MQTT control channel unavailable."); return; } };
	let host = match ccfg.get("MQTTHOST") { Some(v) => v.clone(), None => { dbout(debug, 1, "No MQTT host on file; MQTT control channel unavailable."); return; } };
	let port: u16 = match ccfg.get("MQTTPORT").and_then(|p| p.parse().ok()) { Some(p) => p, None => { dbout(debug, 1, "No valid MQTT port on file; MQTT control channel unavailable."); return; } };

	let (seed, _clpub) = client_keypair(debug, &ccfg);
	let srvpub = server_pubkey(&ccfg);

	// Topic tree (protocol §4.2). The client subscribes to its own command
	// topic plus the group command topics it belongs to: all endpoints, its OS,
	// and any custom groups (GROUPS = comma-separated names, set by the server
	// via a setgroups command). Groups carry commands only (server -> client);
	// responses/check-ins always go to the per-UID topics below.
	let status_topic = format!("luminum/{}/{}/status", sid, uid);
	let resp_topic = format!("luminum/{}/{}/resp", sid, uid);
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

	// LWT: a pre-signed offline envelope (protocol §7.5), retained, QoS 1.
	// Re-sent in the CONNECT packet on every (re)connect.
	let mut offline = new_envelope("client", &uid, "core", "checkin", "offline", None);
	sign_envelope(&mut offline, &seed);
	let offline_payload = serde_json::to_vec(&offline).expect("Error: unable to serialize LWT envelope");
	let will = LastWill::new(&status_topic, offline_payload, QoS::AtLeastOnce, true);

	// TLS trust anchor: the server certificate (config/server.crt).
	let ca = match fs::read(crt_path()) {
		Ok(c) => c,
		Err(_) => { dbout(debug, 1, "Server certificate not found (config/server.crt); MQTT control channel unavailable."); return; }
	};

	let mut mopts = MqttOptions::new(&uid, &host, port);
	mopts.set_transport(Transport::tls(ca, None, None));
	mopts.set_credentials(&uid, &secret);
	mopts.set_clean_session(false);
	mopts.set_keep_alive(Duration::from_secs(60));
	mopts.set_max_packet_size(65536, 65536);
	mopts.set_last_will(will);

	let (client, mut eventloop) = AsyncClient::new(mopts, 100);

	// Shared connection state for the check-in subtask.
	let connected = Arc::new(AtomicBool::new(false));

	// Periodic check-ins (protocol §4.4). Gated on connection state so no
	// check-ins accumulate in the request channel while offline.
	let checkin_client = client.clone();
	let checkin_seed = seed;
	let checkin_uid = uid.clone();
	let checkin_topic = status_topic.clone();
	let checkin_flag = connected.clone();
	spawn(async move {
		let mut interval = time::interval(Duration::from_secs(checkin_secs()));
		loop {
			interval.tick().await;
			if !checkin_flag.load(Ordering::SeqCst) { continue; }
			let payload = build_checkin(&checkin_uid, &checkin_seed);
			let _ = checkin_client.publish(checkin_topic.clone(), QoS::AtMostOnce, true, payload).await;
		}
	});

	// Command deduplication (protocol §9.2): bounded ring of recent message ids.
	let mut seen: VecDeque<String> = VecDeque::with_capacity(1024);

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
				let payload = build_checkin(&uid, &seed);
				let _ = client.publish(&status_topic, QoS::AtMostOnce, true, payload).await;
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
				// Apply the command (protocol 6). core/setgroups applies a
				// group-membership change to this endpoint; the remaining
				// actions (query/deploy/config) are follow-ons.
				let cmd_err = if env.lumy == "core" && env.action == "setgroups" {
					apply_setgroups(&client, &mut cmd_topics, &env, &sid, debug).await
				} else {
					None
				};
				// Acknowledge on the resp topic (the server's worker marks
				// the matching outbox command ACKED).
				let mut resp = new_envelope("client", &uid, &env.lumy, &env.action,
					match &cmd_err { Some(_) => "ERR", None => "OK" }, None);
				resp.err = cmd_err;
				sign_envelope(&mut resp, &seed);
				let payload = serde_json::to_vec(&resp).expect("Error: unable to serialize response");
				if let Err(err) = client.publish(&resp_topic, QoS::AtLeastOnce, false, payload).await {
					dbout(debug, 1, &format!("MQTT response publish failed: {}", err));
				}
			}
			Ok(_) => {}
			Err(ConnectionError::ConnectionRefused(code)) => {
				connected.store(false, Ordering::SeqCst);
				dbout(debug, 1, &format!("MQTT connection refused (code {:?}); check credentials.", code));
				time::sleep(Duration::from_secs(30)).await;
			}
			Err(err) => {
				connected.store(false, Ordering::SeqCst);
				dbout(debug, 2, &format!("MQTT connection error: {} (reconnecting)", err));
				time::sleep(Duration::from_secs(5)).await;
			}
		}
	}
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

	if let Some(parent) = Path::new(&cfg_path()).parent() {
		fs::create_dir_all(parent).expect("Error: Could not create configuration directory");
	}
	fs::write(crt_path(), &cert_pem).expect("Error: Could not save server certificate");
	if let Some(pem) = &signing_pem {
		fs::write(signing_crt_path(), pem).expect("Error: Could not save server signing certificate");
	}
	let confconn = Connection::open(cfg_path()).expect("Error: Could not initialize configuration database");
	// KEY is unique: config_set relies on INSERT OR REPLACE semantics.
	confconn.execute("create table if not exists CONFIG ( KEY text not null unique, VALUE text not null )", [])
		.expect("Error: Could not create CONFIG table in configuration database");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["SHOST", server.as_str()])
		.expect("Error: Could not insert SHOST into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["SPORT", port.to_string().as_str()])
		.expect("Error: Could not insert SPORT into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["SVRKEY", server_key.as_str()])
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
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)", params!["FPNT", fpnt.as_str()])
		.expect("Error: Could not insert FPNT into CONFIG table.");
	confconn.close().unwrap();
	// The config DB holds the client's private signing key (CLPPRV).
	fs::set_permissions(&cfg_path(), fs::Permissions::from_mode(0o600))
		.expect("Error: Could not secure configuration database");

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
		.get_matches();

	let setup = matches.is_present("setup");
	let debug = matches.is_present("debug");

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

	// MQTT control channel (protocol §4): persistent session, LWT, periodic
	// check-ins, and command handling. Returns immediately (no-op) when the
	// client is not yet registered or lacks MQTT parameters.
	spawn(mqtt_run(debug, ccfg));

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

	// Inbound data listener (server -> client bulk data, protocol §2)
	let ip_address = local_ip().map(|a| a.to_string()).unwrap_or_default();
	let data_addr: SocketAddr = format!("{}:{}", ip_address, IPORT).parse().expect("Invalid data socket address");
	// TODO: data channel handler (server -> client bulk transfer, protocol §8.3)
	let _datalistener = match TcpListener::bind(data_addr) {
		Ok(l) => {
			dbout(debug, 3, &format!("Incoming data connection configured on port {}", IPORT));
			l
		}
		Err(err) => {
			dbout(debug, 1, &format!("Unable to configure incoming data connection: {}", err));
			process::exit(1);
		}
	};

	// Discover and launch Lumys
	let lumys = discover_lumys(debug);
	for (lumy, lpath) in &lumys {
		start_lumy(lumy, lpath, debug);
		if lumys.len() > 1 { thread::sleep(Duration::from_secs(2)); }
	}

	// IPC accept loop. Runs on its own thread so the main task can keep
	// the tokio runtime alive (worker threads run the check-in task).
	let dbc = debug;
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
