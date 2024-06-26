// Luminum Client for Linux
// by Christopher R. Curzio <ccurzio@luminum.net>

use clap::{Arg, App};
use colored::Colorize;
use chrono::Local;
use chrono::format::strftime::StrftimeItems;
use std::sync::atomic::{AtomicBool, Ordering};
use std::process;
use std::process::{Command, Stdio, Child};
use std::thread;
use tokio::task::spawn;
use tokio::time;
use gethostname::gethostname;
use etc_os_release::OsRelease;
use local_ip_address::local_ip;
use std::net::{TcpListener, SocketAddr, ToSocketAddrs, TcpStream};
use native_tls::{TlsConnector, TlsStream};
use std::str;
use std::error::Error;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::fs::{self, File};
use std::io::{self, Read, Write, BufWriter, BufReader, BufRead};
use std::time::Duration;
use regex::Regex;
use rusqlite::{params, Connection, Result};
use serde::{Serialize, Deserialize};
use rmp_serde::{from_read, Deserializer, Serializer, to_vec_named};
use rmp_serde::decode::from_slice;

const VER: &str = "0.0.1";
const CFGPATH: &str = "/opt/Luminum/LuminumClient/config/client.conf.db";
const CRTPATH: &str = "/opt/Luminum/LuminumClient/config/server.crt";
const MODPATH: &str = "/opt/Luminum/LuminumClient/modules";
const IPORT: u16 = 10704;
const DPORT: u16 = 10465;
const LPORT: u16 = 10461;

struct Config {
	key: String,
	value: String
	}

#[derive(Serialize, Deserialize, Debug)]
struct ServerMessage {
	version: String,
	content: MessageContent
	}

#[derive(Serialize, Deserialize, Debug)]
struct ClientMessage {
	uid: String,
	product: String,
	version: String,
	content: MessageContent
	}

#[derive(Serialize, Deserialize, Debug)]
struct MessageContent {
	lumy: String,
	status: String,
	action: String,
	data: Option<MessageData>
	}

#[derive(Serialize, Deserialize, Debug)]
struct MessageData {
	serverkey: Option<String>,
	hostname: Option<String>,
	uid: Option<String>,
	osplat: Option<String>,
	osver: Option<String>,
	ipv4: Option<String>,
	ipv6: Option<String>,
	info: Option<Vec<String>>
	}

#[derive(Serialize, Deserialize, Debug)]
struct LumyMessage {
	lumy: String,
	version: String,
	content: LumyContent
	}

#[derive(Serialize, Deserialize, Debug)]
struct LumyContent {
	action: String,
	data: Option<Vec<String>>
	}

#[tokio::main]
async fn main() {
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
	let mut lumys: HashMap<String, String> = HashMap::new();

        // Set up break handler
	let running = Arc::new(AtomicBool::new(true));
	let r = running.clone();
	ctrlc::set_handler(move || {
		r.store(false, Ordering::SeqCst);
		print!("\r\x1B[K");
		io::stdout().flush().unwrap_or(());
		dbout(debug,0,"Received BREAK signal.");
		dbout(debug,0,"Luminum Client Terminated.");
		process::exit(1);
		}).expect("Error creating break handler");

	// Check if setup routine needs to run
	if setup {
		dbout(debug,4,format!("Starting client setup...").as_str());
		if fs::metadata(CFGPATH).is_err() { clientsetup(); }
		else {
			dbout(debug,1,format!("Client configuration already exists. Aborting.").as_str());
			process::exit(1);
			}
		}

	// Client Startup
	dbout(debug,0,format!("Starting Luminum Client v{}...", VER).as_str());

	// Get machine IP address information
	let ip_address = local_ip().unwrap().to_string();
	let ipv4_regex = Regex::new(r"^(\d{1,3}\.){3}\d{1,3}$").unwrap();
	let ipv6_regex = Regex::new(r"^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$").unwrap();
	let mut ipv4_address = String::new();
	let mut ipv6_address = String::new();
	if ipv4_regex.is_match(&ip_address) { ipv4_address = ip_address.clone(); }
	if ipv6_regex.is_match(&ip_address) { ipv6_address = ip_address.clone(); }

	dbout(debug,4,format!("Endpoint IP address: {}", ip_address).as_str());

	dbout(debug,3,format!("Using configuration: {}",CFGPATH).as_str());
	let clientconfig = parse_clientconfig(debug);
	let clientconfig_clone = clientconfig.clone();

	// Set up local IPC listener
	let addr_str = format!("127.0.0.1:{}", LPORT);
	let addr: SocketAddr = addr_str.parse().expect("Invalid socket address for IPC");

	let ipclistener = match TcpListener::bind(addr) {
		Ok(ipclistener) => { 
			dbout(debug,3,format!("Local IPC configured on port {}", LPORT).as_str());
			ipclistener
			},
		Err(err) => {
			dbout(debug,1,format!("Unable to configure local IPC: {}", err).as_str());
			process::exit(1);
			}
		};

	// Set up local data connection
	let sladdr_str = format!("{}:{}",ip_address,IPORT);
	let sladdr: SocketAddr = sladdr_str.parse().expect("Invalid socket address for server data connection");

	let serverlistener = match TcpListener::bind(sladdr) {
		Ok(serverlistener) => {
			dbout(debug,3,format!("Incoming data connection configured on port {}", IPORT).as_str());
			serverlistener
			},
		Err(err) => {
			dbout(debug,1,format!("Unable to configure incoming data connection: {}", err).as_str());
			process::exit(1);
			}
		};

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
			eprintln!("Unable to resolve hostname: {}", e);
			return;
			}
		};

	// Check client registration status and register with server if necessary
	let mut uid = String::new();
	if clientconfig.get("UID").is_none() {
		dbout(debug,4,format!("Endpoint is not registered with the Luminum server. Sending registration request...").as_str());
		let msgdata = MessageData {
			hostname: Some(String::from(endpointname.clone())),
			serverkey: Some(String::from(clientconfig.get("SVRKEY").unwrap())),
			uid: Some(String::from("NONE")),
			osplat: Some(String::from("Linux")),
			osver: Some(String::from(get_os_release())),
			ipv4: Some(String::from(ip_address)),
			ipv6: None,
			info: None
			};
		let msgcontent = MessageContent {
			lumy: String::from("Client Core"),
			status: String::from("noreg"),
			action: String::from("register"),
			data: Some(msgdata)
			};
			let clientmsg = ClientMessage {
			product: String::from("Luminum Client"),
			version: String::from(VER),
			uid: String::from("NONE"),
			content: msgcontent
			};
		let servermsg: Option<ServerMessage> = match server_send(server_host, server_port, CRTPATH, clientmsg, debug) {
			Ok(response) => { Some(response) },
			Err(err) => {
				dbout(debug,2,format!("Unable to send message to server: {}", err).as_str());
				None
				}
			};

		let response = servermsg.unwrap();
		if response.content.action == "register" {
			if response.content.status == "OK" {
				let response_data: MessageData = response.content.data.expect("Error: Unable to parse response data");
				let new_uid = response_data.uid.expect("Error: Unable to parse UID in response data");
				let confconn = Connection::open(CFGPATH).expect("Error: Could not open configuration database.");
				confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"UID",new_uid.to_string().as_str()]).expect("Error: Could not insert UID into CONFIG table.");
				confconn.close().unwrap();
				dbout(debug,3,format!("Registration successful. (UID: {})", new_uid).as_str());
				let dbg = debug;
				tokio::spawn(async move {
					let mut interval = time::interval(Duration::from_secs(300));
					loop {
						interval.tick().await;
						heartbeat(dbg).await;
						}
					});
				}
			}		
		}
	else {
		let uid = clientconfig.get("UID").unwrap();
		dbout(debug,3,format!("Endpoint is registered with UID {}", uid).as_str());
		let dbg = debug;
		tokio::spawn(async move {
			let mut interval = time::interval(Duration::from_secs(300));
			loop {
				interval.tick().await;
				heartbeat(dbg).await;
				}
			});
		}

	// Review installed Lumys
	if file_exists(MODPATH) {
		let mut integrity_path = String::from(MODPATH);
		integrity_path.push_str("/integrity/Lumy_Integrity");

		if file_exists(&integrity_path) {
			dbout(debug,4,format!("Found Lumy: Integrity").as_str());
			lumys.insert(String::from("Integrity"),String::from(integrity_path));
			}
		}

	for (lumy, lpath) in &lumys {
		start_lumy(&lumy, &lpath, debug);
		if lumys.len() > 1 { thread::sleep(Duration::from_secs(2)); }
		}

	// Start IPC listener
	let dbc = debug.clone();
	for stream in ipclistener.incoming() {
		match stream {
			Ok(stream) => {
				thread::spawn(move || {
					if let Err(err) = handle_ipc(stream,dbc) {
						dbout(debug,2,format!("Error in IPC stream data: {}", err).as_str());
						}
					});
				}
			Err(err) => {
				dbout(debug,2,format!("Error establishing IPC connection: {}", err).as_str());
				}
			}
		}




/*
		let msgdata = MessageData {
			hostname: Some(String::from(endpointname.clone())),
			serverkey: Some(String::from(clientconfig.get("SVRKEY").unwrap())),
			uid: Some(String::from("NONW")),
			osplat: Some(String::from("Linux")),
			osver: Some(String::from(get_os_release())),
			ipv4: Some(String::from(ipv4_address.clone())),
			ipv6: Some(String::from(ipv6_address.clone()))
			};
		let msgcontent = MessageContent {
			module: String::from("Client Core"),
			status: String::from("noreg"),
			action: String::from("register"),
			data: Some(msgdata)
			};
		let clientmsg = ClientMessage {
			product: String::from("Luminum Client"),
			version: String::from(VER),
			uid: String::from("NONE"),
			content: msgcontent
			};
		let servermsg: Option<ServerMessage> = match server_send(server_host, server_port, server_cert_path, clientmsg, debug) {
			Ok(response) => { Some(response) },
			Err(err) => {
				dbout(debug,2,format!("Failed to send message to server: {}", err).as_str());
				None
				}
			};

	let ipcstream = Arc::new(Mutex::new(None));

	for incoming in ipclistener.incoming() {
		match incoming {
			Ok(mut stream) => {
				let shared_stream = Arc::clone(&ipcstream);
				let ccfg = clientconfig_clone.clone();
				thread::spawn(move || {
					let mut shared_stream = shared_stream.lock().unwrap();
					*shared_stream = Some(stream);
					});
				},
			Err(e) => {
				eprintln!("Error: {}", e);
				}
			}
		}
*/
	}

async fn heartbeat(debug: bool) {
	let ccfg = parse_clientconfig(debug);
	let uid = ccfg.get("UID").unwrap();
	let endpointname = gethostname().to_string_lossy().into_owned();
	let server_host = ccfg.get("SHOST").unwrap();
	let server_port = ccfg.get("SPORT").unwrap();

	let msgdata = MessageData {
		hostname: None,
		serverkey: None,
		uid: None,
		osplat: None,
		osver: None,
		ipv4: None,
		ipv6: None,
		info: None
		};
	let msgcontent = MessageContent {
		lumy: String::from("Client Core"),
		status: String::from("online"),
		action: String::from("heartbeat"),
		data: Some(msgdata)
		};
	let clientmsg = ClientMessage {
		product: String::from("Luminum Client"),
		version: String::from(VER),
		uid: String::from(uid),
		content: msgcontent
		};

	dbout(debug,4,format!("Sending heartbeat to Luminum server").as_str());
	let _ = server_send(server_host, server_port, CRTPATH, clientmsg, debug);
	thread::sleep(Duration::from_secs(5));
	}


fn parse_clientconfig(debug: bool) -> HashMap<String, String> {
	let mut clientconfig: HashMap<String, String> = HashMap::new();

	if fs::metadata(CFGPATH).is_ok() {
		let confconn = match Connection::open(CFGPATH) {
			Ok(confconn) => { confconn }
			Err(err) => {
				dbout(debug,1,format!("Could not open client configuration database: {}",err).as_str());
				process::exit(1);
				}
			};
		let mut stmt = confconn.prepare("select KEY,VALUE from CONFIG").unwrap();
		let cfg_iter = stmt.query_map(params![], |row| {
			Ok(Config {
				key: row.get(0)?,
				value: row.get(1)?
				})
			}).expect("Error: Unable to parse configuration values");
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
	return clientconfig
	}

fn handle_ipc(stream: TcpStream, debug: bool) -> Result<(), Box<dyn std::error::Error>> {
	let mut reader = BufReader::new(&stream);
	let mut writer = BufWriter::new(&stream);

	let ccfg = parse_clientconfig(debug);
	let uid = ccfg.get("UID").unwrap();
	let endpointname = gethostname().to_string_lossy().into_owned();
	let server_host = ccfg.get("SHOST").unwrap();
	let server_port = ccfg.get("SPORT").unwrap();

	let mut buffer = [0; 1024];
	let bytes_read = reader.read(&mut buffer)?;
	let mut deserializer = Deserializer::new(&buffer[..]);
	let lumymsg: LumyMessage = Deserialize::deserialize(&mut deserializer)?;

	if lumymsg.lumy == "Integrity" {
		if lumymsg.content.action == "newconfig" {
			dbout(debug,4,format!("Received new configuration request from Integrity Lumy").as_str());
			let msgdata = MessageData {
				hostname: Some(String::from(endpointname)),
				serverkey: None,
				uid: Some(String::from(uid)),
				osplat: Some(String::from("Linux")),
				osver: None,
				ipv4: None,
				ipv6: None,
				info: None
				};
			let msgcontent = MessageContent {
				lumy: String::from("Integrity"),
				status: String::from("new"),
				action: String::from("newconfig"),
				data: Some(msgdata)
				};
			let clientmsg = ClientMessage {
				product: String::from("Luminum Client"),
				version: String::from(VER),
				uid: String::from(uid),
				content: msgcontent
				};
			let servermsg: Option<ServerMessage> = match server_send(server_host, server_port, CRTPATH, clientmsg, debug) {
				Ok(response) => {
					dbout(debug,4,format!("Sent Integrity configuration request to Luminum server").as_str());
					Some(response)
					},
				Err(err) => {
					dbout(debug,2,format!("Failed to send Integrity configuration request to server: {}", err).as_str());
					None
					}
				};

			if let serverdata = servermsg.unwrap().content.data.unwrap().info {
				let tolumycontent = LumyContent {
					action: String::from("setconfig"),
					data: serverdata
					};
				let tolumymsg = LumyMessage {
					lumy: String::from("Luminum Client"),
					version: String::from(VER),
					content: tolumycontent
					};
				let serialized_data = to_vec_named(&tolumymsg).expect("Error: Unable to serialize IPC response");
				writer.write_all(&serialized_data).expect("Error: Unable to send message to Luminum Client process");
				dbout(debug,3,format!("New configuration sent to Integrity Lumy").as_str());
				}
			}
		}
	Ok(())
	}

fn server_send(server_host: &str, server_port: &str, cert_path: &str, message: ClientMessage, debug: bool) -> Result<ServerMessage, Box<dyn Error>> {
	let server_addr_str = format!("{}:{}", server_host, server_port); 
	let server_addr = server_addr_str.to_socket_addrs()?.next().ok_or("No addresses found for hostname")?; 
	let mut server_cert = File::open(cert_path)?;
	let mut cert_buffer = Vec::new();
	server_cert.read_to_end(&mut cert_buffer)?;

	let sconn = loop {
		match TcpStream::connect(server_addr) {
			Ok(sconn) => break sconn,
			Err(err) => {
				dbout(debug,2,format!("Connection to Luminum server failed: {}", err).as_str());
				dbout(debug,4,format!("Retrying connection in 30 seconds...",).as_str());
				thread::sleep(Duration::from_secs(30));
				}
			}
		};

	let mut builder = TlsConnector::builder();
	builder.add_root_certificate(native_tls::Certificate::from_pem(&cert_buffer)?);
	let connector = builder.build()?;
	let mut server_stream = connector.connect(server_host, sconn)?;

	let mut stream = Arc::new(Mutex::new(server_stream));
	let stream_clone = Arc::clone(&stream);

	let serialized_data = to_vec_named(&message)?;
	let mut stream = stream.lock().unwrap();
	stream.write_all(&serialized_data)?;
	stream.flush()?;

	let mut buffer = Vec::new();
	stream.read_to_end(&mut buffer)?;

	let mut deserializer = Deserializer::new(&buffer[..]);
	let response: ServerMessage = Deserialize::deserialize(&mut deserializer)?;
	Ok(response)
	}

fn start_lumy(lumy: &str, cmd: &str, debug: bool) {
	dbout(debug,0,format!("Starting \"{}\" Lumy", lumy).as_str());
	let mut child = Command::new(cmd)
	.stdout(Stdio::null())
	.stderr(Stdio::null())
	.spawn();

	match child {
		Ok(mut _child) => {
			dbout(debug,3,format!("Successfully started \"{}\" Lumy", lumy).as_str());
			},
		Err(err) => {
			dbout(debug,1,format!("Unable to start \"{}\" Lumy: {}", lumy, err).as_str());
			}
		}
	}

fn clientsetup() {
	println!("Luminum Client (Linux)\nby Christopher R. Curzio <ccurzio@luminum.net>\n");
	println!("Client Configuration\n--------------------");

	let mut server = String::new();
	let mut ui_server = String::new();
	let mut ui_server_key = String::new();
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

	print!("Enter Luminum server key: ");
	io::stdout().flush().unwrap();
	io::stdin()
		.read_line(&mut ui_server_key)
		.expect("Error reading user input");
	let ui_server_key = ui_server_key.trim();
	let server_key = ui_server_key.to_string();

	let confconn = Connection::open(CFGPATH).expect("Error: Could not initialize configuration database");
	confconn.execute("create table if not exists CONFIG ( KEY text not null, VALUE text not null )",[]).expect("Error: Could not create CONFIG table in configuration database");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"SHOST",server.as_str()]).expect("Error: Could not insert SHOST into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"SPORT",port.to_string().as_str()]).expect("Error: Could not insert SPORT into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"SVRKEY",server_key.as_str()]).expect("Error: Could not insert SKEY into CONFIG table.");
	confconn.close().unwrap();

	println!("\nLuminum Server: {}",server);
	println!("Server port: {}\n",port);
	println!("Luminum Client configuration complete.");

	process::exit(0);
	}

fn get_os_release() -> String {
	let mut os_release = String::new();
	match OsRelease::open() {
		Ok(result) => { os_release = result.pretty_name().to_string(); }
		Err(_) => { os_release = "Unknown".to_string(); }
		}
	return os_release;
	}

fn file_exists(path: &str) -> bool {
	fs::metadata(path).is_ok()
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
