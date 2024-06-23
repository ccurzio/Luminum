use chrono::Local;
use chrono::format::strftime::StrftimeItems;
use std::collections::HashMap;
use std::env;
use std::str;
use std::fs::{self, File};
use std::path::Path;
use std::io::{self, BufRead, Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc};
use std::process;
use std::net::{TcpListener, SocketAddr, TcpStream, Ipv4Addr, Ipv6Addr};
use libc::setuid;
use random_str;
use magic_crypt::{new_magic_crypt, MagicCryptTrait};
use clap::{Arg, App};
use regex::Regex;
use colored::Colorize;
use rpassword;
use rusqlite::{params, Connection, Result};
use mysql::*;
use mysql::prelude::Queryable;
use uuid::Uuid;
use native_tls::{Identity, TlsAcceptor};
use openssl::bn::BigNum;
use openssl::rsa::Rsa;
use openssl::pkey::PKey;
use openssl::symm::Cipher;
use openssl::error::ErrorStack;
use openssl::pkcs12::Pkcs12;
use openssl::x509::{X509NameBuilder, X509};
use openssl::x509::extension::SubjectAlternativeName;
use openssl::hash::MessageDigest;
use openssl::asn1::Asn1Time;
use openssl::nid::Nid;
use serde::{Deserialize, Serialize};
use rmp_serde::{from_read, to_vec_named};

const VER: &str = "0.0.1";
const CFGPATH: &str = "/opt/Luminum/LuminumServer/config/server.conf.db";
const DKPATH: &str = "/opt/Luminum/LuminumServer/config/luminum.key";
const DPPATH: &str = "/opt/Luminum/LuminumServer/config/luminum.pub";
const DCPATH: &str = "/opt/Luminum/LuminumServer/config/luminum.crt";
const DIPATH: &str = "/opt/Luminum/LuminumServer/config/luminum.pfx";
const DPORT: &str = "10465";

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
	data: MessageData
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

fn main() {
	// Parse command-line arguments
	let matches = App::new("Luminum Server Daemon")
		.version(VER)
		.author("Christopher R. Curzio <ccurzio@accipiter.org>")
	.arg(Arg::with_name("certificate")
		.short('c')
		.long("certificate")
		.value_name("CERT_FILE")
		.help("Specifies the path to the certificate file")
		.takes_value(true))
	.arg(Arg::with_name("key")
		.short('k')
		.long("key")
		.value_name("KEY_FILE")
		.help("Specifies the path to the private key file")
		.takes_value(true))
	.arg(Arg::with_name("pubkey")
		.short('b')
		.long("pubkey")
		.value_name("PUBKEY_FILE")
		.help("Specifies the path to the public key file")
		.takes_value(true))
	.arg(Arg::with_name("identity")
		.short('i')
		.long("identity")
		.value_name("IDENTITY_FILE")
		.help("Specifies the path to the PFX identity file")
		.takes_value(true))
	.arg(Arg::with_name("address")
		.short('a')
		.long("address")
		.value_name("ADDRESS")
		.help("Specifies the network IP address to bind to")
		.takes_value(true))
	.arg(Arg::with_name("port")
		.short('p')
		.long("port")
		.value_name("PORT")
		.help("Specifies the network data port to use")
		.takes_value(true))
	.arg(Arg::with_name("setup")
		.short('s')
		.long("setup")
		.value_name("SETUP")
		.help("Set daemon configuration parameters")
		.takes_value(false))
	.arg(Arg::with_name("debug")
		.short('d')
		.long("debug")
		.value_name("debug")
		.help("Enables debug mode")
		.takes_value(false))
	.get_matches();

	// Set variables based on command-line arguments or use defaults
	let key_file = matches.value_of("key").unwrap_or(DKPATH);
	let pub_file = matches.value_of("pubkey").unwrap_or(DPPATH);
	let cert_file = matches.value_of("certificate").unwrap_or(DCPATH);
	let identity_file = matches.value_of("identity").unwrap_or(DIPATH);
	let mut address = matches.value_of("address").unwrap_or("");
	let mut port = matches.value_of("port").unwrap_or("");
	let setup = matches.is_present("setup");
	let debug = matches.is_present("debug");

	dbout(debug,0,format!("Starting Luminum Server Daemon v{}...",VER).as_str());

	// Figure out location on disk
	match env::current_exe() {
		Ok(current_exe) => {
			let path_string = current_exe.to_string_lossy().into_owned();
			dbout(debug,4,format!("Run location: {}",path_string).as_str());
			}
		Err(err) => {
			dbout(debug,1,format!("Unable to determine run location: {}",err).as_str());
			}
		}

	// Check if the standard installation paths exist
	if fs::metadata("/opt/Luminum").is_err() || fs::metadata("/opt/Luminum/LuminumServer").is_err() || fs::metadata("/opt/Luminum/LuminumServer/config/").is_err() {
		dbout(debug,1,format!("Luminum Server install paths are missing. Is the software installed correctly?").as_str());
		process::exit(1);
		}

	// Set up break handler
	let running = Arc::new(AtomicBool::new(true));
	let r = running.clone();
	ctrlc::set_handler(move || {
		r.store(false, Ordering::SeqCst);
		print!("\r\x1B[K");
		dbout(debug,0,"Received BREAK signal. Terminating Luminum Server...");
		process::exit(1);
		}).expect("Error creating break handler");

	// Check if setup flag is specified and run setup routine if true
	if setup {
		dbout(debug,4,format!("Starting daemon setup.").as_str());
		if fs::metadata(CFGPATH).is_err() {
			daemonsetup();
			}
		else {
			dbout(debug,1,format!("Server configuration already exists. Aborting.").as_str());
			process::exit(1);
			}
		}

	// Import server configuration
	let mut serverconfig: HashMap<String, String> = HashMap::new();
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
				serverconfig.insert(cfg.key.to_string(),cfg.value.to_string());
				}
			}

		if address == "" {
			address = serverconfig.get("IPADDR").expect("Error: Could not set server IP address from configuration database.");
			}
		if port == "" {
			port = serverconfig.get("PORT").expect("Error: Could not set server port from configuration database.");
			}
		}
	else {
		dbout(debug,1,format!("Configuration database not found. (Run with --setup)").as_str());
		process::exit(1);
		}

	// Network options sanity checking
	if contains_no_numbers(port) {
		dbout(debug,1,format!("Invalid port specified: {}", port).as_str());
		process::exit(1);
		}

	let addr_str = format!("{}:{}", address,port);
	let addr: SocketAddr = addr_str.parse().expect("Invalid socket address");

	// Check if necessary encryption files exist
	if !file_exists(key_file) {
		dbout(debug,1,format!("Private key file ({}) does not exist.", key_file).as_str());
		process::exit(1);
		}
	else {
		dbout(debug,3,format!("Using private key: {}",key_file).as_str());
		}

	if !file_exists(pub_file) {
		dbout(debug,1,format!("Public key file ({}) does not exist.", pub_file).as_str());
		process::exit(1);
		}
	else {
		dbout(debug,3,format!("Using public key: {}",pub_file).as_str());
		}

	if !file_exists(cert_file) {
		dbout(debug,1,format!("Certificate file ({}) does not exist.", cert_file).as_str());
		process::exit(1);
		}
	else {
		dbout(debug,3,format!("Using certificate: {}",cert_file).as_str());
		}

	if !file_exists(identity_file) {
		dbout(debug,1,format!("Identity file ({}) does not exist.", identity_file).as_str());
		process::exit(1);
		}
	else {
		dbout(debug,3,format!("Using identity: {}",identity_file).as_str());
		}

	// Check if the "luminum" system user exists and switch process to that user
	let (user_exists,user_uid) = sysuser_info("luminum");
	if user_exists {
		let parse_uid: Result<u32, _> = user_uid.unwrap_or_else(|| String::new()).parse();
		match parse_uid {
			Ok(run_uid) => {
				if unsafe { setuid(run_uid) } != 0 {
					dbout(debug,1,format!("Could not assign process to \"luminum\" system user.").as_str());
					process::exit(1);
					}
				},
			Err(err) => {
				dbout(debug,1,format!("Could not assign process to \"luminum\" system user: {}", err).as_str());
				process::exit(1);
				}
			}
		}
	else {
		dbout(debug,1,format!("The \"luminum\" system user does not exist.").as_str());
		process::exit(1);
		}

	// Connect to MySQL server
	if !file_exists("/var/run/mysqld/mysqld.sock") {
		dbout(debug,1,format!("Database socket (/var/run/mysqld/mysqld.sock) is missing.").as_str());
		process::exit(1);
		}

	let server_key = serverconfig.get("SVRKEY").unwrap();
	let mc = new_magic_crypt!(&server_key, 256);
	let encrypted_dbpass = serverconfig.get("DBPASS").unwrap();
	let dbpass = mc.decrypt_base64_to_string(&encrypted_dbpass).unwrap();

	let socket_path = "/var/run/mysqld/mysqld.sock";

	// Open CLIENTS database
	let copts = Opts::from(OptsBuilder::new()
		.socket(Some(socket_path))
		.user(Some("luminum"))
		.pass(Some(dbpass.clone()))
		.db_name(Some("CLIENTS")));
	let clients_db_pool = Arc::new(Pool::new(copts).unwrap());

/*
	let clientsconn = match clients_db_pool.get_conn() {
		Ok(cconn) => {
			dbout(debug,3,format!("Connected to MySQL database: CLIENTS").as_str());
			cconn
			}
		Err(err) => {
			dbout(debug,1,format!("Error connecting to MySQL database: {}", err).as_str());
			std::process::exit(1);
			}
		};
*/
	// TODO - Need to create a check for configured modules so we're not creating connections for modules not enabled

	// Open INTEGRITY database
	let liopts = Opts::from(OptsBuilder::new()
		.socket(Some(socket_path))
		.user(Some("luminum"))
		.pass(Some(dbpass.clone()))
		.db_name(Some("INTEGRITY")));
	let integrity_db_pool = Arc::new(Pool::new(liopts).unwrap());

/*
	let liconn = match integrity_db_pool.get_conn() {
		Ok(conn) => {
			dbout(debug,3,format!("Connected to MySQL database: INTEGRITY").as_str());
			conn
			}
		Err(err) => {
			dbout(debug,1,format!("Error connecting to MySQL database: {}", err).as_str());
			std::process::exit(1);
			}
		};
*/
	// Use private key passphrase from server configuration and load PKE identity file
	let encrypted_passphrase = serverconfig.get("PKPASS").unwrap();
	let passphrase = mc.decrypt_base64_to_string(&encrypted_passphrase).unwrap();

	let identity = match Identity::from_pkcs12(&fs::read(identity_file).unwrap(), &passphrase) {
		Ok(identity) => identity,
		Err(err) => {
			dbout(debug,1,format!("Error loading TLS identity: {}", err).as_str());
			return;
			}
		};

	// Create TLS handler
	let acceptor = match TlsAcceptor::new(identity) {
		// TODO: Probably want to set up the connection to require client certificates
		Ok(acceptor) => acceptor,
		Err(err) => {
			dbout(debug,1,format!("Error creating TLS handler: {}", err).as_str());
			return;
			}
		};

	// Start the data listener service
	let listener = match TcpListener::bind(addr) {
		Ok(listener) => listener,
		Err(err) => {
			dbout(debug,1,format!("Failed to bind to port {port}: {}", err).as_str());
			return;
			}
		};

	// Finished Startup
	dbout(debug,3,format!("Luminum Server Daemon started on {}...",addr_str).as_str());

	// Listen for incoming connections
	while running.load(Ordering::SeqCst) {
		match listener.accept() {
			Ok((stream, peer_addr)) => {
				dbout(debug,4,format!("Incoming connection from {}", peer_addr).as_str());
				// Accept TLS connection
				let mut tls_stream = match acceptor.accept(stream) {
					Ok(stream) => {
						dbout(debug,3,format!("Connection established with {}", peer_addr).as_str());
						stream
						},
					Err(err) => {
						dbout(debug,2,format!("Error accepting TLS connection: {}", err).as_str());
						continue;
						}
					};
				// Handle the connection
				let mut buffer = [0; 1024];

				match tls_stream.read(&mut buffer) {
					Ok(n) => {
						if n > 0 {
							match from_read::<_, ClientMessage>(&buffer[..n]) {
								Ok(msg) => {
									//println!("Received from client: {:?}",msg);
									if msg.product == "Luminum Client" && !msg.uid.is_empty() {
										let uid = msg.uid.to_string();
										if msg.content.action == "heartbeat" {
											let mut conn = clients_db_pool.get_conn().unwrap();
											conn.exec_drop(format!("update STATUS set LASTSEEN = now() where UID = '{}'",uid),());
											dbout(debug,4,format!("Received heartbeat from UID \"{}\"", &uid).as_str());
											}
										else if msg.uid == "NONE" && msg.content.action == "register" {
											dbout(debug,4,format!("Received endpoint registration request from {}",&peer_addr).as_str());
											if msg.content.data.serverkey == Some(String::from(server_key)) {
												register_client(&clients_db_pool,msg.content.data,&mut tls_stream,debug);
												}
											else {
												dbout(debug,2,format!("An invalid server key was provided by {} during registration.", &peer_addr).as_str());
												}
											}
										else if msg.content.lumy == "Integrity" {
											if msg.content.action == "newconfig" {
												dbout(debug,4,format!("Received Integrity Lumy configuration request from {}",&peer_addr).as_str());
												integrity_config(&integrity_db_pool,msg.uid,&mut tls_stream,"new".to_string(),debug);
												}
											}
										}
									},
								Err(_) => {
									dbout(debug,2,format!("Malformed data in stream from {}", peer_addr).as_str());
									}
								}
							}

						},
					Err(err) => {
						dbout(debug,2,format!("Error reading from stream: {}", err).as_str());
						}
					}
				},
			Err(err) => { dbout(debug,2,format!("Error accepting connection: {}", err).as_str()); }
			}
		}

	dbout(debug,0,format!("Luminum server daemon stopped.").as_str());
	}

fn handle_msg(pool: &Arc<Pool>, peer_addr: String, data: &str, stream: &mut native_tls::TlsStream<TcpStream>, debug: bool) {
	let conn = pool.get_conn().unwrap();
	}

fn verify_client(pool: &Arc<Pool>, peer_addr: String, data: &str, stream: &mut native_tls::TlsStream<TcpStream>, debug: bool) {
	let conn = pool.get_conn().unwrap();
	let mut vstat = String::new();
	}

fn register_client(pool: &Arc<Pool>, data: MessageData, stream: &mut native_tls::TlsStream<TcpStream>, debug: bool) {
	let mut conn = pool.get_conn().unwrap();
	let new_uid = Uuid::new_v4();

	let hostname = data.hostname.unwrap();
	let osplat = data.osplat.unwrap();
	let osver = data.osver.unwrap();
	let ipv4 = data.ipv4.unwrap_or("".to_string());
	let ipv6 = data.ipv6.unwrap_or("".to_string());

	let query = format!("insert into STATUS (UID,HOSTNAME,IPV4,IPV6,OSPLAT,OSVER,REGDATE,LASTSEEN) VALUES ('{}', '{}', '{}', '{}', '{}', '{}',now(),now())", new_uid, hostname, ipv4, ipv6, osplat, osver);
	match conn.query_drop(query) {
		Ok(_) => {
			let response_data = MessageData {
				uid: Some(String::from(new_uid)),
				serverkey: None,
				hostname: None,
				osplat: None,
				osver: None,
				ipv4: None,
				ipv6: None,
				info: None
				};
			let response_content = MessageContent {
				lumy: String::from("Luminum Core"),
				status: String::from("OK"),
				action: String::from("register"),
				data: response_data
				};
			let response = ServerMessage {
				version: String::from(VER),
				content: response_content
				};
			let serialized_data = to_vec_named(&response).expect("Error: Failed to serialize message to client.");
			stream.write_all(&serialized_data).expect("Error: Failed to send response to client.");
			dbout(debug,3,format!("Endpoint \"{}\" successfully registered. (UID {})", hostname,new_uid).as_str());
			},
		Err(err) => {
			dbout(debug,2,format!("Failed to register endpoint \"{}\": {}", hostname,err).as_str());
			}
		}
	}

fn integrity_config(pool: &Arc<Pool>, uid: String, stream: &mut native_tls::TlsStream<TcpStream>, action: String, debug: bool) {
	let mut conn = pool.get_conn().unwrap();
	if action == "new" {
		match conn.exec_drop(format!("delete from WATCHLIST where ID = (select ID from CLIENTS.STATUS where UID = '{}')",uid),()) {
			Ok(_) => { dbout(debug,3,format!("Deleted saved Integrity Lumy configuration for UID \"{}\"", uid).as_str()); }
			Err(err) => { dbout(debug,2,format!("Error deleting saved Integrity Lumy configuration for UID \"{}\": {}", uid, err).as_str()); }
			}
		let query = format!("insert into WATCHLIST (ID, OS, PATH) SELECT status.ID, status.OSPLAT, wd.PATH from (SELECT ID, OSPLAT FROM CLIENTS.STATUS WHERE UID = '{}') AS status CROSS JOIN (SELECT PATH FROM WATCH_DEFAULT WHERE OS = (SELECT OSPLAT FROM CLIENTS.STATUS WHERE UID = '{}')) AS wd", uid, uid);
		match conn.query_drop(query) {
			Ok(_) => {
				let query = format!("select PATH FROM WATCHLIST WHERE ID = (select ID from CLIENTS.STATUS where UID = '{}')", uid);
				let results: Vec<String> = conn.exec(query, ()).expect("Error: Unable to retrieve saved Integrity configuration for endpoint");

				let response_data = MessageData {
					uid: None,
					serverkey: None,
					hostname: None,
					osplat: None,
					osver: None,
					ipv4: None,
					ipv6: None,
					info: Some(results)
					};
				let response_content = MessageContent {
					lumy: String::from("Integrity"),
					status: String::from("OK"),
					action: String::from("newconfig"),
					data: response_data
					};
				let response = ServerMessage {
					version: String::from(VER),
					content: response_content
					};
				let serialized_data = to_vec_named(&response).expect("Error: Failed to serialize message to client.");
				stream.write_all(&serialized_data).expect("Error: Failed to send response to client.");
				dbout(debug,3,format!("Saved Integrity Lumy configuration for UID \"{}\"", uid).as_str());			
				}
	                Err(err) => {
	                        dbout(debug,2,format!("Failed to save Integrity Lumy configuration: {}", err).as_str());
				}
                        }
		}
	}

fn file_exists(path: &str) -> bool {
	fs::metadata(path).is_ok()
	}

fn contains_no_numbers(variable: &str) -> bool {
	let re = Regex::new(r"\d").unwrap();
	!re.is_match(variable)
	}

fn contains_only_numbers(input: &str) -> bool {
	let re = Regex::new(r"^\d+$").unwrap();
	re.is_match(input)
	}

// Daemon Setup
fn daemonsetup() {
	println!("Luminum Server Daemon\nby Christopher R. Curzio <ccurzio@accipiter.org>\n");
	println!("Daemon Configuration\n--------------------");

	let mut setup_address = String::new();
	let mut setup_port = String::new();
	let mut setup_passphrase = String::new();

	loop {
		let mut ui_address = String::new();
		print!("Enter server IP address: ");
		io::stdout().flush().unwrap();

		io::stdin()
			.read_line(&mut ui_address)
			.expect("Error reading user input");
		let ui_address = ui_address.trim();

		if is_valid_ipv4_address(ui_address) || is_valid_ipv6_address(ui_address) {
			setup_address = ui_address.to_string();
			break;
			}
		else {
			println!("Invalid IP address: {}\n", ui_address);
			}
		}

	loop {
		let mut ui_port = String::new();

		print!("Enter server port [{}]: ", DPORT.to_string());
		io::stdout().flush().unwrap();

		io::stdin().read_line(&mut ui_port).unwrap();
		let ui_port = ui_port.trim();

		if ui_port.is_empty() {
			setup_port = DPORT.to_string();
			break;
			}
		else {
			if ui_port == "0" || !contains_only_numbers(ui_port) {
				println!("Invalid port: {}\n", ui_port);
				continue;
				}
			else {
				setup_port = ui_port.to_string();
				break;
				}
			}
		}

	if fs::metadata(DKPATH).is_err() {
		println!("\nServer key pair does not exist. Creating...");
		loop {
			let keypass = rpassword::read_password_from_tty(Some("Enter PEM passphrase for private key: ")).expect("Error reading passphrase input");
			let vkeypass = rpassword::read_password_from_tty(Some("Verify PEM passphrase: ")).expect("Error reading verify passphrase input");
			if keypass != vkeypass {
				println!("Error: Passphrase mismatch\n");
				continue;
				}
			else {
				let _ = generate_private_key(keypass.as_str());
				setup_passphrase = keypass;
				break;
				}
			}
		}
	else {
		let mut ui_exkey = String::new();
		println!("\nA private key was found at {}", DKPATH);
		loop {
			print!("Do you want to use this key? [Y/n]: ");
			io::stdout().flush().unwrap();
			io::stdin().read_line(&mut ui_exkey).expect("Error reading user input");
			let ui_exkey = ui_exkey.trim();
			if ui_exkey == "Y" || ui_exkey == "y" || ui_exkey.is_empty() {
				loop {
					let ui_passphrase = rpassword::read_password_from_tty(Some("Enter PEM passphrase for private key: ")).expect("Error reading passphrase input");
					setup_passphrase = ui_passphrase.trim().to_string();
					break;
					}
				break;
				}
			else {
				let oldkey = format!("{DKPATH}.old");
				let oldpub = format!("{DPPATH}.old");
				let oldcrt = format!("{DCPATH}.old");
				let oldpfx = format!("{DIPATH}.old");

				if file_exists(&oldkey) { fs::remove_file(&oldkey).expect("Error: Could not delete existing private key backup file"); }
				if file_exists(&oldpub) { fs::remove_file(&oldpub).expect("Error: Could not delete existing private key backup file"); }
				if file_exists(&oldcrt) { fs::remove_file(&oldcrt).expect("Error: Could not delete existing certificate backup file"); }
				if file_exists(&oldpfx) { fs::remove_file(&oldpfx).expect("Error: Could not delete existing identity backup file"); }

				match fs::rename(DKPATH, &oldkey) {
					Ok(()) => {
						println!("Backed up existing private key to {}", oldkey);
						},
					Err(err) => {
						println!("Failure: Backup of existing private key failed: {}", err);
						process::exit(1);
						}
					}
				match fs::rename(DPPATH, &oldpub) {
					Ok(()) => {
						println!("Backed up existing public key to {}", oldpub);
						},
					Err(err) => {
						println!("Failure: Backup of existing public key failed: {}", err);
						process::exit(1);
						}
					}
				match fs::rename(DCPATH, &oldcrt) {
					Ok(()) => {
						println!("Backed up existing certificate to {}", oldcrt);
						},
					Err(err) => {
						println!("Failure: Backup of existing certificate failed: {}", err);
						process::exit(1);
						}
					}
				match fs::rename(DIPATH, &oldpfx) {
					Ok(()) => {
						println!("Backed up existing identity file to {}", oldpfx);
						},
					Err(err) => {
						println!("Failure: Backup of existing identity file failed: {}",err);
						process::exit(1);
						}
					}
				println!("\nCreating new keypair and identity...");
				loop {
					let keypass = rpassword::read_password_from_tty(Some("Enter PEM passphrase for private key: ")).expect("Error reading passphrase input");
					let vkeypass = rpassword::read_password_from_tty(Some("Verify PEM passphrase: ")).expect("Error reading verify passphrase input");
					if keypass != vkeypass {
						println!("Error: Passphrase mismatch\n");
						continue;
						}
					else {
						let _ = generate_private_key(keypass.as_str());
						setup_passphrase = keypass;
						break;
						}
					}
				}
			if setup_passphrase.is_empty() { continue; }
			else { break; }
			}
		}

	if fs::metadata(DCPATH).is_err() {
		println!("\nServer certificate does not exist. Creating...");
		let _ = generate_certificate(setup_passphrase.as_str());
		}

	let sid = Uuid::new_v4().to_string();
	let new_server_key = random_str::get_string(32, true, true, true, false);
	let mc = new_magic_crypt!(&new_server_key, 256);
	let encoded_crypt = mc.encrypt_str_to_base64(setup_passphrase);
	let dbpass = random_str::get_string(16, true, true, true, true);
	let encoded_dbpass = mc.encrypt_str_to_base64(dbpass.clone());

	let confconn = Connection::open(CFGPATH).expect("Error: Could not initialize configuration database");
	confconn.execute("create table if not exists CONFIG ( KEY text not null, VALUE text not null )",[]).expect("Error: Could not create CONFIG table in configuration database");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"SID",sid.as_str()]).expect("Error: Could not insert SID into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"SVRKEY",new_server_key.as_str()]).expect("Error: Could not insert SVRKEY into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"IPADDR",setup_address.as_str()]).expect("Error: Could not insert IPADDR into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"PORT",setup_port.as_str()]).expect("Error: Could not insert PORT into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"PKPASS",encoded_crypt.as_str()]).expect("Error: Could not insert PKPASS into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"DBPASS",encoded_dbpass.as_str()]).expect("Error: Could not insert DBPASS into CONFIG table.");
	confconn.close().unwrap();

	println!("Server IP address: {}", setup_address);
	println!("Server Port: {}", setup_port);
	println!("Private Key: {}", DKPATH);
	println!("Public Key: {}", DPPATH);
	println!("Certificate: {}", DCPATH);
	println!("Database password for \"luminum\" user: {}", dbpass);
	println!("\nNOTE: This will be the only time the database password for the \"luminum\" user will be made available. Please make a note of it!\n\n");
	println!("Luminum Server setup is complete.");
	process::exit(0);
	}

// IPv4 Address Validation
fn is_valid_ipv4_address(ip: &str) -> bool {
	if ip.to_string() != "127.0.0.1" {
		return ip.parse::<Ipv4Addr>().is_ok()
		}
	else { return false; }
	}

// IPv6 Address Validation
fn is_valid_ipv6_address(ip: &str) -> bool {
	if ip.to_string() != "0:0:0:0:0:0:0:1" && ip.to_string() != "::1" {
		ip.parse::<Ipv6Addr>().is_ok()
		}
	else { return false; }
	}

// Create Private/Public Key PEM Files
fn generate_private_key(ui_keypass: &str) -> Result<(), ErrorStack> {
	let rsa = Rsa::generate(2048).unwrap();
	let pkey = PKey::from_rsa(rsa).unwrap();

	let mut keyfile = File::create(DKPATH).expect("Could not create private key file");
	let mut pubkeyfile = File::create(DPPATH).expect("Could not create public key file");

	//let prv_key = pkey.private_key_to_pem_pkcs8().unwrap();
	let pub_key = pkey.public_key_to_pem().unwrap();
	let encrypted_key = pkey.private_key_to_pem_pkcs8_passphrase(Cipher::aes_256_cbc(), ui_keypass.as_bytes()).expect("Failed to encrypt private key");
	keyfile.write_all(str::from_utf8(encrypted_key.as_slice()).unwrap().as_bytes()).expect("Failed to write private key data to file");
	pubkeyfile.write_all(str::from_utf8(pub_key.as_slice()).unwrap().as_bytes()).expect("Failed to write public key data to file");

	Ok(())
	}


fn generate_certificate(ui_keypass: &str) -> Result<(), ErrorStack> {
	let mut cert_co = String::new();
	let mut cert_st = String::new();
	let mut cert_lc = String::new();
	let mut cert_on = String::new();
	let mut cert_cn = String::new();

	let mut prv_key_file = File::open(DKPATH).expect("Unable to open private key file");
	let mut prv_key_pem = String::new();
	let mut pub_key_file = File::open(DPPATH).expect("Unable to open public key file");
	let mut pub_key_pem = String::new();

	prv_key_file.read_to_string(&mut prv_key_pem).expect("Unable to read private key file");
	let prv_key = PKey::private_key_from_pem_passphrase(prv_key_pem.as_bytes(),ui_keypass.as_bytes()).expect("Unable to parse private key");
	pub_key_file.read_to_string(&mut pub_key_pem).expect("Unable to read public key file");
	let pub_key = PKey::public_key_from_pem_passphrase(pub_key_pem.as_bytes(),ui_keypass.as_bytes()).expect("Unable to parse public key");

	print!("Two-letter country code: ");
	io::stdout().flush().unwrap();
	io::stdin()
		.read_line(&mut cert_co)
		.expect("Error reading user input");
	let cert_co = cert_co.trim();

	print!("State or province: ");
	io::stdout().flush().unwrap();
	io::stdin()
		.read_line(&mut cert_st)
		.expect("Error reading user input");
	let cert_st = cert_st.trim();

	print!("City or locality name: ");
	io::stdout().flush().unwrap();
	io::stdin()
		.read_line(&mut cert_lc)
		.expect("Error reading user input");
	let cert_lc = cert_lc.trim();

	print!("Organization: ");
	io::stdout().flush().unwrap();
	io::stdin()
		.read_line(&mut cert_on)
		.expect("Error reading user input");
	let cert_on = cert_on.trim();

	print!("Enter certificate common name (CN): ");
	io::stdout().flush().unwrap();
	io::stdin()
		.read_line(&mut cert_cn)
		.expect("Error reading user input");
	let cert_cn = cert_cn.trim();

	let mut serial_number = BigNum::new().unwrap();
	serial_number.rand(159, openssl::bn::MsbOption::MAYBE_ZERO, false).unwrap();
	let serial_number = serial_number.to_asn1_integer().unwrap();

	let mut name_builder = X509NameBuilder::new().unwrap();
	name_builder.append_entry_by_nid(Nid::COUNTRYNAME, cert_co).expect("Failed to add country to X509Name");
	name_builder.append_entry_by_nid(Nid::STATEORPROVINCENAME, cert_st).expect("Failed to add state to X509Name");
	name_builder.append_entry_by_nid(Nid::LOCALITYNAME, cert_lc).expect("Failed to add city to X509Name");
	name_builder.append_entry_by_nid(Nid::ORGANIZATIONNAME, cert_on).expect("Failed to add organization to X509Name");
	name_builder.append_entry_by_nid(Nid::COMMONNAME, cert_cn).expect("Failed to add CN to X509Name");

	let mut x509 = X509::builder().expect("Failed to create X509 builder");
	let name = name_builder.build();
	x509.set_version(3).expect("Failed to set x509 version");
	x509.set_serial_number(&serial_number).unwrap();
	x509.set_subject_name(&name).expect("Failed to set x509 subject name");
	x509.set_issuer_name(&name).expect("Failed to set x509 issuer name");
	x509.set_pubkey(&pub_key).unwrap();

	let not_before = Asn1Time::days_from_now(0).expect("Failed to set not before time");
	let not_after = Asn1Time::days_from_now(365).expect("Failed to set not after time");

	x509.set_not_before(&not_before).expect("Failed to set not before");
	x509.set_not_after(&not_after).expect("Failed to set not after");

	let san = SubjectAlternativeName::new()
		.ip("192.168.1.10")
		.dns(cert_cn)
		.build(&x509.x509v3_context(None, None))
		.unwrap();
	x509.append_extension(san).unwrap();

	x509.sign(&prv_key, MessageDigest::sha256()).unwrap();

	let certificate = x509.build();
	let cert_pem = certificate.to_pem().unwrap();

	match std::fs::write(DCPATH, &cert_pem) {
		Ok(_) => println!("Certificate written to {}",DCPATH),
		Err(err) => eprintln!("Error writing certificate to file: {}", err)
		}

	let mut pkcs12_builder = Pkcs12::builder();
	//let pkcs12 = pkcs12_builder.build(&ui_keypass,"Luminum Server Key",&prv_key, &certificate).expect("Failed to build PKCS#12 structure");
	let pkcs12 = pkcs12_builder.name("Luminum Server Key").pkey(&prv_key).cert(&certificate).build2(&ui_keypass).expect("Failed to build PKCS#12 structure");
	let pkcs12_der = pkcs12.to_der().expect("Failed to convert PKCS#12 to DER format");
	match std::fs::write(DIPATH, &pkcs12_der) {
		Ok(_) => println!("Identity written to {}",DIPATH),
		Err(err) => eprintln!("Error writing identity file: {}", err)
		}

	Ok(())
	}

// See if a specific user exists on the system
fn sysuser_info(username: &str) -> (bool, Option<String>) {
	let pwpath = Path::new("/etc/passwd");

	if let Ok(pwfile) = File::open(pwpath) {
		let reader = io::BufReader::new(pwfile);
		for line in reader.lines() {
			if let Ok(line) = line {
				let fields: Vec<&str> = line.split(':').collect();
				if let (Some(user),Some(uid)) = (fields.get(0),fields.get(2)) {
					if *user == username {
						return (true, Some((*uid).to_string()));
						}
					}
				}
			}
		}
	return (false,None);
	}

// Debug Output
pub fn dbout(debug: bool, outlvl: i32, output: &str) {
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
