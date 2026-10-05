//! Prints the apps in the Dock and their badges.
//!
//!     cargo run --example dock
//!
//! The terminal running this needs Accessibility access.

use chime_core::dock::{DockError, DockReader};

fn main() {
    match DockReader::new().read() {
        Ok(items) => {
            for item in items {
                let badge = item.badge.map_or("-".to_string(), |badge| badge.label);
                let bundle_id = item.bundle_id.as_deref().unwrap_or("?");
                let running = if item.running { "●" } else { " " };
                println!("{running} {badge:>6}  {:<28} {bundle_id}", item.name);
            }
        }
        Err(DockError::NotTrusted) => {
            eprintln!("No Accessibility access. Grant it to this terminal in");
            eprintln!("System Settings → Privacy & Security → Accessibility.");
            std::process::exit(1);
        }
        Err(DockError::Unavailable) => {
            eprintln!("The Dock is not running or did not answer.");
            std::process::exit(1);
        }
    }
}
