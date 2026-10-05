//! Reads the apps in the Dock, and their badges, through the Accessibility API.
//!
//! The Dock exposes every icon as an accessibility element. App icons carry
//! the badge text in `AXStatusLabel`, which is the only public way to see
//! another app's badge.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use core_foundation::array::CFArray;
use core_foundation::base::{CFType, TCFType};
use core_foundation::boolean::CFBoolean;
use core_foundation::dictionary::CFDictionary;
use core_foundation::string::CFString;
use core_foundation::url::CFURL;
use core_foundation_sys::bundle::CFBundleCopyInfoDictionaryInDirectory;
use serde::Serialize;

use crate::ax::{self, Element};
use crate::badge::Badge;

const DOCK_EXECUTABLE: &str = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock";
const APP_ITEM_SUBROLE: &str = "AXApplicationDockItem";

/// How long to wait before looking again for the bundle id of an app whose
/// `Info.plist` could not be read (it may be mid-update).
const BUNDLE_ID_RETRY: Duration = Duration::from_secs(30);

/// An app icon in the Dock.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DockItem {
    pub name: String,
    pub path: Option<String>,
    pub bundle_id: Option<String>,
    pub running: bool,
    pub badge: Option<Badge>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DockError {
    /// The user has not granted Accessibility access.
    NotTrusted,
    /// The Dock is not running or did not answer (it may be restarting).
    Unavailable,
}

/// Reads the Dock, keeping the connection and bundle id lookups between reads.
///
/// Holds CoreFoundation objects, so a reader stays on the thread that made it.
pub struct DockReader {
    dock: Option<Element>,
    attributes: CFArray<CFString>,
    bundle_ids: HashMap<String, BundleIdLookup>,
}

struct BundleIdLookup {
    bundle_id: Option<String>,
    at: Instant,
}

impl Default for DockReader {
    fn default() -> Self {
        Self::new()
    }
}

impl DockReader {
    pub fn new() -> DockReader {
        // Order matters: `read_item` indexes the values by position.
        let attributes = ["AXSubrole", "AXTitle", "AXURL", "AXIsApplicationRunning", "AXStatusLabel"]
            .map(CFString::from_static_string);
        DockReader {
            dock: None,
            attributes: CFArray::from_CFTypes(&attributes),
            bundle_ids: HashMap::new(),
        }
    }

    /// The app icons currently in the Dock, in Dock order.
    pub fn read(&mut self) -> Result<Vec<DockItem>, DockError> {
        if !ax::is_trusted(false) {
            self.dock = None;
            return Err(DockError::NotTrusted);
        }
        // A cached connection goes stale when the Dock restarts, so allow one reconnect.
        for _ in 0..2 {
            if self.dock.is_none() {
                self.dock = find_dock_pid().and_then(Element::application);
            }
            let Some(dock) = self.dock.take() else {
                return Err(DockError::Unavailable);
            };
            if let Some(items) = self.read_items(&dock) {
                self.dock = Some(dock);
                return Ok(items);
            }
        }
        Err(DockError::Unavailable)
    }

    fn read_items(&mut self, dock: &Element) -> Option<Vec<DockItem>> {
        let mut items = Vec::new();
        // The Dock's only child is the list holding its icons.
        for list in dock.children().ok()? {
            for element in list.children().ok()? {
                if let Some(item) = self.read_item(&element) {
                    items.push(item);
                }
            }
        }
        Some(items)
    }

    fn read_item(&mut self, element: &Element) -> Option<DockItem> {
        let values = element.attributes(&self.attributes).ok()?;
        let [subrole, title, url, running, status_label] = values.as_slice() else {
            return None;
        };
        if string(subrole)? != APP_ITEM_SUBROLE {
            return None;
        }

        let path = url
            .downcast::<CFURL>()
            .and_then(|url| url.to_path())
            .map(|path| path.to_string_lossy().trim_end_matches('/').to_string());
        let bundle_id = path.as_deref().and_then(|path| self.bundle_id(path));

        Some(DockItem {
            name: string(title).unwrap_or_default(),
            path,
            bundle_id,
            running: running.downcast::<CFBoolean>().is_some_and(bool::from),
            badge: string(status_label).as_deref().and_then(Badge::parse),
        })
    }

    fn bundle_id(&mut self, path: &str) -> Option<String> {
        let now = Instant::now();
        if let Some(lookup) = self.bundle_ids.get(path)
            && (lookup.bundle_id.is_some() || now.duration_since(lookup.at) < BUNDLE_ID_RETRY)
        {
            return lookup.bundle_id.clone();
        }
        let bundle_id = read_bundle_id(path);
        let lookup = BundleIdLookup { bundle_id: bundle_id.clone(), at: now };
        self.bundle_ids.insert(path.to_string(), lookup);
        bundle_id
    }
}

fn string(value: &CFType) -> Option<String> {
    value.downcast::<CFString>().map(|s| s.to_string())
}

fn read_bundle_id(bundle_path: &str) -> Option<String> {
    let url = CFURL::from_path(bundle_path, true)?;
    let info: CFDictionary<CFString, CFType> = unsafe {
        let info = CFBundleCopyInfoDictionaryInDirectory(url.as_concrete_TypeRef());
        if info.is_null() {
            return None;
        }
        CFDictionary::wrap_under_create_rule(info)
    };
    let bundle_id = info.find(CFString::from_static_string("CFBundleIdentifier"))?;
    string(&bundle_id)
}

/// The pid of the current user's Dock, if it is running.
fn find_dock_pid() -> Option<libc::pid_t> {
    let uid = unsafe { libc::getuid() };
    all_pids()
        .into_iter()
        .find(|&pid| pid > 0 && owner(pid) == Some(uid) && executable(pid).as_deref() == Some(DOCK_EXECUTABLE))
}

fn all_pids() -> Vec<libc::pid_t> {
    // With no buffer this returns the number of processes; leave headroom for
    // ones that start between the two calls.
    let count = unsafe { libc::proc_listallpids(std::ptr::null_mut(), 0) };
    if count <= 0 {
        return Vec::new();
    }
    let mut pids = vec![0 as libc::pid_t; count as usize + 32];
    let bytes = (pids.len() * size_of::<libc::pid_t>()) as libc::c_int;
    let filled = unsafe { libc::proc_listallpids(pids.as_mut_ptr().cast(), bytes) };
    pids.truncate(filled.max(0) as usize);
    pids
}

fn owner(pid: libc::pid_t) -> Option<libc::uid_t> {
    let mut info = std::mem::MaybeUninit::<libc::proc_bsdshortinfo>::zeroed();
    let size = size_of::<libc::proc_bsdshortinfo>() as libc::c_int;
    let filled = unsafe {
        libc::proc_pidinfo(pid, libc::PROC_PIDT_SHORTBSDINFO, 0, info.as_mut_ptr().cast(), size)
    };
    (filled == size).then(|| unsafe { info.assume_init() }.pbsi_uid)
}

fn executable(pid: libc::pid_t) -> Option<String> {
    let mut buffer = [0u8; libc::PROC_PIDPATHINFO_MAXSIZE as usize];
    let len = unsafe { libc::proc_pidpath(pid, buffer.as_mut_ptr().cast(), buffer.len() as u32) };
    (len > 0).then(|| String::from_utf8_lossy(&buffer[..len as usize]).into_owned())
}
