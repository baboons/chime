import AppKit
import SwiftUI

/// Development aid: renders Chime with sample apps and badges into a PNG,
/// without reading the Dock or needing any permissions. `make screenshots`
/// uses it for the README images.
///
///     Chime --demo-snapshot <menu-bar|styles|settings> out.png [--light]
@MainActor
enum DemoSnapshot {
    private enum Scene: String, CaseIterable {
        /// A stretch of menu bar with the sample apps in it.
        case menuBar = "menu-bar"
        /// The same apps in each badge style.
        case styles
        /// The settings window.
        case settings
    }

    private struct Sample {
        let name: String
        let bundleId: String
        var badge: UInt64?
        var alwaysShow = false

        var app: TrackedApp {
            TrackedApp(bundleId: bundleId, name: name, path: "/System/Applications/\(name).app", alwaysShow: alwaysShow)
        }

        var status: AppStatus {
            let badge = badge.map { Badge(label: String($0), short: String($0), count: $0) }
            return AppStatus(bundleId: bundleId, running: true, badge: badge)
        }
    }

    // Apps that ship with macOS, so the icons exist on any Mac.
    private static let samples = [
        Sample(name: "Mail", bundleId: "com.apple.mail", badge: 3),
        Sample(name: "Messages", bundleId: "com.apple.MobileSMS", badge: 12),
        Sample(name: "Calendar", bundleId: "com.apple.iCal", badge: 1),
        Sample(name: "Reminders", bundleId: "com.apple.reminders", alwaysShow: true),
    ]

    private static var isDark = true
    private static var ink: NSColor { isDark ? .white : .black }

    /// Renders the scene named on the command line and exits. Returns only
    /// when no snapshot was asked for.
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--demo-snapshot") else { return }
        guard arguments.count > flag + 2, let scene = Scene(rawValue: arguments[flag + 1]) else {
            let scenes = Scene.allCases.map(\.rawValue).joined(separator: "|")
            FileHandle.standardError.write(Data("usage: Chime --demo-snapshot <\(scenes)> out.png [--light]\n".utf8))
            exit(64)
        }
        let output = URL(fileURLWithPath: arguments[flag + 2])
        isDark = !arguments.contains("--light")
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        let image = switch scene {
        case .menuBar: menuBar()
        case .styles: styles()
        case .settings: settings()
        }
        guard let png = image.representation(using: .png, properties: [:]), (try? png.write(to: output)) != nil else {
            FileHandle.standardError.write(Data("could not write \(output.path)\n".utf8))
            exit(1)
        }
        print("Wrote \(output.path) (\(image.pixelsWide)×\(image.pixelsHigh))")
        exit(0)
    }

    // MARK: Menu bar scenes

    private static func menuBar() -> NSBitmapImageRep {
        let strip = MenuBarStrip(style: .pill, showsExtras: true)
        return draw(strip.size) { strip.draw(at: .zero) }
    }

    private static func styles() -> NSBitmapImageRep {
        let variants: [(caption: String, strip: MenuBarStrip)] = [
            ("Badge", MenuBarStrip(style: .pill)),
            ("Number", MenuBarStrip(style: .number)),
            ("Dot", MenuBarStrip(style: .dot)),
            ("Monochrome", MenuBarStrip(style: .pill, monochrome: true)),
        ]
        let gap: CGFloat = 24
        let captionHeight: CGFloat = 26
        let width = variants.map(\.strip.size.width).reduce(0, +) + gap * CGFloat(variants.count - 1)

        return draw(NSSize(width: width, height: MenuBarStrip.height + captionHeight)) {
            var x: CGFloat = 0
            for (caption, strip) in variants {
                strip.draw(at: NSPoint(x: x, y: captionHeight))
                // The captions sit on the dark backdrop the README images get, whatever the appearance.
                let label = text(caption, font: .systemFont(ofSize: 11, weight: .medium), color: .white.withAlphaComponent(0.85))
                label.draw(at: NSPoint(x: x + (strip.size.width - label.size().width) / 2, y: 2))
                x += strip.size.width + gap
            }
        }
    }

    /// A stretch of menu bar: the sample apps as the real status item code
    /// draws them, optionally followed by Chime's bell and a clock.
    @MainActor
    private struct MenuBarStrip {
        static let height: CGFloat = 30
        private static let padding: CGFloat = 14
        private static let itemGap: CGFloat = 18
        private static let titleGap: CGFloat = 4

        private enum Piece {
            case image(NSImage)
            case text(NSAttributedString)

            var size: NSSize {
                switch self {
                case .image(let image): image.size
                case .text(let text): text.size()
                }
            }
        }

        /// Each piece with the gap that precedes it.
        private var pieces: [(gap: CGFloat, piece: Piece)] = []

        init(style: BadgeStyle, monochrome: Bool = false, showsExtras: Bool = false) {
            for sample in samples where sample.alwaysShow || sample.badge != nil {
                var icon = NSWorkspace.shared.icon(forFile: sample.app.path)
                if monochrome {
                    icon = StatusItemArt.monochrome(icon)
                }
                let content = StatusItemArt.content(icon: icon, badge: sample.status.badge, style: style)
                pieces.append((Self.itemGap, .image(content.image)))
                if !content.title.isEmpty {
                    pieces.append((Self.titleGap, .text(text(content.title, font: StatusItemArt.titleFont, color: ink))))
                }
            }
            if showsExtras {
                let symbol = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                if let bell = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?.withSymbolConfiguration(symbol) {
                    pieces.append((Self.itemGap, .image(tinted(bell, ink))))
                }
                let clock = text("Mon 5 Oct  09:41", font: .systemFont(ofSize: 13, weight: .medium), color: ink)
                pieces.append((Self.itemGap, .text(clock)))
            }
            if !pieces.isEmpty {
                pieces[0].gap = 0
            }
        }

        var size: NSSize {
            let content = pieces.map { $0.gap + $0.piece.size.width }.reduce(0, +)
            return NSSize(width: content + Self.padding * 2, height: Self.height)
        }

        func draw(at origin: NSPoint) {
            let bar = NSBezierPath(roundedRect: NSRect(origin: origin, size: size).insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
            (isDark ? NSColor(white: 0.13, alpha: 0.86) : NSColor(white: 0.96, alpha: 0.9)).setFill()
            bar.fill()
            ink.withAlphaComponent(0.14).setStroke()
            bar.stroke()

            var x = origin.x + Self.padding
            for (gap, piece) in pieces {
                x += gap
                let y = origin.y + (Self.height - piece.size.height) / 2
                switch piece {
                case .image(let image): image.draw(at: NSPoint(x: x, y: y), from: .zero, operation: .sourceOver, fraction: 1)
                case .text(let text): text.draw(at: NSPoint(x: x, y: y))
                }
                x += piece.size.width
            }
        }
    }

    // MARK: Settings scene

    /// The settings window showing the sample apps, title bar included.
    private static func settings() -> NSBitmapImageRep {
        let model = AppModel(
            sampleConfig: Config(apps: samples.map(\.app)),
            state: CoreState(trusted: true, apps: samples.map(\.status))
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 676),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Chime"
        window.contentView = NSHostingView(rootView: SettingsView().environment(model))
        // Off every screen, so taking the picture never flashes a window at the user.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1))

        // The window's frame view draws the title bar as well as the content.
        guard let frame = window.contentView?.superview,
              let capture = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)
        else {
            fatalError("the settings window has no frame view")
        }
        frame.cacheDisplay(in: frame.bounds, to: capture)

        // The window server rounds a window's corners; a view capture has to do it itself.
        let scale = CGFloat(capture.pixelsWide) / frame.bounds.width
        return draw(frame.bounds.size, scale: scale) {
            NSBezierPath(roundedRect: frame.bounds, xRadius: 16, yRadius: 16).addClip()
            capture.draw(in: frame.bounds)
        }
    }

    // MARK: Drawing

    /// Draws into a transparent bitmap of `size` points, `scale` pixels per point.
    private static func draw(_ size: NSSize, scale: CGFloat = 4, _ drawing: () -> Void) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        drawing()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func text(_ string: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
