import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            if !model.state.trusted {
                Section {
                    AccessibilityPrompt()
                }
            }

            Section("Apps") {
                if model.config.apps.isEmpty {
                    NoAppsView()
                } else {
                    ForEach(model.config.apps) { app in
                        TrackedAppRow(app: app)
                    }
                    Button {
                        model.isPickingApps = true
                    } label: {
                        Label("Add Apps…", systemImage: "plus")
                    }
                }
            }

            Section("Appearance") {
                Picker("Show notifications as", selection: $model.config.settings.badgeStyle) {
                    ForEach(BadgeStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Monochrome icons", isOn: $model.config.settings.monochrome)
                LabeledContent("Preview") {
                    MenuBarPreview()
                }
                Toggle(isOn: $model.config.settings.useOwnItems) {
                    Text("Use apps' own menu bar items")
                    Text("An app that is in the menu bar already is not added again, and the floating indicator shows its item's title.")
                }
            }

            Section("When notified") {
                Toggle(isOn: $model.config.settings.revealMenuBar) {
                    Text("Reveal the menu bar")
                    Text("For when the menu bar is set to hide automatically.")
                }
                Toggle(isOn: $model.config.settings.showIndicator) {
                    Text("Show a floating indicator")
                    Text("The notified apps in a small panel you can drag anywhere.")
                }
                if model.config.settings.showIndicator {
                    if IndicatorEffect.glass.isAvailable {
                        Picker("Indicator background", selection: $model.config.settings.indicatorEffect) {
                            ForEach(IndicatorEffect.allCases) { effect in
                                Text(effect.title).tag(effect)
                            }
                        }
                    }
                    Slider(value: indicatorOpacity, in: 0...1) {
                        Text("Background opacity")
                    }
                }
                Toggle("Play a sound", isOn: $model.config.settings.playSound)
                    .onChange(of: model.config.settings.playSound) { _, isOn in
                        // Lets the user hear what they turned on.
                        if isOn {
                            model.playSound()
                        }
                    }
            }

            Section("General") {
                Toggle(isOn: Binding { model.launchAtLogin } set: { model.setLaunchAtLogin($0) }) {
                    Text("Launch at login")
                    if let error = model.launchAtLoginError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Toggle(isOn: $model.config.settings.showMenuIcon) {
                    Text("Show Chime in the menu bar")
                    Text("When hidden, open Chime again to get back here.")
                }
                Picker("Check for notifications", selection: $model.config.settings.pollIntervalMs) {
                    Text("Every second").tag(1000)
                    Text("Every 2 seconds").tag(2000)
                    Text("Every 5 seconds").tag(5000)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 420)
        .sheet(isPresented: $model.isPickingApps) {
            AppPicker().environment(model)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
        }
    }

    /// The indicator's opacity in whole percent, so dragging the slider saves a hundred values at most.
    private var indicatorOpacity: Binding<Double> {
        Binding {
            model.config.settings.indicatorOpacity
        } set: {
            model.config.settings.indicatorOpacity = ($0 * 100).rounded() / 100
        }
    }
}

/// Explains why Chime needs Accessibility access and how to grant it.
private struct AccessibilityPrompt: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Allow Accessibility access")
                    .font(.headline)
                Text("Chime reads notification badges from the Dock, which macOS only allows with Accessibility access. Nothing it reads leaves your Mac.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility Settings…") {
                    model.requestAccessibilityAccess()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
                Text("Turn on Chime in the list. This message goes away once it is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NoAppsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.badge")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No apps yet")
                .font(.headline)
            Text("Add the apps you want to keep an eye on. Each one appears in the menu bar when it has notifications.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Apps…") {
                model.isPickingApps = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct TrackedAppRow: View {
    @Environment(AppModel.self) private var model
    let app: TrackedApp

    var body: some View {
        let status = model.status(of: app)

        HStack(spacing: 10) {
            AppIcon(path: model.location(of: app).path, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(summary(of: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let badge = status?.badge {
                BadgePill(text: badge.short)
            }
            Picker("Show \(app.name)", selection: alwaysShow) {
                Text("When notified").tag(false)
                Text("Always").tag(true)
            }
            .labelsHidden()
            .fixedSize()
            Button {
                model.remove(app.bundleId)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove \(app.name)")
            .accessibilityLabel("Remove \(app.name)")
        }
    }

    private var alwaysShow: Binding<Bool> {
        Binding { app.alwaysShow } set: { model.setAlwaysShow($0, for: app.bundleId) }
    }

    private func summary(of status: AppStatus?) -> String {
        if !model.state.trusted {
            "Waiting for Accessibility access"
        } else if let badge = status?.badge {
            badge.summary
        } else if status?.running == true {
            "No notifications"
        } else {
            "Not running"
        }
    }
}

/// How a tracked app looks in the menu bar with the current appearance settings.
private struct MenuBarPreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let content = StatusItemArt.content(icon: icon, badge: sample, style: model.config.settings.badgeStyle)

        HStack(spacing: 3) {
            Image(nsImage: content.image)
            if !content.title.isEmpty {
                Text(content.title)
                    .font(Font(StatusItemArt.titleFont))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private var sample: Badge {
        Badge(label: "3", short: "3", count: 3)
    }

    private var icon: NSImage {
        let path = model.config.apps.first.map { model.location(of: $0).path } ?? "/System/Applications/Mail.app"
        let icon = NSWorkspace.shared.icon(forFile: path)
        return model.config.settings.monochrome ? StatusItemArt.monochrome(icon) : icon
    }
}

struct AppIcon: View {
    let path: String
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct BadgePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(.red, in: Capsule())
    }
}
