//! Chime core.
//!
//! Reads notification badges off the macOS Dock through the Accessibility API
//! and tracks them for a configurable set of apps. The Swift app owns all UI
//! and drives this crate through the C ABI in [`ffi`] (see `include/chime_core.h`).

mod ax;
pub mod badge;
pub mod config;
pub mod dock;
pub mod ffi;
pub mod monitor;
