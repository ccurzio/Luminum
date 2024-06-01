use chrono::Local;
use chrono::format::strftime::StrftimeItems;
use native_tls::{Identity, TlsAcceptor};
use std::env;
use std::fs;
use std::net::{TcpListener, SocketAddr, TcpStream};
use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::process;
use clap::{Arg, App};
use regex::Regex;
use colored::Colorize;

extern crate regex;

const VER: &str = "0.0.1";

fn main() {
	// Parse command-line arguments
	let matches = App::new("Luminum Server Daemon")
		.version(VER)
		.author("Christopher R. Curzio")
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
	.arg(Arg::with_name("port")
		.short('p')
		.long("port")
		.value_name("PORT")
		.help("Specifies the network data port to use")
		.takes_value(true))
	.arg(Arg::with_name("address")
		.short('a')
		.long("address")
		.value_name("ADDRESS")
		.help("Specifies the network IP address to bind to")
		.takes_value(true))
	.arg(Arg::with_name("debug")
		.short('d')
		.long("debug")
		.value_name("debug")
		.help("Enables debug mode")
		.takes_value(false))
	.get_matches();

	// Set variables based on command-line arguments or use defaults
	let cert_file = matches.value_of("certificate").unwrap_or("/opt/luminum/LuminumServer/conf/luminum.crt");
	let key_file = matches.value_of("key").unwrap_or("/opt/luminum/LuminumServer/conf/luminum.key");
	let identity_file = matches.value_of("identity").unwrap_or("/opt/luminum/LuminumServer/conf/luminum.pfx");
	let address = matches.value_of("address").unwrap_or("127.0.0.1");
	let port = matches.value_of("port").unwrap_or("4988");
	let debug = matches.is_present("debug");

	// Start the thing
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
		dbout(debug,3,format!("Certificate loaded: {}",cert_file).as_str());
		}

	if !file_exists(key_file) {
		dbout(debug,1,format!("Private key file ({}) does not exist.", key_file).as_str());
		return;
		}
	else {
		dbout(debug,3,format!("Private key loaded: {}",key_file).as_str());
		}

	if !file_exists(identity_file) {
		dbout(debug,1,format!("Identity file ({}) does not exist.", identity_file).as_str());
		return;
		}
	else {
		dbout(debug,3,format!("Identity loaded: {}",identity_file).as_str());
		}

	// Load TLS certificate, private key, and identity files
	let identity = match Identity::from_pkcs12(&fs::read(identity_file).unwrap(), "PASSWORD_GOES_HERE") {
		Ok(identity) => identity,
		Err(err) => {
			eprintln!("Error loading TLS identity: {}", err);
			return;
			}
		};

	// Create TLS handler
	let acceptor = match TlsAcceptor::new(identity) {
		Ok(acceptor) => acceptor,
		Err(err) => {
			eprintln!("Error creating TLS handler: {}", err);
			return;
			}
		};

	// Starts the data listener service
	let listener = match TcpListener::bind(addr) {
		Ok(listener) => listener,
		Err(err) => {
			eprintln!("Failed to bind to port {port}: {}", err);
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
		dbout(debug,0,format!("Terminating Server Listener Process.").as_str());
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
						eprintln!("Error accepting TLS connection: {}", err);
						continue;
						}
					};

				// Handle the connection
				handle_client(tls_stream);
				}
			Err(err) => { dbout(debug,2,format!("Error accepting connection: {}", err).as_str()); }
			}
		}
	println!("Luminum server listener stopped.");
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
