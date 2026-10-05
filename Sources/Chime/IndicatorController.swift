import AppKit
import Observation

/// A small floating panel with the apps that have notifications, for when the
/// menu bar is out of sight. It can be dragged anywhere and stays where it is put.
@MainActor
final class IndicatorController: NSObject {
    private static let height: CGFloat = 34
    private static let frameName = "Indicator"

    private let model: AppModel
    private let appButtons: AppButtons

    private var panel: NSPanel?
    private let stack = NSStackView()
    private var buttons: [String: IndicatorButton] = [:]

    init(model: AppModel, appButtons: AppButtons) {
        self.model = model
        self.appButtons = appButtons
    }

    /// Shows the indicator when it is wanted and keeps it in step with the model.
    func start() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            // Fires before the change lands, so render on the next main-queue turn.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.start() }
            }
        }
    }

    private func render() {
        let config = model.config
        let notified = config.settings.showIndicator
            ? config.apps.filter { model.status(of: $0)?.badge != nil }
            : []

        for bundleId in buttons.keys where !notified.contains(where: { $0.bundleId == bundleId }) {
            buttons[bundleId] = nil
        }
        guard !notified.isEmpty else {
            panel?.orderOut(nil)
            return
        }

        let views = notified.map { app in
            let button = buttons[app.bundleId] ?? makeButton(for: app)
            buttons[app.bundleId] = button
            appButtons.show(app, badge: model.status(of: app)?.badge, in: button)
            return button
        }
        stack.setViews(views, in: .center)

        let isNew = panel == nil
        let panel = panel ?? makePanel()
        self.panel = panel
        fit(panel, restoringFrame: isNew)
        panel.orderFrontRegardless()
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        // A panel that never takes focus, floats over everything and follows the user to every space.
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.setAccessibilityLabel("Chime notifications")

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.maskImage = Self.capsule(height: Self.height)
        panel.contentView = background

        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        return panel
    }

    /// A capsule that stretches to any width, for masking the panel's background.
    private static func capsule(height: CGFloat) -> NSImage {
        let radius = height / 2
        let image = NSImage(size: NSSize(width: height + 1, height: height), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: 0, left: radius, bottom: 0, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Sizes the panel to its apps. It grows away from the side of the screen
    /// it is near, and both ways in the middle, so it stays where it was put.
    private func fit(_ panel: NSPanel, restoringFrame: Bool) {
        let size = NSSize(width: ceil(stack.fittingSize.width), height: Self.height)
        if restoringFrame {
            let restored = panel.setFrameUsingName(Self.frameName, force: true)
            panel.setFrameAutosaveName(Self.frameName)
            if !restored {
                panel.setFrame(defaultFrame(size: size), display: false)
            }
        }

        var frame = panel.frame
        guard let screen = screen(of: frame)?.frame else {
            // It was left on a display that is gone.
            panel.setFrame(defaultFrame(size: size), display: true)
            return
        }
        guard frame.size != size else { return }
        switch (frame.midX - screen.minX) / screen.width {
        case ..<(1 / 3): break
        case ..<(2 / 3): frame.origin.x = frame.midX - size.width / 2
        default: frame.origin.x = frame.maxX - size.width
        }
        frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - size.width))
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    /// The screen that `frame` is on, going by its center.
    private func screen(of frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
    }

    /// Top center of the main screen, just under where the menu bar is or would be.
    private func defaultFrame(size: NSSize) -> NSRect {
        let screen = NSScreen.screens.first?.frame ?? .zero
        let menuBarHeight = NSApp.mainMenu?.menuBarHeight ?? 0
        return NSRect(
            x: screen.midX - size.width / 2,
            y: screen.maxY - menuBarHeight - 8 - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: Apps

    private func makeButton(for app: TrackedApp) -> IndicatorButton {
        let button = IndicatorButton()
        button.identifier = NSUserInterfaceItemIdentifier(app.bundleId)
        button.isBordered = false
        button.font = StatusItemArt.titleFont
        button.target = self
        button.action = #selector(appClicked)
        button.makeMenu = { [weak self] in self?.menu(for: app.bundleId) }
        return button
    }

    private func app(_ bundleId: String) -> TrackedApp? {
        model.config.apps.first { $0.bundleId == bundleId }
    }

    @objc private func appClicked(_ button: NSButton) {
        guard let bundleId = button.identifier?.rawValue, let app = app(bundleId) else { return }
        model.open(app)
    }

    private func menu(for bundleId: String) -> NSMenu? {
        app(bundleId).map(appButtons.menu(for:))
    }
}

/// An app in the indicator. A click is the button's action, a drag moves the
/// whole indicator, and a right-click opens the menu.
private final class IndicatorButton: NSButton {
    /// How far the pointer may wander during a click before it becomes a drag.
    private static let dragThreshold: CGFloat = 3

    var makeMenu: (() -> NSMenu?)?

    /// The panel never becomes the active window, so every click is a first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeMenu?()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.modifierFlags.contains(.control), let menu = makeMenu?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }

        highlight(true)
        defer { highlight(false) }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            guard next.type == .leftMouseDragged else {
                sendAction(action, to: target)
                return
            }
            let location = next.locationInWindow
            if hypot(location.x - start.x, location.y - start.y) > Self.dragThreshold {
                window.performDrag(with: event)
                return
            }
        }
    }
}
