extern crate pkg_config;

use std::path::PathBuf;
use notify::{RecommendedWatcher, RecursiveMode, Watcher, Config, Result};
use std::sync::mpsc::channel;

fn main() -> Result<()> {
	match pkg_config::probe_library("fsevent") {
		Ok(_) => {
			let (tx, rx) = channel();
			let mut watcher: RecommendedWatcher = Watcher::new(tx, Config::default())?;

			let path = PathBuf::from("/Users/ccurzio");

			let _ = watcher.watch(&path, RecursiveMode::Recursive);

			loop {
				match rx.recv() {
					Ok(event) => println!("Event: {:?}",event),
					Err(e) => println!("Error: {:?}",e)
					}
				}
			}
		Err(_) => {
			hashscan();
			}
		}
	Ok(())
	}

fn hashscan() {
	}
