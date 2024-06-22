use std::fs::{self, File};
use std::os::unix::fs::MetadataExt;
use std::os::unix::fs::PermissionsExt;
use users::get_group_by_gid;
use users::get_user_by_uid;
use std::env;
use std::error::Error;
use std::process;
use std::path::Path;
use std::net::{TcpStream, Shutdown};
use std::io::{self, BufRead, BufReader, Read, Write, Seek};
use std::thread;
use std::collections::HashMap;
use rusqlite::{params, Connection, Result};
use notify::{RecommendedWatcher, RecursiveMode, Watcher, Event, Config, Result as NotifyResult};
use notify::event::{EventKind, MetadataKind};
use std::sync::mpsc::channel;
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};
use serde::{Serialize, Deserialize};
use serde_json::{json, Value};
use rmp_serde::{from_read, Deserializer, Serializer, to_vec_named};
use rmp_serde::decode::from_slice;

#[derive(Serialize)]
struct NotifyEvent {
	kind: String,
	paths: Vec<String>
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

impl From<Event> for NotifyEvent {
	fn from(event: Event) -> Self {
		NotifyEvent {
			kind: format!("{:?}", event.kind),
			paths: event.paths.into_iter().map(|p| p.to_string_lossy().into_owned()).collect()
			}
		}
	}

const VER: &str = "0.0.1";
const CFGPATH: &str = "/opt/Luminum/LuminumClient/modules/integrity/integrity.conf.db";
const IMLOGS: &str = "/opt/Luminum/LuminumClient/modules/integrity/imlogs.db";

fn main() {
	let mut stream = TcpStream::connect("127.0.0.1:10461").expect("Error: Could not connect to Luminum Client process");
	
	if !file_exists(CFGPATH) {
		let lumycontent = LumyContent {
			action: String::from("newconfig"),
			data: None
			};
		let lumymsg = LumyMessage {
			lumy: String::from("Integrity"),
			version: String::from(VER),
			content: lumycontent
			};
		let clientmsg: Option<LumyMessage> = match client_send(stream, lumymsg) {
			Ok(response) => Some(response),
			Err(err) => {
				println!("Error: Unable to send message to Luminum Client process");
				None
				}
			};

		let response = clientmsg.unwrap();
		println!("{:?}",response);

		if response.content.action == "setconfig" {
			let confconn = Connection::open(CFGPATH).expect("Error: Could not open configuration database.");
			confconn.execute("create table if not exists WATCH ( PATH text not null )",[]).expect("Error: Could not create WATCH table in Integrity Lumy configuration database");
			for value in response.content.data.unwrap() { confconn.execute("insert into WATCH (PATH) values (?)", [&value]).expect("Error: Could not insert watch list values into Lumy configuration"); }
			confconn.close().unwrap();
			}
		}

	if is_inotify_enabled() {
		let (tx, rx) = channel();
		let mut watcher: RecommendedWatcher = RecommendedWatcher::new(tx, Config::default()).expect("Error: Could not set up watcher.");

		let watchpaths = get_config("watch");
		let ignorepaths = get_config("ignore");

		for watchpath in watchpaths {
			println!("{:?}",watchpath);
			watcher.watch(Path::new(&watchpath), RecursiveMode::Recursive);
			}

		//for ignorepath in ignorepaths {
			
		loop {
			match rx.recv() {
				Ok(Ok(event)) => {
					println!("{:?}", event);
					let notify_event: NotifyEvent = event.clone().into();
					let mut combined_json = json!({});
					combined_json["notify_event"] = serde_json::to_value(&notify_event).unwrap();
					let json_event = serde_json::to_string(&combined_json).unwrap();
					if let Ok(metadata) = std::fs::metadata(&event.paths[0].clone()) {
						println!("{:?}",event.kind);
						println!("{:?}",metadata);
						println!("{:?}",event.paths);
                                        	let mut ftype = String::new();
						if metadata.is_dir() { ftype = "Directory".to_string() }
						else if metadata.is_file() {ftype = "File".to_string() }
						println!("{}",String::from(ftype));
						let permissions = metadata.permissions();
						let mode = permissions.mode();
						println!("{}",octal_to_symbolic(mode));
						let user = get_user_by_uid(metadata.uid()).map_or("Unknown".to_string(), |u| u.name().to_string_lossy().into_owned());
						let group = get_group_by_gid(metadata.gid()).map_or("Unknown".to_string(), |g| g.name().to_string_lossy().into_owned());
						println!("{}:{}",user,group);
						let file_size = metadata.len();
						println!("{} bytes",file_size);
						}
					else {
						println!("{:?}",event.kind);
						println!("{:?}",event.paths);
						}
					}
				Ok(Err(e)) => println!("Watch error: {:?}", e),
				Err(e) => {
					println!("Error: {:?}",e);
					}
				}
			}
		}
	}

fn client_send(mut stream: TcpStream, message: LumyMessage) -> Result<LumyMessage, Box<dyn Error>> {
	let serialized_data = to_vec_named(&message).expect("Error: Unable to serialize data to Luminum Client");
	stream.write_all(&serialized_data).expect("Error: Unable to send message to Luminum Client process");
	println!("Sent: {:?}",message);

	let mut buffer = Vec::new();
	stream.read_to_end(&mut buffer);
	let mut deserializer = Deserializer::new(&buffer[..]);
	let response: LumyMessage = Deserialize::deserialize(&mut deserializer)?;
	println!("Received: {:?}",response);
	Ok(response)
	}

fn get_config(list: &str) -> Vec<String> {
	if list.to_string() == "watch" {
		let confconn = Connection::open(CFGPATH).expect("Error: Could not open configuration database.");
		let mut stmt = confconn.prepare("select PATH from WATCH").expect("Failed to prepare query");
		let watchpaths: Vec<String> = stmt.query_map([], |row| row.get(0)).expect("Failed to execute query").map(|result| result.expect("Error retrieving column value")).collect();
		//confconn.close().unwrap();
		watchpaths
		}
	else if list.to_string() == "ignore" {
		let ignorepaths: Vec<String> = Vec::new();

		ignorepaths
		}
	else {
		Vec::new()
		}
	}

fn save_event() {
	let imlogsconn = Connection::open(IMLOGS).expect("Error: Could not open events database.");
	imlogsconn.execute("create table if not exists EVENTS (`DATE` datetime not null, `TYPE` tinytext not null, `PATH` text not null, `PERMS` tinytext not null, `CHANGE` tinytext not null)",[]).expect("Error: Could not create EVENTS table in Integrity Lumy database");
	imlogsconn.execute("insert into EVENTS (DATE) values (CURRENT_TIMESTAMP)",[]).expect("Error: Could not save event to Integrity Lumy database");
	imlogsconn.close().unwrap();
	}

fn is_inotify_enabled() -> bool {
	fs::metadata("/proc/sys/fs/inotify").is_ok()
	}

fn file_exists(path: &str) -> bool {
        fs::metadata(path).is_ok()
        }

fn octal_to_symbolic(octal: u32) -> String {
	let mut result = String::new();

	result.push(if (octal & 0o400) != 0 { 'r' } else { '-' });
	result.push(if (octal & 0o200) != 0 { 'w' } else { '-' });
	result.push(if (octal & 0o100) != 0 { 'x' } else { '-' });

	// Group permissions
	result.push(if (octal & 0o040) != 0 { 'r' } else { '-' });
	result.push(if (octal & 0o020) != 0 { 'w' } else { '-' });
	result.push(if (octal & 0o010) != 0 { 'x' } else { '-' });

	// Other permissions
	result.push(if (octal & 0o004) != 0 { 'r' } else { '-' });
	result.push(if (octal & 0o002) != 0 { 'w' } else { '-' });
	result.push(if (octal & 0o001) != 0 { 'x' } else { '-' });
	result
	}
