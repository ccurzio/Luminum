extern crate short_crypt;
extern crate regex;
extern crate base64;

use chrono::Local;
use chrono::format::strftime::StrftimeItems;
use native_tls::{Identity, TlsAcceptor};
use std::env;
use std::str;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::process;
use std::net::{TcpListener, SocketAddr, TcpStream};
use clap::{Arg, App};
use regex::Regex;
use colored::Colorize;
use rpassword;
use short_crypt::ShortCrypt;
use rusqlite::{params, Connection, Result};
use std::net::Ipv4Addr;
use std::net::Ipv6Addr;
use openssl::rsa::Rsa;
use openssl::pkey::PKey;
use openssl::symm::Cipher;
use openssl::error::ErrorStack;
use openssl::x509::{X509NameBuilder, X509};
use openssl::asn1::Asn1Time;
use openssl::nid::Nid;

const VER: &str = "0.0.1";
const CFGKEY: &str = "config_encryption_password";
const CFGPATH: &str = "/opt/luminum/LuminumServer/conf/server.conf.db";
const DKPATH: &str = "/opt/luminum/LuminumServer/conf/luminum.key";
const DPPATH: &str = "/opt/luminum/LuminumServer/conf/luminum.pub";
const DCPATH: &str = "/opt/luminum/LuminumServer/conf/luminum.crt";
const DIPATH: &str = "/opt/luminum/LuminumServer/conf/luminum.pfx";
const DPORT: u16 = 10465;

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
	.arg(Arg::with_name("identity")
		.short('i')
		.long("identity")
		.value_name("IDENTITY_FILE")
		.help("Specifies the path to the identity file")
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
	let cert_file = matches.value_of("certificate").unwrap_or(DCPATH);
	let identity_file = matches.value_of("identity").unwrap_or(DIPATH);
	let address = matches.value_of("address").unwrap_or("127.0.0.1");
	let port = matches.value_of("port").unwrap_or("10465");
	let setup = matches.is_present("setup");
	let debug = matches.is_present("debug");

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

	// Startup
	dbout(debug,0,format!("Starting Luminum Server Daemon v{}...",VER).as_str());
	if fs::metadata(CFGPATH).is_ok() {
		let confconn = Connection::open(CFGPATH).expect("Error: Could not open configuration database.");
		}
	else {
		dbout(debug,1,format!("Configuration database not found. (Run with --setup)").as_str());
		process::exit(1);
		}

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

	// Network options sanity checking
	if contains_no_numbers(port) {
		dbout(debug,1,format!("Invalid port specified: {}", port).as_str());
		process::exit(1);
		}

	let addr_str = format!("{}:{}", address,port);
	let addr: SocketAddr = addr_str.parse().expect("Invalid socket address");

	// Check if necessary encryption files exist
	if !file_exists(cert_file) {
		dbout(debug,1,format!("Certificate file ({}) does not exist.", cert_file).as_str());
		process::exit(1);
		}
	else {
		dbout(debug,3,format!("Using certificate: {}",cert_file).as_str());
		}

	if !file_exists(key_file) {
		dbout(debug,1,format!("Private key file ({}) does not exist.", key_file).as_str());
		return;
		}
	else {
		dbout(debug,3,format!("Using private key: {}",key_file).as_str());
		}

	if !file_exists(identity_file) {
		dbout(debug,1,format!("Identity file ({}) does not exist.", identity_file).as_str());
		return;
		}
	else {
		dbout(debug,3,format!("Using identity: {}",identity_file).as_str());
		}

	// Load TLS certificate, private key, and identity files
	let identity = match Identity::from_pkcs12(&fs::read(identity_file).unwrap(), "PASSWORD_GOES_HERE") {
		Ok(identity) => identity,
		Err(err) => {
			dbout(debug,1,format!("Error loading TLS identity: {}", err).as_str());
			return;
			}
		};

	// Create TLS handler
	let acceptor = match TlsAcceptor::new(identity) {
		Ok(acceptor) => acceptor,
		Err(err) => {
			dbout(debug,1,format!("Error creating TLS handler: {}", err).as_str());
			return;
			}
		};

	// Starts the data listener service
	let listener = match TcpListener::bind(addr) {
		Ok(listener) => listener,
		Err(err) => {
			dbout(debug,1,format!("Failed to bind to port {port}: {}", err).as_str());
			return;
			}
		};

	// Set up break handler
	let running = Arc::new(AtomicBool::new(true));
	let r = running.clone();
	ctrlc::set_handler(move || {
		r.store(false, Ordering::SeqCst);
		println!();
		dbout(debug,0,"BREAK");
		dbout(debug,0,format!("Terminating Luminum Server Daemon.").as_str());
		process::exit(1);
		}).expect("Error creating break handler");

	// Startuo
	dbout(debug,3,format!("Luminum Server Daemon started on {}...",addr_str).as_str());

	// Listen for incoming connections
	while running.load(Ordering::SeqCst) {
		match listener.accept() {
			Ok((stream, _)) => {
				// Accept TLS connection
				let tls_stream = match acceptor.accept(stream) {
					Ok(stream) => stream,
					Err(err) => {
						dbout(debug,2,format!("Error accepting TLS connection: {}", err).as_str());
						continue;
						}
					};

				// Handle the connection
				handle_client(tls_stream);
				}
			Err(err) => { dbout(debug,2,format!("Error accepting connection: {}", err).as_str()); }
			}
		}
	dbout(debug,0,format!("Luminum server daemon stopped.").as_str());
	}

fn handle_client(mut stream: native_tls::TlsStream<TcpStream>) {
	// Buffer to store incoming data
	let mut buffer = [0; 1024];

	// Read data from the stream
	match stream.read(&mut buffer) {
		Ok(n) => {
			// Print received data
			println!("Received {} bytes: {}", n, String::from_utf8_lossy(&buffer[..n]));

			// Echo the data back to the client
			match stream.write_all(&buffer[..n]) {
				Ok(_) => println!("Echoed back to client"),
				Err(e) => eprintln!("Failed to echo back: {}", e),
				}
			}
		Err(e) => eprintln!("Error reading from stream: {}", e),
		}
	}

fn file_exists(path: &str) -> bool {
	fs::metadata(path).is_ok()
	}

fn contains_no_numbers(variable: &str) -> bool {
	let re = Regex::new(r"\d").unwrap();
	!re.is_match(variable)
	}

// Daemon Setup
fn daemonsetup() {
	println!("Luminum Server Daemon\nby Christopher R. Curzio <ccurzio@accipiter.org>\n");
	println!("Daemon Configuration\n--------------------");

	let mut address = String::new();
	let port: u16;
	let mut passphrase = String::new();

	loop {
		let mut ui_address = String::new();
		print!("Enter server IP address: ");
		io::stdout().flush().unwrap();

		io::stdin()
			.read_line(&mut ui_address)
			.expect("Error reading user input");
		let ui_address = ui_address.trim();

		if is_valid_ipv4_address(ui_address) || is_valid_ipv6_address(ui_address) {
			address = ui_address.to_string();
			break;
			}
		else {
			println!("Invalid IP address: {}\n", ui_address);
			}
		}

	loop {
		let mut ui_port = String::new();

		print!("Enter server port [{}]: ",DPORT);
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

	if fs::metadata(DKPATH).is_err() {
		println!("\nServer key pair does not exist. Creating...");
		loop {
			let keypass = rpassword::read_password_from_tty(Some("Enter passphrase for private key: ")).expect("Error reading passphrase input");
			let vkeypass = rpassword::read_password_from_tty(Some("Verify passphrase: ")).expect("Error reading verify passphrase input");
			if keypass != vkeypass {
				println!("Error: Passphrase mismatch\n");
				continue;
				}
			else {
				let _ = generate_private_key(keypass.as_str());
				passphrase = keypass;
				break;
				}
			}
		println!("Wrote private key: {}",DKPATH);
		println!("Wrote public key: {}",DPPATH);
		}

	if fs::metadata(DCPATH).is_err() {
		println!("\nServer certificate does not exist. Creating...");
		}

	let sc = ShortCrypt::new(CFGKEY);
	let (_, crypt_passphrase) = sc.encrypt(&passphrase);
	let encoded_crypt = base64::encode(&crypt_passphrase);

	let confconn = Connection::open(CFGPATH).expect("Error: Could not initialize configuration database");
	confconn.execute("create table if not exists CONFIG ( KEY text not null, VALUE text not null )",[]).expect("Error: Could not create CONFIG table in configuration database");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"IPADDR",address.as_str()]).expect("Error: Could not insert IPADDR into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"PORT",port.to_string().as_str()]).expect("Error: Could not insert PORT into CONFIG table.");
	confconn.execute("insert into CONFIG (KEY,VALUE) values (?1, ?2)",&[&"PKPASS",encoded_crypt.as_str()]).expect("Error: Could not insert PKPASS into CONFIG table.");
	confconn.close().unwrap();

	println!("Server IP address: {}", address);
	println!("Server Port: {}", port);
	println!("Private Key: {}", DKPATH);
	println!("Public Key: {}", DPPATH);
	println!("Certificate: {}", DCPATH);
	process::exit(0);
	}

// IPv4 Address Validation
fn is_valid_ipv4_address(ip: &str) -> bool {
	ip.parse::<Ipv4Addr>().is_ok()
	}

// IPv6 Address Validation
fn is_valid_ipv6_address(ip: &str) -> bool {
	ip.parse::<Ipv6Addr>().is_ok()
	}

// Create Private/Public Key PEM Files
fn generate_private_key(ui_keypass: &str) -> Result<(), ErrorStack> {
	let rsa = Rsa::generate(2048).unwrap();
	let pkey = PKey::from_rsa(rsa).unwrap();

	let mut keyfile = File::create(DKPATH).expect("Could not create private key file");
	let mut pubkeyfile = File::create(DPPATH).expect("Could not create public key file");

	let prv_key = pkey.private_key_to_pem_pkcs8().unwrap();
	let pub_key = pkey.public_key_to_pem().unwrap();
	let encrypted_key = pkey.private_key_to_pem_pkcs8_passphrase(Cipher::aes_256_cbc(), ui_keypass.as_bytes()).expect("Failed to encrypt private key");
	keyfile.write_all(str::from_utf8(encrypted_key.as_slice()).unwrap().as_bytes()).expect("Failed to write private key data to file");
	pubkeyfile.write_all(str::from_utf8(pub_key.as_slice()).unwrap().as_bytes()).expect("Failed to write public key data to file");
	Ok(())
	}

/*
fn generate_certificate() -> Result<(), ErrorStack> {
	let mut name_builder = X509NameBuilder::new().expect("Failed to create X509NameBuilder");
	name_builder.append_entry_by_nid(Nid::COMMONNAME, "example.com").expect("Failed to add CN to X509Name");
	let name = name_builder.build();

	let mut x509 = X509::builder().expect("Failed to create X509 builder");
	x509.set_version(2).expect("Failed to set version");
	x509.set_subject_name(&name).expect("Failed to set subject name");
	x509.set_issuer_name(&name).expect("Failed to set issuer name");
	x509.set_pubkey(&pub_key).expect("Failed to set public key");

	let not_before = Asn1Time::days_from_now(0).expect("Failed to set not before time");
	let not_after = Asn1Time::days_from_now(365).expect("Failed to set not after time");

	x509.set_not_before(&not_before).expect("Failed to set not before");
	x509.set_not_after(&not_after).expect("Failed to set not after");
	x509.sign(&pub_key, openssl::hash::MessageDigest::sha256()).expect("Failed to sign certificate");

	let certificate = x509.build();

	Ok(())
	}
*/

// Debug Output
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
