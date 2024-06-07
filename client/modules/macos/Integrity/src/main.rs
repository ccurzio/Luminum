extern crate libc;
use std::path::Path;
use notify::{RecommendedWatcher, RecursiveMode, Watcher, Event, Config, Result};
use serde::Serialize;
use serde_json::json;
use std::sync::mpsc::channel;

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
	if !unsafe { libc::fopen("/System/Library/Frameworks/CoreServices.framework/Frameworks/FSEvents.framework/Headers/FSEvents.h\0".as_ptr() as *const _, "r\0".as_ptr() as *const _) }.is_null() {
		let (tx, rx) = channel();
		let mut watcher: RecommendedWatcher = RecommendedWatcher::new(tx, Config::default())?;

		let watchpaths = vec![ "/usr", "/usr/bin" ];

		for watchpath in watchpaths {
			watcher.watch(Path::new(watchpath), RecursiveMode::Recursive)?;
			}

		loop {
			match rx.recv() {
				Ok(Ok(event)) => {
					let notify_event: NotifyEvent = event.into();
					let event_info = json!({"dtype":"fsevents"});
					let mut combined_json = json!({});
					combined_json["notify_event"] = serde_json::to_value(&notify_event).unwrap();
					combined_json["event_info"] = event_info;
					let json_event = serde_json::to_string(&combined_json).unwrap();
					println!("{}", json_event);
					}
				Ok(Err(e)) => println!("Error: {:?}", e),
				Err(e) => println!("Error: {:?}",e)
				}
			}
		}
	else {
		Ok(())
		}
	}

fn hashscan() {
	}
