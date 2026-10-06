# How an app shows up in Chime

Chime has nothing to link against. An app shows up in it through three things,
and either of the first two is enough:

- [The badge on its Dock icon](#the-dock-badge) says when it has notifications.
- [An item it sends Chime](#sending-chime-an-item) says what they are about, as
  a title that Chime shows next to the app's icon. An item shows the app by
  itself, with or without a badge.
- [The title of its menu bar item](#the-apps-own-menu-bar-item) says the same
  for an app that sends nothing.

## The Dock badge

The badge is what tells Chime that an app has notifications. No badge means
none: the app leaves the floating indicator and, unless it is set to show
always, the menu bar. An app that [sent Chime an item](#sending-chime-an-item)
stays for as long as the item does.

| The badge says | Chime shows | Counts as |
| --- | --- | --- |
| `3` | `3` | 3 notifications |
| `1,234`, `1.234` or `1 234` | `1.2K` | 1,234 notifications |
| `1500000` | `1.5M` | 1,500,000 notifications |
| `99+`, `•`, `NEW` | the same | a badge without a count |
| `UPDATE` | `UPD…` | a badge without a count |
| nothing, or only spaces | no badge | no notifications |

- Text of up to four characters is shown as it is. Longer text is cut short.
- A notification arrives, which is when Chime can play its sound, when a badge
  appears or a count goes up. Text that changes into other text does not count.
- The app has to be in the Dock, running or pinned. An app without a Dock icon
  has no badge for Chime to read.
- Chime looks every 1, 2 or 5 seconds, as set under **Check for notifications**.

Setting it:

```swift
// AppKit and SwiftUI
NSApp.dockTile.badgeLabel = "3"   // nil takes it away
```

```rust
// Tauri 2
window.set_badge_count(Some(3))?;            // None takes it away
window.set_badge_label(Some("•".into()))?;   // any text
```

To see the badges as Chime reads them, from a terminal that has Accessibility
access:

```sh
cargo run --manifest-path core/Cargo.toml --example dock
```

## Sending Chime an item

An app can tell Chime what to show next to its icon in the floating indicator:
a title, as plain text or in a rounded box of a color, with an icon before it
if the app sends one.

It does so by posting a distributed notification named
`com.baboons.chime.item`, with the item as JSON in the notification's object:

```json
{"app": "com.example.app", "title": "Standup in 4:59", "color": "#1B6FDB", "icon": "video.fill"}
```

| Field | | |
| --- | --- | --- |
| `app` | required | The app's bundle identifier, as it is in its `Info.plist`. The app has to be running. |
| `title` | optional | What to show. An item without a title, or with an empty one, takes away what was shown. A title of more than 48 characters loses its middle. |
| `color` | optional | `#RRGGBB`. The title goes in a rounded box of this color, in black or white, whichever reads better on it. Without a color the title is plain text. |
| `icon` | optional | An icon to go before the title: the name of an SF Symbol, such as `video.fill`, or an image as a `data:` URL, such as `data:image/png;base64,…`. It is drawn in the color of the title, so only its shape counts. An image is drawn 14 points tall, and one of more than 64 KB is left out. |

- An item is enough for the app to be shown. For as long as it has one, the
  app is in the floating indicator with the item beside it, and in the menu
  bar, whether or not its Dock icon has a badge. So take the item away, by
  sending one with no title, when there is nothing more to say.
- Post again whenever the item changes. Chime shows the new one at once, so a
  countdown can be posted every second.
- Chime forgets the item when the app quits.
- Chime does not keep items when it quits itself. When it starts, it posts
  `com.baboons.chime.ready`; an app that listens for that can post its item again.
- An item takes the place of the title of the app's menu bar item, below.
- Sending needs no permission. The item is in the notification's object
  because a sandboxed app may not send user info.
- Chime cannot tell who posted an item, so any process can post one for any
  app. It only ever puts a title next to an app that the user added to Chime.

Posting it:

```swift
// Swift
let item = ##"{"app":"com.example.app","title":"Standup in 4:59","color":"#1B6FDB"}"##
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.baboons.chime.item"), object: item, userInfo: nil, deliverImmediately: true)
```

```rust
// Rust, with the objc2-foundation crate (0.3)
use objc2_foundation::{NSDistributedNotificationCenter, NSString};

let item = r##"{"app":"com.example.app","title":"Standup in 4:59","color":"#1B6FDB"}"##;
let center = NSDistributedNotificationCenter::defaultCenter();
// SAFETY: there is no user info to be of the wrong type.
unsafe {
    center.postNotificationName_object_userInfo_deliverImmediately(
        &NSString::from_str("com.baboons.chime.item"),
        Some(&NSString::from_str(item)),
        None,
        true,
    );
}
```

To try it from a terminal, for an app that is running and in Chime:

```sh
osascript -l JavaScript -e 'ObjC.import("Foundation")
$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(
  "com.baboons.chime.item",
  JSON.stringify({app: "com.example.app", title: "Standup in 4:59", color: "#1B6FDB"}),
  $(), true)'
```

## The app's own menu bar item

This part only matters to people who turned on **Use apps' own menu bar
items**. For them, an app that has an item in the menu bar is treated as being
there already:

- Chime adds no item of its own for the app.
- While the app has a badge, the floating indicator shows the title of the
  app's item after the app's icon and badge, unless the app sent an item of
  its own.

Chime finds the item by the app's bundle identifier, so it has to belong to
the app itself and not to a helper with an identifier of its own. If the app
has several items, Chime uses the first.

The title is the item's accessibility title. Chime reads it as often as it
checks for notifications, and twice a second while it is on show, so a title
that counts down keeps counting.

- An item that shows text has that text as its title, and needs nothing more.
- An item that draws its text into its image has no title. Give it one, as
  below, or send Chime an item.
- A title that is only the app's name is left out. The icon says that already.
- Chime does not read the item's tooltip or its accessibility label.

Setting a title that the item shows:

```swift
// AppKit
statusItem.button?.title = "Standup in 4:59"

// SwiftUI
MenuBarExtra {
    // the menu
} label: {
    Text("Standup in 4:59")
}
```

```rust
// Tauri 2
tray.set_title(Some("Standup in 4:59"))?;
```

Setting a title that the item does not show, for an item that is all image:

```swift
// AppKit
statusItem.button?.setAccessibilityTitle("Standup in 4:59")
```

Tauri has no call for that. Reach the `NSStatusItem` with
`TrayIcon::with_inner_tray_icon` and `ns_status_item()`, and send its button
`setAccessibilityTitle:`.

To see the title as Chime reads it, point Accessibility Inspector, which comes
with Xcode, at the item and look for **Title**.

## What Chime does not do

- It does not read notifications themselves, only that the badge is there.
- It does not click an app's menu bar item or open its menu. A click on an app
  in the indicator opens the app.
- It shows an item or a title in the floating indicator only, not in the menu bar.
