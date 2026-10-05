import SwiftUI
import UniformTypeIdentifiers

/// A searchable list of installed apps; clicking one adds or removes it.
struct AppPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Nil while the applications folders are being read.
    @ViewState private var apps: [InstalledApp]?
    /// The badges showing in the Dock right now, by bundle id.
    @ViewState private var badges: [String: Badge] = [:]
    @ViewState private var query = ""
    @FocusState private var isSearching: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add Apps")
                    .font(.headline)
                TextField("Search apps", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearching)
            }
            .padding()

            Divider()
            results
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()

            HStack {
                Button("Choose Other…", action: chooseOther)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 520)
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var results: some View {
        if let apps {
            let matches = query.isEmpty ? apps : apps.filter { $0.name.localizedStandardContains(query) }
            let notifying = query.isEmpty ? apps.filter { badges[$0.bundleId] != nil } : []

            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if !notifying.isEmpty {
                        Section("Has notifications now") {
                            ForEach(notifying, content: row)
                        }
                    }
                    Section(query.isEmpty ? "All apps" : "Results") {
                        ForEach(matches, content: row)
                    }
                }
            }
        } else {
            ProgressView()
        }
    }

    private func row(_ app: InstalledApp) -> some View {
        let isTracked = model.isTracked(app.bundleId)

        return Button {
            model.toggle(app)
        } label: {
            HStack(spacing: 10) {
                AppIcon(path: app.path, size: 28)
                Text(app.name)
                if let badge = badges[app.bundleId] {
                    BadgePill(text: badge.short)
                }
                Spacer()
                Image(systemName: isTracked ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isTracked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isTracked ? "Added" : "Not added")
    }

    private func load() async {
        // The Dock holds every app that can show a badge, wherever it is installed.
        let dock = Core.dockApps()
        for app in dock {
            if let bundleId = app.bundleId, let badge = app.badge {
                badges[bundleId] = badge
            }
        }
        let docked = dock.compactMap(\.path).map { URL(fileURLWithPath: $0) }
        apps = await AppCatalog.installedApps(including: docked)
        isSearching = true
    }

    private func chooseOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            model.add(panel.urls)
        }
    }
}
