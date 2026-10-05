// C interface to the Chime core (Rust). Keep in sync with core/src/ffi.rs.
//
// Structured data crosses the boundary as UTF-8 JSON. Strings returned by the
// library are owned by the caller and must be released with chime_string_free.

#ifndef CHIME_CORE_H
#define CHIME_CORE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Receives the state of the tracked apps as JSON. Called on a background
/// thread; the string is only valid during the call.
typedef void (*chime_state_callback)(const char *_Nonnull state_json, void *_Nullable context);

/// Loads the config at `config_path` and starts watching the Dock. The callback
/// fires once right away, then on every change. Returns false if the core is
/// already running or an argument is invalid.
bool chime_start(const char *_Nonnull config_path,
                 chime_state_callback _Nonnull callback,
                 void *_Nullable context);

/// Stops watching. The callback is never invoked after this returns.
void chime_stop(void);

/// The current config as JSON, or NULL if the core is not running.
char *_Nullable chime_config_get(void);

/// Replaces the config, saves it and applies it to the running monitor.
/// Returns false, leaving the config untouched, if the JSON is invalid or the
/// core is not running. A failed save still applies the config for this session.
bool chime_config_set(const char *_Nonnull config_json);

/// Reads the Dock right away and reports the state even if nothing changed.
void chime_refresh(void);

/// Every app in the Dock as a JSON array, or NULL if the Dock cannot be read
/// (no Accessibility access, or the Dock is not running).
char *_Nullable chime_dock_snapshot(void);

/// Whether Accessibility access is granted. With `prompt`, macOS asks the user
/// for it (and lists the app in System Settings) if it is not.
bool chime_accessibility_trusted(bool prompt);

/// Releases a string returned by this library. NULL is ignored.
void chime_string_free(char *_Nullable string);

#ifdef __cplusplus
}
#endif

#endif
