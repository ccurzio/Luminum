// Luminum Client for Linux
// by Christopher R. Curzio <ccurzio@luminum.net>

use clap::{Arg, App};
use colored::Colorize;
use chrono::Local;
use chrono::format::strftime::StrftimeItems;
use std::process;
use std::net::TcpListener;
use rusqlite::{params, Connection, Result};
use std::collections::HashMap;
use std::fs;
use std::io::{Read};

const VER: &str = "0.0.1";
const CFGPATH: &str = "/opt/luminum/LuminumClient/conf/luminum.conf.db";
const LPORT: u16 = 10511;

fn main() {
	let matches = App::new("Luminum Client (Linux)")
		.version(VER)
		.author("Christopher R. Curzio <ccurzio@luminum.net>")
	 .arg(Arg::with_name("debug")
		.short('d')
		.long("debug")
		.value_name("debug")
		.help("Enables debug mode")
		.takes_value(false))
	.get_matches();

	let debug = matches.is_present("debug");

	let mut clientconfig: HashMap<String, String> = HashMap::new();

	// Client Startup
	dbout(debug,0,format!("Starting Luminum Client v{}...",VER).as_str());

	lumcomm(debug);

	if fs::metadata(CFGPATH).is_ok() {
		// Read Client Config
		let confconn = Connection::open(CFGPATH).expect("Error: Could not open configuration database.");
		}
	else {
		dbout(debug,1,format!("Configuration database not found.").as_str());
		process::exit(1);
		}
	}

fn lumcomm(debug: bool) {
	let listener = TcpListener::bind("127.0.0.1:10511").expect("Error: Could not open listener on localhost");
	for stream in listener.incoming() {
		match stream {
			Ok(mut stream) => {
				let mut buffer = [0; 1024];
				let bytes_read = stream.read(&mut buffer).expect("Failed to read from socket");
				println!("Received: {}", String::from_utf8_lossy(&buffer[..bytes_read]));
				}
			Err(e) => {
				eprintln!("Error: {}", e);
				}
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
