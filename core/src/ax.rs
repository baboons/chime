//! Minimal safe wrappers over the macOS Accessibility (AX) C API.

use std::ffi::c_void;

use core_foundation::array::{CFArray, CFArrayRef};
use core_foundation::base::{CFType, CFTypeRef, TCFType};
use core_foundation::boolean::CFBoolean;
use core_foundation::dictionary::{CFDictionary, CFDictionaryRef};
use core_foundation::string::{CFString, CFStringRef};

type AXUIElementRef = *const c_void;

/// A raw `AXError` code other than `kAXErrorSuccess`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AxError(pub i32);

const AX_SUCCESS: i32 = 0;

/// How long a single AX request may block before giving up. The Dock answers
/// in well under a millisecond; this only matters when it is hung or restarting.
const MESSAGING_TIMEOUT_SECS: f32 = 1.0;

#[link(name = "ApplicationServices", kind = "framework")]
unsafe extern "C" {
    static kAXTrustedCheckOptionPrompt: CFStringRef;

    safe fn AXIsProcessTrusted() -> u8;
    fn AXIsProcessTrustedWithOptions(options: CFDictionaryRef) -> u8;
    fn AXUIElementCreateApplication(pid: libc::pid_t) -> AXUIElementRef;
    fn AXUIElementSetMessagingTimeout(element: AXUIElementRef, timeout_secs: f32) -> i32;
    fn AXUIElementCopyAttributeValue(
        element: AXUIElementRef,
        attribute: CFStringRef,
        value: *mut CFTypeRef,
    ) -> i32;
    fn AXUIElementCopyMultipleAttributeValues(
        element: AXUIElementRef,
        attributes: CFArrayRef,
        options: u32,
        values: *mut CFArrayRef,
    ) -> i32;
}

/// Whether this process may use the Accessibility API. With `prompt`, macOS
/// shows its "would like to control this computer" dialog if it may not.
pub fn is_trusted(prompt: bool) -> bool {
    if !prompt {
        return AXIsProcessTrusted() != 0;
    }
    unsafe {
        let key = CFString::wrap_under_get_rule(kAXTrustedCheckOptionPrompt);
        let options = CFDictionary::from_CFType_pairs(&[(key, CFBoolean::true_value())]);
        AXIsProcessTrustedWithOptions(options.as_concrete_TypeRef()) != 0
    }
}

/// An accessibility element in another process.
pub struct Element(CFType);

impl Element {
    /// The top-level element of the application with the given pid.
    pub fn application(pid: libc::pid_t) -> Option<Element> {
        unsafe {
            let raw = AXUIElementCreateApplication(pid);
            if raw.is_null() {
                return None;
            }
            AXUIElementSetMessagingTimeout(raw, MESSAGING_TIMEOUT_SECS);
            Some(Element(CFType::wrap_under_create_rule(raw)))
        }
    }

    pub fn attribute(&self, name: &CFString) -> Result<CFType, AxError> {
        let mut value: CFTypeRef = std::ptr::null();
        let status = unsafe {
            AXUIElementCopyAttributeValue(
                self.0.as_CFTypeRef(),
                name.as_concrete_TypeRef(),
                &mut value,
            )
        };
        if status != AX_SUCCESS || value.is_null() {
            return Err(AxError(status));
        }
        Ok(unsafe { CFType::wrap_under_create_rule(value) })
    }

    /// Several attributes in one round trip. The result has one entry per
    /// requested name; attributes the element lacks come back as placeholder
    /// values that fail every `downcast`.
    pub fn attributes(&self, names: &CFArray<CFString>) -> Result<Vec<CFType>, AxError> {
        let mut values: CFArrayRef = std::ptr::null();
        let status = unsafe {
            AXUIElementCopyMultipleAttributeValues(
                self.0.as_CFTypeRef(),
                names.as_concrete_TypeRef(),
                0,
                &mut values,
            )
        };
        if status != AX_SUCCESS || values.is_null() {
            return Err(AxError(status));
        }
        let values = unsafe { CFArray::<CFType>::wrap_under_create_rule(values) };
        Ok(values.iter().map(|value| value.clone()).collect())
    }

    pub fn children(&self) -> Result<Vec<Element>, AxError> {
        let children = self
            .attribute(&CFString::from_static_string("AXChildren"))?
            .downcast_into::<CFArray>()
            .ok_or(AxError(AX_SUCCESS))?;
        Ok(children
            .iter()
            .map(|child| Element(unsafe { CFType::wrap_under_get_rule(*child) }))
            .collect())
    }
}
