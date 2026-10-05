//! The C ABI the Swift app links against. Keep in sync with `include/chime_core.h`.
//!
//! Structured data crosses the boundary as UTF-8 JSON. Strings returned to the
//! caller are owned by it and must be released with [`chime_string_free`].

use std::ffi::{CStr, CString, c_char, c_void};
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

use crate::ax;
use crate::config::Config;
use crate::dock::DockReader;
use crate::monitor::{Monitor, State};

/// Receives the state as JSON. The string is only valid during the call.
pub type StateCallback = unsafe extern "C" fn(state_json: *const c_char, context: *mut c_void);

struct Core {
    config: Config,
    config_path: PathBuf,
    monitor: Monitor,
}

static CORE: Mutex<Option<Core>> = Mutex::new(None);

fn core() -> MutexGuard<'static, Option<Core>> {
    CORE.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// The caller's callback context, moved onto the monitor thread.
struct Context(*mut c_void);

// SAFETY: the pointer is opaque to this crate and only ever handed back to the
// callback; `chime_start` requires the caller to make that thread-safe.
unsafe impl Send for Context {}

impl Context {
    // A method, so that closures capture the whole `Send` wrapper, not its field.
    fn pointer(&self) -> *mut c_void {
        self.0
    }
}

fn into_c_string(text: String) -> *mut c_char {
    CString::new(text).map_or(std::ptr::null_mut(), CString::into_raw)
}

/// Loads the config at `config_path` and starts watching the Dock.
///
/// `callback` is invoked on a background thread with the state of the tracked
/// apps: once right away, then on every change. Returns false if the core is
/// already running or an argument is invalid.
///
/// # Safety
/// `config_path` must be a valid NUL-terminated UTF-8 string. `callback` and
/// `context` must be safe to use from another thread until `chime_stop` returns.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn chime_start(
    config_path: *const c_char,
    callback: Option<StateCallback>,
    context: *mut c_void,
) -> bool {
    let Some(callback) = callback else { return false };
    if config_path.is_null() {
        return false;
    }
    let Ok(config_path) = unsafe { CStr::from_ptr(config_path) }.to_str() else {
        return false;
    };

    let mut core = core();
    if core.is_some() {
        return false;
    }
    let config_path = PathBuf::from(config_path);
    let config = Config::load(&config_path);
    let context = Context(context);
    let monitor = Monitor::start(&config, move |state: &State| {
        let Ok(json) = CString::new(serde_json::to_string(state).expect("state serializes")) else {
            return;
        };
        unsafe { callback(json.as_ptr(), context.pointer()) };
    });
    *core = Some(Core { config, config_path, monitor });
    true
}

/// Stops watching. The callback is never invoked after this returns.
#[unsafe(no_mangle)]
pub extern "C" fn chime_stop() {
    // Release the lock before joining the monitor thread in `Monitor::drop`.
    let stopped = core().take();
    drop(stopped);
}

/// The current config as JSON, or NULL if the core is not running.
#[unsafe(no_mangle)]
pub extern "C" fn chime_config_get() -> *mut c_char {
    match core().as_ref() {
        Some(core) => into_c_string(core.config.to_json()),
        None => std::ptr::null_mut(),
    }
}

/// Replaces the config, saves it and applies it to the running monitor.
///
/// Returns false, leaving the config untouched, if the JSON is invalid or the
/// core is not running. A failed save still applies the config for this session.
///
/// # Safety
/// `config_json` must be a valid NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn chime_config_set(config_json: *const c_char) -> bool {
    if config_json.is_null() {
        return false;
    }
    let Ok(json) = unsafe { CStr::from_ptr(config_json) }.to_str() else {
        return false;
    };
    let Ok(config) = Config::from_json(json) else {
        return false;
    };
    let mut core = core();
    let Some(core) = core.as_mut() else { return false };

    core.monitor.update(&config);
    let saved = config.save(&core.config_path);
    core.config = config;
    saved.is_ok()
}

/// Reads the Dock right away and reports the state even if nothing changed.
#[unsafe(no_mangle)]
pub extern "C" fn chime_refresh() {
    if let Some(core) = core().as_ref() {
        core.monitor.refresh();
    }
}

/// Every app in the Dock as a JSON array, or NULL if the Dock cannot be read
/// (no Accessibility access, or the Dock is not running).
#[unsafe(no_mangle)]
pub extern "C" fn chime_dock_snapshot() -> *mut c_char {
    match DockReader::new().read() {
        Ok(items) => into_c_string(serde_json::to_string(&items).expect("items serialize")),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Whether Accessibility access is granted. With `prompt`, macOS asks the user
/// for it (and lists the app in System Settings) if it is not.
#[unsafe(no_mangle)]
pub extern "C" fn chime_accessibility_trusted(prompt: bool) -> bool {
    ax::is_trusted(prompt)
}

/// Releases a string returned by this library. NULL is ignored.
///
/// # Safety
/// `string` must come from this library and not have been freed already.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn chime_string_free(string: *mut c_char) {
    if !string.is_null() {
        drop(unsafe { CString::from_raw(string) });
    }
}
