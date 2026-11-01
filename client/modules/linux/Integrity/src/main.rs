// Luminum Integrity Lumy for Linux
// by Christopher R. Curzio <ccurzio@luminum.net>
//
// File integrity monitoring module:
//  - Watches configured filesystem paths in real time via inotify
//    (notify + notify-debouncer-full).
//  - Records every filesystem change locally in the IM log database.
//  - Sends a signed-envelope alert to the Luminum Client process over
//    the local IPC channel (port 10461) for each change; the client
//    forwards/queues the alert for the server.
//
// Protocol notes (docs/protocol.md v1.0-draft):
//  - IPC uses length-prefixed JSON frames (§8.2), envelope per §5.1
//    with src = "lumy".
//  - Every envelope is signed with the client's Ed25519 key (§8.2);
//    responses from the client are verified under the client public
//    key before use.

use std::env;
use std::fs;
use std::io::{Read, Write};
use std::net::{TcpStream, SocketAddr};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::Path;
use std::sync::mpsc;
use std::time::Duration;

use base64ct::Encoding;
use chrono::Local;
use chrono::format::strftime::StrftimeItems;
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use notify::{RecursiveMode, Watcher};
use notify_debouncer_full::{new_debouncer, DebounceEventResult};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use users::get_group_by_gid;
use users::get_user_by_uid;

const VER: &str = "0.0.1";
const LUMY: &str = "integrity";
const IPC_ADDR_STR: &str = "127.0.0.1:10461";
const DEBOUNCE_SECS: u64 = 2;

// Install root; overridable via LUMINUM_HOME for testing.
fn base_path() -> String {
	env::var("LUMINUM_HOME").unwrap_or_else(|_| String::from("/opt/Luminum/LuminumClient"))
}

fn cfg_path() -> String {
	format!("{}/modules/integrity/integrity.conf.db", base_path())
}

fn imlogs_path() -> String {
	format!("{}/modules/integrity/imlogs.db", base_path())
}

fn client_cfg_path() -> String {
	format!("{}/config/client.conf.db", base_path())
}

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
	data: Option<Value>,
	#[serde(skip_serializing_if = "Option::is_none")]
	sig: Option<String>,
}

fn new_envelope(uid: &str, action: &str, status: &str, data: Option<Value>) -> Envelope {
	Envelope {
		v: String::from("1.0"),
		id: uuid4(),
		ts: Local::now().timestamp(),
		src: String::from("lumy"),
		uid: String::from(uid),
		lumy: String::from(LUMY),
		action: String::from(action),
		status: String::from(status),
		err: None,
		data,
		// Signed in place before transmission (sign_envelope, §8.2).
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
// Ed25519 signatures (protocol §3.3, §5.3, §8.2)
// ---------------------------------------------------------------------------

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
// Client keypair (protocol §3.1)
// ---------------------------------------------------------------------------

/// Load the client's Ed25519 keypair from the client configuration
/// database (CLPPRV = base64 32-byte seed, CLPPUB = base64 raw public
/// key). The Lumy runs under the client's trust domain: it signs every
/// envelope with the client key (§8.2) and verifies client responses
/// under the client public key.
fn client_keypair() -> Option<([u8; 32], [u8; 32])> {
	let path = client_cfg_path();
	if fs::metadata(&path).is_err() { return None; }
	let conn = Connection::open(&path).ok()?;
	let mut stmt = conn.prepare("select VALUE from CONFIG where KEY = ?1").ok()?;
	let prv_b64: String = stmt.query_row(params!["CLPPRV"], |row| row.get(0)).ok()?;
	let pub_b64: String = stmt.query_row(params!["CLPPUB"], |row| row.get(0)).ok()?;
	let prv_raw = base64ct::Base64::decode_vec(&prv_b64).ok()?;
	let pub_raw = base64ct::Base64::decode_vec(&pub_b64).ok()?;
	if prv_raw.len() != 32 || pub_raw.len() != 32 { return None; }
	let mut seed = [0u8; 32];
	let mut clpub = [0u8; 32];
	seed.copy_from_slice(&prv_raw);
	clpub.copy_from_slice(&pub_raw);
	Some((seed, clpub))
}

// ---------------------------------------------------------------------------
// Framing (protocol §8.2)
// ---------------------------------------------------------------------------

const MAX_FRAME: usize = 16 * 1024 * 1024;

fn frame_write<W: Write>(w: &mut W, env: &Envelope) -> std::io::Result<()> {
	let payload = serde_json::to_vec(env).expect("Error: unable to serialize envelope");
	if payload.len() > MAX_FRAME {
		return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "frame too large"));
	}
	let len = (payload.len() as u32).to_be_bytes();
	w.write_all(&len)?;
	w.write_all(&payload)?;
	w.flush()
}

fn frame_read<R: Read>(r: &mut R) -> Result<Envelope, Box<dyn std::error::Error>> {
	let mut lenbuf = [0u8; 4];
	r.read_exact(&mut lenbuf)?;
	let len = u32::from_be_bytes(lenbuf) as usize;
	if len == 0 || len > MAX_FRAME {
		return Err("Invalid frame length".into());
	}
	let mut payload = vec![0u8; len];
	r.read_exact(&mut payload)?;
	Ok(serde_json::from_slice(&payload)?)
}

// ---------------------------------------------------------------------------
// IPC to the Luminum Client
// ---------------------------------------------------------------------------

fn ipc_connect(retries: u32) -> Option<TcpStream> {
	let addr: SocketAddr = IPC_ADDR_STR.parse().expect("Invalid IPC address");
	for attempt in 1..=retries {
		match TcpStream::connect(addr) {
			Ok(stream) => {
				let _ = stream.set_read_timeout(Some(Duration::from_secs(30)));
				let _ = stream.set_write_timeout(Some(Duration::from_secs(30)));
				return Some(stream);
			}
			Err(_) => {
				dbout(2, &format!("Could not connect to Luminum Client IPC (attempt {} of {}). Retrying in 5 seconds...", attempt, retries));
				std::thread::sleep(Duration::from_secs(5));
			}
		}
	}
	None
}

/// Send a single framed envelope to the client and read the response.
/// The request is signed with the client key (§8.2) and the response
/// must verify under the client public key before it is returned. A
/// fresh connection is used per exchange (the client handles one
/// frame per connection).
fn ipc_exchange(env: &Envelope, seed: &[u8; 32], clpub: &[u8; 32]) -> Result<Envelope, String> {
	let mut request = env.clone();
	sign_envelope(&mut request, seed);
	let mut stream = ipc_connect(12).ok_or("Could not connect to Luminum Client IPC")?;
	frame_write(&mut stream, &request).map_err(|e| format!("IPC write failed: {}", e))?;
	let response = frame_read(&mut stream).map_err(|e| format!("IPC read failed: {}", e))?;
	if response.src != "client" || !verify_envelope(&response, clpub) {
		return Err("MSG_AUTH_FAIL: response from client failed signature verification".to_string());
	}
	Ok(response)
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

fn client_uid() -> String {
	// The Lumy runs under the client's trust domain and reads the
	// client's UID from the client configuration database.
	let path = client_cfg_path();
	if fs::metadata(&path).is_err() { return String::from("0"); }
	match Connection::open(&path) {
		Ok(conn) => {
			let mut stmt = match conn.prepare("select VALUE from CONFIG where KEY = 'UID'") {
				Ok(s) => s,
				Err(_) => return String::from("0"),
			};
			stmt.query_map(params![], |row| row.get::<_, String>(0))
				.ok()
				.and_then(|mut rows| rows.next())
				.and_then(|r| r.ok())
				.unwrap_or_else(|| String::from("0"))
		}
		Err(_) => String::from("0"),
	}
}

fn ensure_imdb() {
	if let Some(parent) = Path::new(&imlogs_path()).parent() {
		fs::create_dir_all(parent).ok();
	}
	if let Ok(conn) = Connection::open(imlogs_path()) {
		let _ = conn.execute(
			"create table if not exists EVENTS ( ID integer primary key autoincrement, DATE datetime not null, TYPE text not null, PATH text not null, PERMS text, OWNER text, GRP text, SIZE integer, CHANGE text, ALERTED integer not null default 0 )",
			[],
		);
		let _ = conn.close();
	}
}

fn save_config(watch: &[String], ignore: &[String]) {
	if let Some(parent) = Path::new(&cfg_path()).parent() {
		fs::create_dir_all(parent).ok();
	}
	let conn = match Connection::open(cfg_path()) {
		Ok(c) => c,
		Err(e) => { dbout(1, &format!("Could not open Lumy configuration database: {}", e)); return; }
	};
	let _ = conn.execute("create table if not exists WATCH ( PATH text not null )", []);
	let _ = conn.execute("create table if not exists IGNORE ( PATH text not null )", []);
	for p in watch {
		let _ = conn.execute("insert into WATCH (PATH) values (?)", params![p]);
	}
	for p in ignore {
		let _ = conn.execute("insert into IGNORE (PATH) values (?)", params![p]);
	}
	let _ = conn.close();
}

fn load_config() -> Option<(Vec<String>, Vec<String>)> {
	if fs::metadata(cfg_path()).is_err() { return None; }
	let conn = Connection::open(cfg_path()).ok()?;
	let mut stmt = conn.prepare("select PATH from WATCH").ok()?;
	let watch = stmt.query_map(params![], |row| row.get::<_, String>(0))
		.ok()?
		.filter_map(|r| r.ok())
		.collect();
	// The IGNORE table may not exist in older config databases.
	let ignore = match conn.prepare("select PATH from IGNORE") {
		Ok(mut stmt) => stmt.query_map(params![], |row| row.get::<_, String>(0))
			.ok()
			.map(|rows| rows.filter_map(|r| r.ok()).collect())
			.unwrap_or_default(),
		Err(_) => Vec::new(),
	};
	Some((watch, ignore))
}

/// Request configuration from the server (via the client) and store it.
/// Accepts either a plain array of watch paths or an object with
/// "watch" and "ignore" arrays.
fn request_config(seed: &[u8; 32], clpub: &[u8; 32]) -> Option<(Vec<String>, Vec<String>)> {
	let env = new_envelope("0", "newconfig", "new", None);
	let response = match ipc_exchange(&env, seed, clpub) {
		Ok(r) => r,
		Err(e) => { dbout(1, &format!("Configuration request failed: {}", e)); return None; }
	};
	if response.action != "setconfig" || response.status != "OK" {
		dbout(1, &format!("Configuration request rejected: {} {}", response.status, response.err.unwrap_or_default()));
		return None;
	}
	let data = response.data?;
	let (mut watch, mut ignore) = (Vec::new(), Vec::new());
	match data {
		Value::Array(items) => {
			for item in items {
				if let Some(p) = item.as_str() { watch.push(p.to_string()); }
			}
		}
		Value::Object(map) => {
			if let Some(Value::Array(items)) = map.get("watch") {
				for item in items {
					if let Some(p) = item.as_str() { watch.push(p.to_string()); }
				}
			}
			if let Some(Value::Array(items)) = map.get("ignore") {
				for item in items {
					if let Some(p) = item.as_str() { ignore.push(p.to_string()); }
				}
			}
		}
		_ => { dbout(1, "Unrecognized configuration format from server."); return None; }
	}
	if watch.is_empty() {
		dbout(1, "No watch paths provided by server.");
		return None;
	}
	save_config(&watch, &ignore);
	Some((watch, ignore))
}

// ---------------------------------------------------------------------------
// Event handling
// ---------------------------------------------------------------------------

fn octal_to_symbolic(octal: u32) -> String {
	let mut result = String::new();
	result.push(if octal & 0o400 != 0 { 'r' } else { '-' });
	result.push(if octal & 0o200 != 0 { 'w' } else { '-' });
	result.push(if octal & 0o100 != 0 { 'x' } else { '-' });
	result.push(if octal & 0o040 != 0 { 'r' } else { '-' });
	result.push(if octal & 0o020 != 0 { 'w' } else { '-' });
	result.push(if octal & 0o010 != 0 { 'x' } else { '-' });
	result.push(if octal & 0o004 != 0 { 'r' } else { '-' });
	result.push(if octal & 0o002 != 0 { 'w' } else { '-' });
	result.push(if octal & 0o001 != 0 { 'x' } else { '-' });
	result
}

/// Build a structured record for a debounced filesystem event.
fn event_record(event: &notify::Event) -> Option<Value> {
	let (etype, change) = match &event.kind {
		notify::EventKind::Access(_) => return None, // access events are noise for FIM
		notify::EventKind::Modify(kind) => match kind {
			notify::event::ModifyKind::Data(_) => ("MODIFY", "data"),
			notify::event::ModifyKind::Metadata(_) => ("MODIFY", "metadata"),
			notify::event::ModifyKind::Name(_) => ("RENAME", "name"),
			_ => ("MODIFY", "other"),
		},
		notify::EventKind::Create(_) => ("CREATE", "create"),
		notify::EventKind::Remove(_) => ("REMOVE", "remove"),
		_ => ("OTHER", "unknown"),
	};

	let mut paths: Vec<String> = event.paths.iter().map(|p| p.to_string_lossy().into_owned()).collect();
	if paths.is_empty() { return None; }
	let path = paths.remove(0);

	let mut record = json!({
		"ts": Local::now().timestamp(),
		"type": etype,
		"change": change,
		"path": path,
	});
	if paths.len() == 1 {
		record["dest"] = json!(paths[0]);
	}

	if let Ok(metadata) = fs::metadata(&path) {
		let ftype = if metadata.is_dir() { "Directory" } else if metadata.is_file() { "File" } else { "Other" };
		let mode = metadata.permissions().mode();
		record["ftype"] = json!(ftype);
		record["perms"] = json!(octal_to_symbolic(mode));
		record["mode"] = json!(format!("{:o}", mode));
		record["owner"] = json!(get_user_by_uid(metadata.uid()).map(|u| u.name().to_string_lossy().into_owned()).unwrap_or_else(|| "Unknown".to_string()));
		record["group"] = json!(get_group_by_gid(metadata.gid()).map(|g| g.name().to_string_lossy().into_owned()).unwrap_or_else(|| "Unknown".to_string()));
		record["size"] = json!(metadata.len());
	}
	Some(record)
}

fn is_ignored(path: &str, ignore: &[String]) -> bool {
	ignore.iter().any(|i| path.starts_with(i.as_str()))
}

fn save_event(record: &Value) -> Option<i64> {
	let conn = match Connection::open(imlogs_path()) {
		Ok(c) => c,
		Err(e) => { dbout(1, &format!("Could not open IM log database: {}", e)); return None; }
	};
	let date = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
	let result = conn.execute(
		"insert into EVENTS (DATE, TYPE, PATH, PERMS, OWNER, GRP, SIZE, CHANGE, ALERTED) values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0)",
		params![
			date,
			record["type"].as_str().unwrap_or("UNKNOWN"),
			record["path"].as_str().unwrap_or(""),
			record["perms"].as_str(),
			record["owner"].as_str(),
			record["group"].as_str(),
			record["size"].as_u64().map(|v| v as i64),
			record["change"].as_str()
		],
	);
	let rowid = match result {
		Ok(_) => conn.last_insert_rowid(),
		Err(e) => { dbout(1, &format!("Could not save event to IM log: {}", e)); 0 }
	};
	let _ = conn.close();
	if rowid > 0 { Some(rowid) } else { None }
}

fn send_alert(record: &Value, uid: &str, seed: &[u8; 32], clpub: &[u8; 32]) -> bool {
	let env = new_envelope(uid, "alert", "OK", Some(record.clone()));
	match ipc_exchange(&env, seed, clpub) {
		Ok(response) => {
			if response.status == "OK" {
				dbout(3, &format!("Alert sent for {} {}", record["type"].as_str().unwrap_or("?"), record["path"].as_str().unwrap_or("?")));
				true
			} else {
				dbout(2, &format!("Alert rejected by client: {} {}", response.status, response.err.unwrap_or_default()));
				false
			}
		}
		Err(e) => {
			dbout(2, &format!("Alert transmission failed: {}", e));
			false
		}
	}
}

fn is_inotify_enabled() -> bool {
	fs::metadata("/proc/sys/fs/inotify").is_ok()
}

fn dbout(outlvl: i32, output: &str) {
	let dateformat = StrftimeItems::new("%Y-%m-%d %H:%M:%S");
	let formatted_datetime = Local::now().format_with_items(dateformat).to_string();
	let etype = if outlvl == 1 { "FAIL" } else if outlvl == 2 { "WARN" } else if outlvl == 3 { " OK " } else { "INFO" };
	println!("{} [{}] {}", formatted_datetime, etype, output);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() {
	dbout(0, &format!("Starting Luminum Integrity Lumy v{} (Linux)", VER));

	if !is_inotify_enabled() {
		dbout(1, "inotify is not available on this system. Integrity monitoring cannot start.");
		std::process::exit(1);
	}

	ensure_imdb();

	// The Lumy signs every envelope with the client's key (§8.2);
	// without the keypair there is nothing it can do.
	let (seed, clpub) = match client_keypair() {
		Some(kp) => kp,
		None => {
			dbout(1, "Unable to load client signing keypair (CLPPRV/CLPPUB) from client configuration. Exiting.");
			std::process::exit(1);
		}
	};

	// Obtain configuration: local store if present, otherwise request
	// from the server via the client.
	let (watchpaths, ignorepaths) = match load_config() {
		Some(cfg) => {
			dbout(3, "Loaded local Integrity configuration.");
			cfg
		}
		None => {
			dbout(4, "No local configuration. Requesting configuration from server...");
			match request_config(&seed, &clpub) {
				Some(cfg) => cfg,
				None => {
					dbout(1, "Unable to obtain Integrity configuration. Exiting.");
					std::process::exit(1);
				}
			}
		}
	};
	let uid = client_uid();
	dbout(4, &format!("Watching {} path(s); {} ignore rule(s).", watchpaths.len(), ignorepaths.len()));

	// Event channel from the debouncer thread to the main loop.
	let (tx, rx) = mpsc::channel::<Value>();

	let mut debouncer = new_debouncer(Duration::from_secs(DEBOUNCE_SECS), None, move |result: DebounceEventResult| {
		match result {
			Ok(events) => {
				for debounced in events {
					if let Some(record) = event_record(&debounced.event) {
						let _ = tx.send(record);
					}
				}
			}
			Err(errors) => {
				for e in errors {
					dbout(1, &format!("Watch error: {:?}", e));
				}
			}
		}
	}).expect("Error: Could not set up debouncer.");

	for watchpath in &watchpaths {
		match debouncer.watcher().watch(Path::new(watchpath), RecursiveMode::Recursive) {
			Ok(_) => dbout(3, &format!("Watching: {}", watchpath)),
			Err(e) => dbout(1, &format!("Unable to watch {}: {}", watchpath, e)),
		}
	}

	// Main loop: drain the event channel, log locally, alert the client.
	loop {
		match rx.recv_timeout(Duration::from_secs(1)) {
			Ok(record) => {
				let path = record["path"].as_str().unwrap_or("").to_string();
				if is_ignored(&path, &ignorepaths) {
					dbout(4, &format!("Ignoring event in excluded path: {}", path));
					continue;
				}
				let rowid = save_event(&record);
				let alerted = send_alert(&record, &uid, &seed, &clpub);
				if alerted {
					mark_alerted(rowid);
				}
			}
			Err(mpsc::RecvTimeoutError::Timeout) => continue,
			Err(mpsc::RecvTimeoutError::Disconnected) => {
				dbout(1, "Event channel disconnected. Exiting.");
				break;
			}
		}
	}
}

/// Mark a local log row as alerted once its alert has been
/// transmitted.
fn mark_alerted(rowid: Option<i64>) {
	let Some(rowid) = rowid else { return };
	let conn = match Connection::open(imlogs_path()) {
		Ok(c) => c,
		Err(_) => return,
	};
	let _ = conn.execute("update EVENTS set ALERTED = 1 where ID = ?1", params![rowid]);
	let _ = conn.close();
}
