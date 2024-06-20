use std::fs::{self, File};
use std::env;
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
use serde::{Serialize, Deserialize};
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
	action: String
	}

impl From<Event> for NotifyEvent {
	fn from(event: Event) -> Self {
		NotifyEvent {
			kind: format!("{:?}", event.kind),
			paths: event.paths.into_iter().map(|p| p.to_string_lossy().into_owned()).collect(),
			}
		}
	}

const VER: &str = "0.0.1";
const CFGPATH: &str = "/opt/Luminum/LuminumClient/modules/integrity/integrity.conf.db";

fn main() {
	let mut lumyconfig: HashMap<String, String> = HashMap::new();

	if file_exists(CFGPATH) {
		}
	else {
		}

	if is_inotify_enabled() {
		let (tx, rx) = channel();

		let mut watcher: RecommendedWatcher = RecommendedWatcher::new(tx, Config::default()).expect("Error: Could not set up watcher.");
		let watchpaths = vec![ "/usr", "/usr/bin" ];

		for watchpath in watchpaths {
			watcher.watch(Path::new(watchpath), RecursiveMode::Recursive);
			}

		let mut stream = match TcpStream::connect("127.0.0.1:10461") {
			Ok(_) => {
				//println!("Connected to Luminum Client");
				}
			Err(err) => { 
				println!("Error: Could not connect to Luminum Client process: {}", err);
				}
			};

/*
		if !file_exists(CFGPATH) {
			let mut combined_json = json!({});
			combined_json["product"] = serde_json::to_value("Luminum Integrity").unwrap();
			combined_json["version"] = serde_json::to_value(VER).unwrap();
			combined_json["content"]["action"] = serde_json::to_value("config").unwrap();
			combined_json["content"]["info"] = serde_json::to_value("none").unwrap();
			let json_event = serde_json::to_string(&combined_json).unwrap();
			stream.write_all(&json_event.as_bytes());
			println!("{}",json_event);
			println!("Fatal: The Integrity Lumy configuration is missing.");
			process::exit(1);
			}
		else {
			let mut combined_json = json!({});
			combined_json["product"] = serde_json::to_value("Luminum Integrity").unwrap();
			combined_json["version"] = serde_json::to_value(VER).unwrap();
			combined_json["content"]["status"] = serde_json::to_value("running").unwrap();
			let json_event = serde_json::to_string(&combined_json).unwrap();
			stream.write_all(&json_event.as_bytes());
			}
*/
		loop {
			match rx.recv() {
				Ok(Ok(event)) => {
					/*
					let mut combined_json = json!({});
					let notify_event: NotifyEvent = event.into();
					let eijson = json!({"dtype":"inotify"});
					let event_info: Value = serde_json::to_value(eijson).unwrap();
					combined_json["product"] = serde_json::to_value("Luminum Integrity").unwrap();
					combined_json["content"]["notify_event"] = serde_json::to_value(&notify_event).unwrap();
					combined_json["content"]["event_info"] = serde_json::to_value(&event_info).unwrap();
					let json_event = serde_json::to_string(&combined_json).unwrap();
					//let json_event_with_newline = format!("{}\n", json_event);
					if let Err(e) = stream.write_all(json_event.as_bytes()) {
						eprintln!("Failed to send message: {}", e);
						break;
						}

					if let Err(e) = stream.flush() {
						eprintln!("Failed to flush stream: {}", e);
						break;
						}
					println!("{}", json_event);
					*/
					}
				Ok(Err(e)) => println!("Watch error: {:?}", e),
				Err(e) => {
					println!("Error: {:?}",e);
					}
				}
			continue;
			//stream.shutdown(Shutdown::Write);
			}
		}
	}

fn is_inotify_enabled() -> bool {
	fs::metadata("/proc/sys/fs/inotify").is_ok()
	}

fn file_exists(path: &str) -> bool {
        fs::metadata(path).is_ok()
        }
