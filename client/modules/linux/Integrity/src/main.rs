use std::fs;
use std::path::Path;
use notify::{RecommendedWatcher, RecursiveMode, Watcher, Event, Config, Result};
use serde::Serialize;
use serde_json::{json, to_value, Value};
use std::sync::mpsc::channel;
use std::net::{TcpStream, Shutdown};
use std::io::Write;
use std::thread;
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

fn main() -> Result<()> {
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
					let mut stream = TcpStream::connect("127.0.0.1:10511").expect("Error: Could not connect to Luminum Client process");
					let notify_event: NotifyEvent = event.into();
					let eijson = json!({"dtype":"inotify"});
					let event_info: Value = serde_json::to_value(eijson).unwrap();
					let mut combined_json = json!({});
					combined_json["product"] = serde_json::to_value("Luminum Integrity").unwrap();
					combined_json["content"]["notify_event"] = serde_json::to_value(&notify_event).unwrap();
					combined_json["content"]["event_info"] = event_info;
					let json_event = serde_json::to_string(&combined_json).unwrap();
					stream.write_all(&json_event.as_bytes());
					stream.shutdown(Shutdown::Write);
					println!("{}", json_event);
					}
				Ok(Err(e)) => println!("Watch error: {:?}", e),
				Err(e) => {
					println!("Error: {:?}",e);
					}
				}
			}
		}
	else {
		Ok(())
		}
	}

fn is_inotify_enabled() -> bool {
	fs::metadata("/proc/sys/fs/inotify").is_ok()
	}
