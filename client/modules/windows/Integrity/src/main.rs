// Luminum Integrity Lumy (Windows)
// by Christopher R. Curzio <ccurzio@luminum.net>

use std::path::PathBuf;
use notify::{RecommendedWatcher, RecursiveMode, Watcher, Config, Result};
use std::sync::mpsc::channel;

fn main() -> Result<()> {
	let (tx, rx) = channel();
	let mut watcher: RecommendedWatcher = Watcher::new(tx, Config::default())?;

	let path = PathBuf::from(".");

	let _ = watcher.watch(&path, RecursiveMode::Recursive);

	loop {
		match rx.recv() {
			Ok(event) => println!("Event: {:?}",event),
			Err(e) => println!("Error: {:?}",e)
			}
		}
	}

fn hashscan() {
	}
