// Luminum Client for Linux
// by Christopher R. Curzio <ccurzio@luminum.net>

use clap::{Arg, App};
use colored::Colorize;
use chrono::Local;
use chrono::format::strftime::StrftimeItems;
use std::sync::atomic::{AtomicBool, Ordering};
use std::process;
use std::thread;
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
	let endpointname = gethostname().to_string_lossy().into_owned();
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

	let mut clientconfig: HashMap<String, String> = HashMap::new();

	if setup {
		dbout(debug,4,format!("Starting client setup...").as_str());
		if fs::metadata(CFGPATH).is_err() { clientsetup(); }
		else {
			dbout(debug,1,format!("Client configuration already exists. Aborting.").as_str());
			process::exit(1);
			}
		}

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

	fn write_to_server(stream: Arc<Mutex<TlsStream<TcpStream>>>, data: &[u8]) {
		let mut stream = stream.lock().unwrap();
		stream.write_all(data).expect("Failed to write to server");
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
	//let server_addr: SocketAddr = server_addr_str.to_socket_addrs().expect("Invalid server address");
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
			dbout(debug,3,format!("Connected to Luminum server {}",server_addr_str).as_str());
			sconn
			},
		Err(err) => {
			dbout(debug,1,format!("Connection to Luminum server failed: {}", err).as_str());
			process::exit(1);
			}
		};

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

	// Get client status from server
	let mut uid = String::new();
	if clientconfig.get("UID").is_none() {
		dbout(debug,4,format!("Endpoint is not registered with the Luminum server. Sending registration request...").as_str());
		let mut combined_json = json!({});
		combined_json["product"] = serde_json::to_value("Luminum Client").unwrap();
		combined_json["version"] = serde_json::to_value(VER).unwrap();
		combined_json["content"]["action"] = serde_json::to_value("register").unwrap();
		combined_json["content"]["hostname"] = serde_json::to_value(endpointname.clone()).unwrap();
		let ejson = json!({"dtype":"inotify"});
		let event_info: Value = serde_json::to_value(ejson).unwrap();
		let json_event = serde_json::to_string(&combined_json).unwrap();
		write_to_server(server_stream.clone(), json_event.as_bytes());
		}
	else {
		dbout(debug,3,format!("Endpoint is registered with UID {}.", uid).as_str());
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
			dbout(debug,1,format!("Failed to configure local IPC: {}", err).as_str());
			process::exit(1);
			}
		};

	let ipcstream = Arc::new(Mutex::new(None));

	for incoming in ipclistener.incoming() {
		match incoming {
			Ok(mut stream) => {
				let shared_stream = Arc::clone(&ipcstream);
				thread::spawn(move || {
					let mut buffer = [0; 1024];
					let bytes_read = stream.read(&mut buffer).expect("Error: Failure reading input stream");
					let data_raw = String::from_utf8_lossy(&buffer[..bytes_read]);
					handle_json(data_raw.as_ref(),debug);
					let mut shared_stream = shared_stream.lock().unwrap();
					*shared_stream = Some(stream);
					});
				},
			Err(e) => {
				eprintln!("Error: {}", e);
				}
			}
		}
	println!("FOO");
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

fn handle_json(data: &str, debug: bool) {
	match serde_json::from_str::<Value>(data) {
		Ok(v) => {
			if let content = v["content"].to_string() { println!("{}", content); }
			}
		Err(e) => {
			dbout(debug,2,format!("Malformed data received on local listener").as_str());
			}
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
		println!("{} [{}] {}",formatted_datetime,etype,output);
		}
	else {
		if outlvl == 1 { println!("{}",output); }
		}
	}
