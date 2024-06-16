use std::fs::{self, File};
use std::env;
use std::process;
use std::path::Path;
use std::net::{TcpStream, Shutdown};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::thread;
use std::collections::HashMap;
use notify::{RecommendedWatcher, RecursiveMode, Watcher, Event, Config, Result};
use serde::Serialize;
use serde_json::{json, to_value, Value};
use std::sync::mpsc::channel;
use std::time::Duration;

#[derive(Serialize)]
struct NotifyEvent {
	kind: String,
	paths: Vec<String>
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

fn main() -> Result<()> {
	let mut lumyconfig: HashMap<String, String> = HashMap::new();
	if !file_exists(CFGPATH) {
		println!("Fatal: The Integrity Lumy configuration is missing.");
		process::exit(1);
		}

	let mut stream = TcpStream::connect("127.0.0.1:10461").expect("Error: Could not connect to Luminum Client process");
	let mut combined_json = json!({});
	combined_json["product"] = serde_json::to_value("Luminum Integrity").unwrap();
	combined_json["version"] = serde_json::to_value(VER).unwrap();
	combined_json["content"]["status"] = serde_json::to_value("running").unwrap();
	let json_event = serde_json::to_string(&combined_json).unwrap();
	stream.write_all(&json_event.as_bytes());

	if is_inotify_enabled() {
		let (tx, rx) = channel();
		let mut watcher: RecommendedWatcher = RecommendedWatcher::new(tx, Config::default())?;

		let watchpaths = vec![ "/usr", "/usr/bin" ];

		for watchpath in watchpaths {
			watcher.watch(Path::new(watchpath), RecursiveMode::Recursive)?;
			}

		loop {
			match rx.recv() {
				Ok(Ok(event)) => {
					// TODO: Can't have hard-coded port. Need to save in client config and pass to modules in their own configs
					let notify_event: NotifyEvent = event.into();
					let eijson = json!({"dtype":"inotify"});
					let event_info: Value = serde_json::to_value(eijson).unwrap();
					let mut combined_json = json!({});
					combined_json["product"] = serde_json::to_value("Luminum Integrity").unwrap();
					combined_json["content"]["notify_event"] = serde_json::to_value(&notify_event).unwrap();
					combined_json["content"]["event_info"] = event_info;
					let json_event = serde_json::to_string(&combined_json).unwrap();
					stream.write_all(&json_event.as_bytes());
					println!("{}", json_event);
					}
				Ok(Err(e)) => println!("Watch error: {:?}", e),
				Err(e) => {
					println!("Error: {:?}",e);
					}
				}
			}
		stream.shutdown(Shutdown::Write);
		}
	else {
		Ok(())
		}
	}

fn is_inotify_enabled() -> bool {
	fs::metadata("/proc/sys/fs/inotify").is_ok()
	}

fn file_exists(path: &str) -> bool {
        fs::metadata(path).is_ok()
        }
