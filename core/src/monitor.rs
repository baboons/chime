//! Watches the Dock on a background thread and reports badge changes.

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use serde::Serialize;

use crate::badge::Badge;
use crate::config::{Config, TrackedApp};
use crate::dock::{DockError, DockItem, DockReader};

/// What the menu bar needs to know: the badge of every tracked app.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct State {
    /// Whether Accessibility access has been granted.
    pub trusted: bool,
    /// One entry per tracked app, in config order.
    pub apps: Vec<AppStatus>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppStatus {
    pub bundle_id: String,
    pub running: bool,
    pub badge: Option<Badge>,
}

impl State {
    /// Looks up each tracked app in a Dock reading. Only apps in the Dock
    /// (pinned or running) can show a badge; the rest report none.
    pub fn resolve(apps: &[TrackedApp], dock: &Result<Vec<DockItem>, DockError>) -> State {
        let items = dock.as_deref().unwrap_or_default();
        let apps = apps
            .iter()
            .map(|app| {
                let item = items.iter().find(|item| is_same_app(app, item));
                AppStatus {
                    bundle_id: app.bundle_id.clone(),
                    running: item.is_some_and(|item| item.running),
                    badge: item.and_then(|item| item.badge.clone()),
                }
            })
            .collect();
        State {
            trusted: !matches!(dock, Err(DockError::NotTrusted)),
            apps,
        }
    }
}

/// Matches by bundle id, falling back to the bundle path for the rare app
/// whose id cannot be read.
fn is_same_app(app: &TrackedApp, item: &DockItem) -> bool {
    match &item.bundle_id {
        Some(bundle_id) => bundle_id.eq_ignore_ascii_case(&app.bundle_id),
        None => item.path.as_deref() == Some(app.path.trim_end_matches('/')),
    }
}

/// A running Dock watcher. Dropping it stops the thread.
pub struct Monitor {
    shared: Arc<Shared>,
    thread: Option<JoinHandle<()>>,
}

struct Shared {
    control: Mutex<Control>,
    wake: Condvar,
}

struct Control {
    apps: Vec<TrackedApp>,
    interval: Duration,
    /// Read the Dock now instead of waiting out the interval.
    wake: bool,
    /// Report the next reading even if nothing changed.
    force: bool,
    stop: bool,
}

impl Shared {
    fn control(&self) -> MutexGuard<'_, Control> {
        self.control.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

impl Monitor {
    /// Starts watching. `on_state` runs on the monitor thread: once right
    /// away, then whenever the state of the tracked apps changes.
    pub fn start(config: &Config, on_state: impl Fn(&State) + Send + 'static) -> Monitor {
        let shared = Arc::new(Shared {
            control: Mutex::new(Control {
                apps: config.apps.clone(),
                interval: interval(config),
                wake: false,
                force: false,
                stop: false,
            }),
            wake: Condvar::new(),
        });
        let thread = thread::Builder::new()
            .name("chime-monitor".into())
            .spawn({
                let shared = Arc::clone(&shared);
                move || run(&shared, on_state)
            })
            .expect("spawn monitor thread");
        Monitor { shared, thread: Some(thread) }
    }

    /// Applies a changed config and re-reads the Dock right away.
    pub fn update(&self, config: &Config) {
        let mut control = self.shared.control();
        control.apps = config.apps.clone();
        control.interval = interval(config);
        control.wake = true;
        self.shared.wake.notify_one();
    }

    /// Re-reads the Dock right away and reports the result even if unchanged.
    pub fn refresh(&self) {
        let mut control = self.shared.control();
        control.wake = true;
        control.force = true;
        self.shared.wake.notify_one();
    }
}

impl Drop for Monitor {
    fn drop(&mut self) {
        self.shared.control().stop = true;
        self.shared.wake.notify_one();
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

fn interval(config: &Config) -> Duration {
    Duration::from_millis(config.settings.poll_interval_ms)
}

fn run(shared: &Shared, on_state: impl Fn(&State)) {
    let mut reader = DockReader::new();
    let mut last: Option<State> = None;

    loop {
        let (apps, force) = {
            let mut control = shared.control();
            if control.stop {
                return;
            }
            control.wake = false;
            (control.apps.clone(), std::mem::take(&mut control.force))
        };

        // A panic must not silently end badge updates; skip this reading instead.
        match catch_unwind(AssertUnwindSafe(|| reader.read())) {
            // The Dock restarts now and then. Keep the last badges until it is
            // back rather than blinking every item out of the menu bar.
            Ok(Err(DockError::Unavailable)) if last.is_some() && !force => {}
            Ok(reading) => {
                let state = State::resolve(&apps, &reading);
                if force || last.as_ref() != Some(&state) {
                    on_state(&state);
                    last = Some(state);
                }
            }
            Err(_) => reader = DockReader::new(),
        }

        let control = shared.control();
        let interval = control.interval;
        let _unused = shared
            .wake
            .wait_timeout_while(control, interval, |control| !control.wake && !control.stop)
            .unwrap_or_else(|poisoned| poisoned.into_inner());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tracked(bundle_id: &str) -> TrackedApp {
        TrackedApp {
            bundle_id: bundle_id.into(),
            name: bundle_id.into(),
            path: format!("/Applications/{bundle_id}.app/"),
            always_show: false,
        }
    }

    fn docked(bundle_id: Option<&str>, path: &str, badge: &str) -> DockItem {
        DockItem {
            name: path.into(),
            path: Some(path.into()),
            bundle_id: bundle_id.map(Into::into),
            running: true,
            badge: Badge::parse(badge),
        }
    }

    #[test]
    fn resolves_tracked_apps_in_config_order() {
        let apps = [tracked("com.b"), tracked("com.a"), tracked("com.missing")];
        let dock = Ok(vec![
            docked(Some("com.a"), "/Applications/A.app", "3"),
            docked(Some("COM.B"), "/Applications/B.app", ""),
            docked(Some("com.untracked"), "/Applications/U.app", "9"),
        ]);

        let state = State::resolve(&apps, &dock);

        assert!(state.trusted);
        let summary: Vec<_> = state
            .apps
            .iter()
            .map(|app| (app.bundle_id.as_str(), app.running, app.badge.as_ref().map(|b| b.label.as_str())))
            .collect();
        assert_eq!(
            summary,
            [("com.b", true, None), ("com.a", true, Some("3")), ("com.missing", false, None)]
        );
    }

    #[test]
    fn falls_back_to_path_when_the_bundle_id_is_unknown() {
        let apps = [tracked("com.a")];
        let dock = Ok(vec![docked(None, "/Applications/com.a.app", "1")]);
        assert!(State::resolve(&apps, &dock).apps[0].badge.is_some());
    }

    #[test]
    fn dock_errors_clear_every_badge() {
        let apps = [tracked("com.a")];

        let state = State::resolve(&apps, &Err(DockError::NotTrusted));
        assert!(!state.trusted);
        assert_eq!(state.apps.len(), 1);
        assert!(!state.apps[0].running && state.apps[0].badge.is_none());

        let state = State::resolve(&apps, &Err(DockError::Unavailable));
        assert!(state.trusted && state.apps[0].badge.is_none());
    }

    #[test]
    fn monitor_reports_right_away_and_on_refresh_then_stops() {
        let config = Config { apps: vec![tracked("com.a")], ..Config::default() };
        let (sender, states) = std::sync::mpsc::channel();
        let monitor = Monitor::start(&config, move |state| sender.send(state.clone()).unwrap());
        let timeout = Duration::from_secs(10);

        let first = states.recv_timeout(timeout).expect("initial state");
        assert_eq!(first.apps.len(), 1);

        monitor.refresh();
        assert_eq!(states.recv_timeout(timeout).expect("state after refresh"), first);

        // Dropping joins the thread, which drops the callback and closes the channel.
        drop(monitor);
        assert!(states.recv().is_err());
    }
}
