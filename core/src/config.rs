//! The persisted configuration: which apps are tracked and how they are shown.

use std::fs;
use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};

pub const MIN_POLL_INTERVAL_MS: u64 = 250;
pub const MAX_POLL_INTERVAL_MS: u64 = 10_000;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Config {
    pub version: u32,
    pub apps: Vec<TrackedApp>,
    pub settings: Settings,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            version: 1,
            apps: Vec::new(),
            settings: Settings::default(),
        }
    }
}

/// An app whose Dock badge is mirrored into the menu bar.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackedApp {
    pub bundle_id: String,
    pub name: String,
    /// Where the app bundle was when it was added. Only a fallback: apps are
    /// matched by bundle id so they survive being moved or updated.
    pub path: String,
    /// Keep the app in the menu bar even when it has no badge.
    #[serde(default)]
    pub always_show: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub badge_style: BadgeStyle,
    pub monochrome: bool,
    pub show_menu_icon: bool,
    /// Bring a menu bar that hides automatically into view while there are notifications.
    pub reveal_menu_bar: bool,
    pub poll_interval_ms: u64,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            badge_style: BadgeStyle::Pill,
            monochrome: false,
            show_menu_icon: true,
            reveal_menu_bar: false,
            poll_interval_ms: 1_000,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BadgeStyle {
    /// A red pill with the count, overlapping the icon like in the Dock.
    #[default]
    Pill,
    /// The count as plain menu bar text next to the icon.
    Number,
    /// A red dot with no count.
    Dot,
}

impl Config {
    /// Parses a config and brings it into a valid state.
    pub fn from_json(json: &str) -> serde_json::Result<Config> {
        let mut config: Config = serde_json::from_str(json)?;
        config.normalize();
        Ok(config)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).expect("config serializes")
    }

    /// Loads the config at `path`. A missing file is a fresh install; an
    /// unreadable one is set aside as `<name>.bak` so nothing is lost silently.
    pub fn load(path: &Path) -> Config {
        let Ok(json) = fs::read_to_string(path) else {
            return Config::default();
        };
        Config::from_json(&json).unwrap_or_else(|_| {
            let _ = fs::copy(path, path.with_extension("json.bak"));
            Config::default()
        })
    }

    /// Writes the config atomically, creating the parent directory if needed.
    pub fn save(&self, path: &Path) -> io::Result<()> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, self.to_json())?;
        fs::rename(&tmp, path)
    }

    fn normalize(&mut self) {
        let mut seen: Vec<String> = Vec::new();
        self.apps.retain(|app| {
            let key = app.bundle_id.to_ascii_lowercase();
            if key.is_empty() || seen.contains(&key) {
                return false;
            }
            seen.push(key);
            true
        });
        self.settings.poll_interval_ms = self
            .settings
            .poll_interval_ms
            .clamp(MIN_POLL_INTERVAL_MS, MAX_POLL_INTERVAL_MS);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(bundle_id: &str) -> TrackedApp {
        TrackedApp {
            bundle_id: bundle_id.into(),
            name: bundle_id.into(),
            path: format!("/Applications/{bundle_id}.app"),
            always_show: false,
        }
    }

    #[test]
    fn empty_json_is_the_default_config() {
        assert_eq!(Config::from_json("{}").unwrap(), Config::default());
    }

    #[test]
    fn missing_fields_fall_back_to_defaults() {
        let config = Config::from_json(
            r#"{"apps":[{"bundleId":"com.apple.mail","name":"Mail","path":"/x/Mail.app"}],
                "settings":{"badgeStyle":"dot"}}"#,
        )
        .unwrap();
        assert!(!config.apps[0].always_show);
        assert_eq!(config.settings.badge_style, BadgeStyle::Dot);
        assert!(config.settings.show_menu_icon);
        assert!(!config.settings.reveal_menu_bar);
        assert_eq!(config.settings.poll_interval_ms, 1_000);
    }

    #[test]
    fn normalize_drops_duplicates_and_clamps_interval() {
        let mut config = Config {
            apps: vec![app("com.a"), app("COM.A"), app(""), app("com.b")],
            ..Config::default()
        };
        config.settings.poll_interval_ms = 1;
        let config = Config::from_json(&config.to_json()).unwrap();
        let ids: Vec<_> = config.apps.iter().map(|a| a.bundle_id.as_str()).collect();
        assert_eq!(ids, ["com.a", "com.b"]);
        assert_eq!(config.settings.poll_interval_ms, MIN_POLL_INTERVAL_MS);
    }

    #[test]
    fn save_and_load_round_trip() {
        let dir = std::env::temp_dir().join(format!("chime-test-{}", std::process::id()));
        let path = dir.join("nested").join("config.json");
        let mut config = Config {
            apps: vec![app("com.a")],
            ..Config::default()
        };
        config.settings.monochrome = true;

        config.save(&path).unwrap();
        assert_eq!(Config::load(&path), config);

        fs::write(&path, "not json").unwrap();
        assert_eq!(Config::load(&path), Config::default());
        assert_eq!(
            fs::read_to_string(path.with_extension("json.bak")).unwrap(),
            "not json"
        );
        fs::remove_dir_all(dir).unwrap();
    }
}
