// Luminum Client for Linux
// by Christopher R. Curzio <ccurzio@luminum.net>

use clap::{Arg, App};
use colored::Colorize;
use chrono::Local;
use chrono::format::strftime::StrftimeItems;
use std::sync::atomic::{AtomicBool, Ordering};
use std::process;
use std::process::Command;
use std::thread;
use regex::Regex;
use etc_os_release::OsRelease;
use gethostname::gethostname;
use std::net::{TcpListener, SocketAddr, ToSocketAddrs, TcpStream};
use native_tls::{TlsConnector, TlsStream};
use rusqlite::{params, Connection, Result};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::fs::{self, File};
use std::io::{self, Read, Write};
use serde_json::{json, to_value, Value};

const VER: &str = "0.0.1";
const CFGPATH: &str = "/opt/Luminum/LuminumClient/conf/luminum.conf.db";
const DPORT: u16 = 10465;
const LPORT: u16 = 10461;

struct Config {
	key: String,
	value: String
	}

fn main() {
	let matches = App::new("Luminum Client (Linux)")
		.version(VER)
		.author("Christopher R. Curzio <ccurzio@luminum.net>")
	 .arg(Arg::with_name("setup")
		.short('s')
		.long("setup")
		.value_name("setup")
		.help("Set client configuration parameters")
		.takes_value(false))
	 .arg(Arg::with_name("debug")
		.short('d')
		.long("debug")
		.value_name("debug")
		.help("Enables debug mode")
		.takes_value(false))
	.get_matches();

	let setup = matches.is_present("setup");
	let debug = matches.is_present("debug");

	if setup {
		dbout(debug,4,format!("Starting client setup...").as_str());
		if fs::metadata(CFGPATH).is_err() { clientsetup(); }
		else {
			dbout(debug,1,format!("Client configuration already exists. Aborting.").as_str());
			process::exit(1);
			}
		}

	let mut clientconfig: HashMap<String, String> = HashMap::new();
	let endpointname = gethostname().to_string_lossy().into_owned();

        // Set up break handler
	let running = Arc::new(AtomicBool::new(true));
	let r = running.clone();
	ctrlc::set_handler(move || {
		r.store(false, Ordering::SeqCst);
		println!();
		dbout(debug,0,"BREAK");
		dbout(debug,0,format!("Terminating Luminum Client.").as_str());
		process::exit(1);
		}).expect("Error creating break handler");

	// Client Startup
	dbout(debug,0,format!("Starting Luminum Client v{}...", VER).as_str());

	fn write_to_server(stream: Arc<Mutex<TlsStream<TcpStream>>>, data: &[u8], debug: bool) {
		let mut stream = stream.lock().unwrap();
		match stream.write_all(data) {
			Ok(_) => {
				dbout(debug,3,format!("Data message successfully sent to server.").as_str());
				}
			Err(err) => {
				dbout(debug,2,format!("Failed to send data package: {}", err).as_str());
				}
			}

		let mut buffer = [0; 1024];
		let bytes_read = stream.read(&mut buffer).expect("Error: Failure reading input stream");
		let data_raw = String::from_utf8_lossy(&buffer[..bytes_read]);

		match serde_json::from_str::<Value>(data_raw.as_ref()) {
			Ok(rcvd_data) => {
				if rcvd_data["product"] == "Luminum Server" {
					if rcvd_data["content"]["action"] == "register" {
						dbout(debug,4,format!("Received registration response from server.").as_str());
						let new_uid = rcvd_data["content"]["uid"].as_str().unwrap_or("");
						let uuid_pattern = Regex::new(r"^[0-9a-fA-F\-]+$").unwrap();
						if uuid_pattern.is_match(new_uid) {
							let confconn = Connection::open(CFGPATH).expect("Error: Could not open client configuration database.");
							match confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"UID",new_uid]) {
								Ok(_) => {
									dbout(debug,3,format!("UID saved to client configuration.").as_str());
									dbout(debug,3,format!("Registration complete.").as_str());
									}
								Err(err) => {
									dbout(debug,1,format!("Unable to save UID value to configuration database: {}", err).as_str());
									process::exit(1);
									}
								}
							confconn.close().unwrap();
							}
						}
					else if rcvd_data["content"]["action"] == "verify" {
						let vstat = rcvd_data["content"]["status"].as_str().unwrap_or("");
						let uid = rcvd_data["content"]["uid"].as_str().unwrap_or("");
						if vstat == "OK" {
							dbout(debug,3,format!("Verified server association with UID.").as_str());
							}
						else if vstat == "NOREG" {
							dbout(debug,2,format!("Registration mismatch detected. Revoking UID {}",uid).as_str());
							let confconn = Connection::open(CFGPATH).expect("Error: Could not initialize configuration database");
							let mut stmt = confconn.execute("delete from CONFIG where KEY = 'UID'",[]).expect("Error with configuration delete query");
							confconn.close().unwrap();
							dbout(debug,1,format!("UID has been revoked. Please restart the service to re-register with the server.").as_str());
							process::exit(1);
							}
						}
					}
				}
			Err(err) => {
				dbout(debug,2,format!("Malformed data in stream from server: {}", err).as_str());
				}
			}
		}

	fn verify_ask(stream: Arc<Mutex<TlsStream<TcpStream>>>, uid: String, debug: bool) {
		let mut combined_json = json!({});
		combined_json["product"] = serde_json::to_value("Luminum Client").unwrap();
		combined_json["version"] = serde_json::to_value(VER).unwrap();
		combined_json["content"]["action"] = serde_json::to_value("verify").unwrap();
		combined_json["content"]["uid"] = serde_json::to_value(uid).unwrap();
		let json_event = serde_json::to_string(&combined_json).unwrap();
		write_to_server(stream, json_event.as_bytes(),debug);
		}

	if fs::metadata(CFGPATH).is_ok() {
		let confconn = Connection::open(CFGPATH).expect("Error: Could not open configuration database.");
		let mut stmt = confconn.prepare("select KEY,VALUE from CONFIG").unwrap();
		let cfg_iter = stmt.query_map(params![], |row| {
			Ok(Config {
				key: row.get(0)?,
				value: row.get(1)?
				})
			}).expect("Error: Failed to parse configuration values");
		for cfg_result in cfg_iter {
			if let Ok(cfg) = cfg_result {
				clientconfig.insert(cfg.key.to_string(),cfg.value.to_string());
				}
			}
		}
	else {
		dbout(debug,1,format!("Configuration database not found.").as_str());
		process::exit(1);
		}

	// Conncet to Luminum Server
	let server_host = clientconfig.get("SHOST").unwrap();
	let server_port = clientconfig.get("SPORT").unwrap();
	let server_addr_str = format!("{}:{}", server_host, server_port);
	let server_addr: SocketAddr = match server_addr_str.to_socket_addrs() {
		Ok(mut addrs) => {
			if let Some(addr) = addrs.next() { addr }
			else {
				eprintln!("No addresses found for hostname");
				return;
				}
			},
		Err(e) => {
			eprintln!("Failed to resolve hostname: {}", e);
			return;
			}
		};

	let server_cert_path = "/opt/Luminum/LuminumServer/config/luminum.crt";
	let mut server_cert = File::open(server_cert_path).expect("Failed to open certificate file");
	let mut cert_buffer = Vec::new();
	server_cert.read_to_end(&mut cert_buffer).expect("Failed to read certificate file");

	let sconn = match TcpStream::connect(server_addr) {
		Ok(sconn) => {
			dbout(debug,3,format!("Connected to Luminum server at {}",server_addr_str).as_str());
			sconn
			},
		Err(err) => {
			dbout(debug,1,format!("Connection to Luminum server failed: {}", err).as_str());
			process::exit(1);
			}
		};

	let sconn_clone = sconn.try_clone().expect("Failed to clone TcpStream");
	let mut builder = native_tls::TlsConnector::builder();
	builder.add_root_certificate(native_tls::Certificate::from_pem(&cert_buffer).expect("Failed to parse certificate"));
	let connector = builder.build().expect("Failed to create TLS connector");

	let mut server_stream;

	match connector.connect(server_host, sconn) {
		Ok(stream) => { server_stream = stream; },
		Err(err) => {
			dbout(debug,1,format!("TLS handshake failed: {}", err).as_str());
			process::exit(1);
			}
		};

	let server_stream = Arc::new(Mutex::new(server_stream));

	let local_addr: SocketAddr = sconn_clone.local_addr().expect("Error: Unable to determine local socket address");
	let ip_address = local_addr.ip().to_string();

	let ipv4_regex = Regex::new(r"^(\d{1,3}\.){3}\d{1,3}$").unwrap();
	let ipv6_regex = Regex::new(r"^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$").unwrap();
	let mut ip_type = String::new();

	if ipv4_regex.is_match(&ip_address) { ip_type = "IPV4".to_string(); }
	else if ipv6_regex.is_match(&ip_address) { ip_type = "IPV6".to_string(); }

	let mut ipv4_address = String::new();
	let mut ipv6_address = String::new();

	if ip_type == "IPV4" {
		ipv4_address = ip_address.to_string();
		ipv6_address = " ".to_string();
		}
	else if ip_type == "IPV6" {
		ipv6_address = ip_address.to_string();
		ipv4_address = " ".to_string();
		}

	// Get client status from server and register if needed
	let mut uid = String::new();

	if clientconfig.get("UID").is_none() {
		dbout(debug,4,format!("Endpoint is not registered with the Luminum server. Sending registration request...").as_str());
		let os_release = get_os_release();
		let mut combined_json = json!({});
		combined_json["product"] = serde_json::to_value("Luminum Client").unwrap();
		combined_json["version"] = serde_json::to_value(VER).unwrap();
		combined_json["content"]["action"] = serde_json::to_value("register").unwrap();
		combined_json["content"]["hostname"] = serde_json::to_value(endpointname.clone()).unwrap();
		combined_json["content"]["ipv4"] = serde_json::to_value(ipv4_address).unwrap();
		combined_json["content"]["ipv6"] = serde_json::to_value(ipv6_address).unwrap();
		combined_json["content"]["osplat"] = serde_json::to_value("Linux").unwrap();
		combined_json["content"]["osver"] = serde_json::to_value(os_release).unwrap();
		let json_event = serde_json::to_string(&combined_json).unwrap();
		write_to_server(server_stream.clone(), json_event.as_bytes(),debug);
		}
	else {
		uid = clientconfig.get("UID").expect("Error: could not set UID from client configuration.").to_string();
		dbout(debug,3,format!("Endpoint UID: {}", uid.to_string()).as_str());
		verify_ask(server_stream.clone(),uid,debug);
		}

	// Set up local IPC listener
	let addr_str = format!("127.0.0.1:{}", LPORT);
	let addr: SocketAddr = addr_str.parse().expect("Invalid socket address");

	let ipclistener = match TcpListener::bind(addr) {
		Ok(ipclistener) => { 
			dbout(debug,3,format!("Local IPC listening on port {}", LPORT).as_str());
			ipclistener
			},
		Err(err) => {
			dbout(debug,1,format!("Failed to initialize local IPC listener: {}", err).as_str());
			process::exit(1);
			}
		};

	let ipcstream = Arc::new(Mutex::new(None));

	for incoming in ipclistener.incoming() {
		let cloned_server_stream = server_stream.clone();
		match incoming {
			Ok(mut stream) => {
				let shared_stream = Arc::clone(&ipcstream);
				thread::spawn(move || {
					let mut buffer = [0; 1024];
					let bytes_read = stream.read(&mut buffer).expect("Error: Failure reading input stream");
					let data_raw = String::from_utf8_lossy(&buffer[..bytes_read]);
					handle_json(cloned_server_stream,data_raw.as_ref(),debug);
					let mut shared_stream = shared_stream.lock().unwrap();
					*shared_stream = Some(stream);
					});
				},
			Err(e) => {
				dbout(debug,2,format!("Malformed data received on local listener: {}", e).as_str());
				}
			}
		}
	}

fn clientsetup() {
	println!("Luminum Client (Linux)\nby Christopher R. Curzio <ccurzio@luminum.net>\n");
	println!("Client Configuration\n--------------------");

	let mut server = String::new();
	let mut ui_server = String::new();
	let mut port: u16 = 10465;

	print!("Enter Luminum server hostname or IP address: ");
	io::stdout().flush().unwrap();
	io::stdin()
		.read_line(&mut ui_server)
		.expect("Error reading user input");
	let ui_server = ui_server.trim();
	server = ui_server.to_string();

	loop {
		let mut ui_port = String::new();
		print!("Enter server port [{}]: ", DPORT);
		io::stdout().flush().unwrap();

		io::stdin().read_line(&mut ui_port).unwrap();
		let ui_port = ui_port.trim();
		let num = if ui_port.is_empty() { DPORT }
		else {
			match ui_port.parse::<u16>() {
				Ok(num) if num >= 1 => num,
				_ => {
					println!("Invalid port: {}\n", ui_port);
					continue;
					}
				}
			};
		port = num;
		break;
		}

	let confconn = Connection::open(CFGPATH).expect("Error: Could not initialize configuration database");
	confconn.execute("create table if not exists CONFIG ( KEY text not null, VALUE text not null )",[]).expect("Error: Could not create CONFIG table in configuration database");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"SHOST",server.as_str()]).expect("Error: Could not insert SHOST into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"SPORT",port.to_string().as_str()]).expect("Error: Could not insert SPORT into CONFIG table.");
	confconn.close().unwrap();

	println!("Server host: {}",server);
	println!("Server port: {}",port);

	process::exit(0);
	}

fn handle_json(stream: Arc<Mutex<TlsStream<TcpStream>>>, data: &str, debug: bool) {
	let mut lumy = String::new();
	match serde_json::from_str::<Value>(data) {
		Ok(rcvd_data) => {
			for line in data.lines() {
				let parsed_value: Value = serde_json::from_str(line).expect("Error: could not parse JSON");
				if let Some(product) = parsed_value.get("product") {
					if product == "Luminum Integrity" {
						lumy = "Integrity".to_string();
						if let Some(content) = parsed_value.get("content") {
							if let Some(event) = content.get("notify_event") {
								if let Some(kind_value) = event.get("kind") {
									if let Some(kind_str) = kind_value.as_str() {
										}
									}
								if let Some(path_value) = event.get("paths") {
									}
								}
							}
						}
					}
				}
//{"content":{"event_info":{"dtype":"inotify"},"notify_event":{"kind":"Create(File)","paths":["/usr/foo"]}},"product":"Luminum Integrity"}
//{"content":{"event_info":{"dtype":"inotify"},"notify_event":{"kind":"Modify(Metadata(Any))","paths":["/usr/foo"]}},"product":"Luminum Integrity"}
//{"content":{"event_info":{"dtype":"inotify"},"notify_event":{"kind":"Access(Close(Write))","paths":["/usr/foo"]}},"product":"Luminum Integrity"}
//{"content":{"event_info":{"dtype":"inotify"},"notify_event":{"kind":"Remove(File)","paths":["/usr/foo"]}},"product":"Luminum Integrity"}
			}
		Err(err) => {
			dbout(debug,2,format!("Malformed data received on local listener").as_str());
			}
		}
	}

fn get_os_release() -> String {
	let mut os_release = String::new();
	match OsRelease::open() {
		Ok(result) => { os_release = result.pretty_name().to_string(); }
		Err(_) => { os_release = "Unknown".to_string(); }
		}
	return os_release;
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
		println!("{} [{}] {}",formatted_datetime,etype,output);
		}
	else {
		if outlvl == 1 { println!("{}",output); }
		}
	}
