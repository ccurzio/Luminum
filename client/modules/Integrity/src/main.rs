use notify::{RecommendedWatcher, RecursiveMode, Watcher, Config, Result};
use std::sync::mpsc::channel;
use std::path::PathBuf;

fn main() -> Result<()> {
	let (tx, rx) = channel();
	let mut watcher: RecommendedWatcher = Watcher::new(tx, Config::default())?;

	let path = PathBuf::from("/Users/ccurzio");

	watcher.watch(&path, RecursiveMode::Recursive);

	loop {
		match rx.recv() {
			Ok(event) => println!("Event: {:?}",event),
			Err(e) => println!("Error: {:?}",e)
			}
		}
	}
