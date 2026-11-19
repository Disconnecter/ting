// Settings › clipbawd: recording, the hotkey, what is never kept, private windows and links.
import AppKit
import SwiftUI
import TingCore

struct ClipbawdSettingsView: View {
    var searchTarget: String? = nil
    @Environment(AppModel.self) private var model
    @State private var prefix = ""
    @State private var message: String?
    @State private var automation: [String: Bool] = [:]
    @State private var storageExpanded = false
    @State private var privacyExpanded = false
    @State private var pendingAction: String?

    var body: some View {
        let settings = model.config.clipbawd
        Form {
            Section {
                Toggle("Use Clipbawd", isOn: Binding(get: { settings.enabled }, set: { enabled in
                    if enabled { model.update { $0.clipbawd.enabled = true } }
                    else { pendingAction = "disable" }
                }))
                Text(settings.enabled
                     ? "Keep what you copy. History stays in memory unless you enable storage below. Turning Clipbawd off forgets it."
                     : "Off: Ting never reads the clipboard, the hotkey is free and the window does not open.")
                    .font(.caption).foregroundStyle(.secondary)
                if settings.enabled { LabeledContent("Hotkey") { ClipbawdHotkeyField() } }
            } header: { MonoLabel("Clipbawd", size: 9).foregroundStyle(Color.tingAmber) }
            .id("clipbawd")
            if settings.enabled { sections(settings) }
        }
        .formStyle(.grouped)
        .onAppear { expandSearchTarget() }
        .onChange(of: searchTarget) { expandSearchTarget() }
        .alert("Delete clipboard history?", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
            Button("Delete", role: .destructive) {
                switch pendingAction {
                case "disable": model.update { $0.clipbawd.enabled = false }
                case "persistent": model.update { $0.clipbawd.persistent = false }
                default: model.clipbawd.clear()
                }
                pendingAction = nil
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction == "persistent"
                 ? "Stored history will be deleted. The current session stays in memory."
                 : "All clipboard history will be deleted from memory and disk. This cannot be undone.")
        }
    }

    @ViewBuilder private func sections(_ settings: ClipbawdSettings) -> some View {
            Section {
                Toggle("Keep history between launches", isOn: Binding(get: { settings.persistent }, set: { enabled in
                    if enabled { model.update { $0.clipbawd.persistent = true } }
                    else { pendingAction = "persistent" }
                }))
                Text(settings.persistent
                     ? "Stored locally, without additional encryption; excluded from backups. Turning this off deletes stored history."
                     : "Off by default. History is forgotten when Ting quits.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Retention limits", isExpanded: $storageExpanded) {
                    LabeledContent("Keep at most") {
                        Stepper(value: model.binding(\.clipbawd.maxItems), in: ClipbawdSettings.maxItemsRange, step: 10) {
                            Text("\(settings.maxItems) items").monospacedDigit()
                        }
                    }
                    LabeledContent("Total size") {
                        TextField("", value: Binding(get: { settings.maxMegabytes }, set: { value in
                            model.update { $0.clipbawd.maxMegabytes = min(max(value, 1), 4096) }
                        }), format: .number.grouping(.never))
                            .labelsHidden()
                            .frame(width: 80)
                            .accessibilityLabel("Clipboard history size limit in MiB")
                        Text("MiB")
                    }
                    LabeledContent("Delete copies older than") {
                        Stepper(value: model.binding(\.clipbawd.maxDays), in: ClipbawdSettings.maxDaysRange) {
                            Text(settings.maxDays == 0 ? "No age limit" : "\(settings.maxDays) days").monospacedDigit()
                        }
                    }
                    Text("Defaults: 100 items, 50 MiB, 30 days. Set days to 0 for no age limit. Limits also apply to session-only history. Expired copies are removed hourly; using a copy again does not extend its lifetime. Videos: up to 30 seconds and 32 MiB each.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    let history = model.clipbawd.history
                    Text("\(history.entries.count) items · \(ByteCountFormatter.string(fromByteCount: Int64(history.totalBytes), countStyle: .memory)) of \(settings.maxMegabytes) MiB" + (settings.persistent ? " · \(ByteCountFormatter.string(fromByteCount: Int64(model.clipbawd.storedBytes), countStyle: .file)) on disk" : " in memory"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History") { pendingAction = "clear" }
                        .disabled(history.entries.isEmpty && model.clipbawd.storageError == nil && !model.clipbawd.isLoading && model.clipbawd.storedBytes == 0)
                }
                if model.clipbawd.isLoading { ProgressView("Restoring history…").controlSize(.small) }
                if let error = model.clipbawd.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.tingAmber)
                }
            } header: { MonoLabel("History", size: 9).foregroundStyle(Color.tingAmber) }
            .id("storage")

            Section {
            DisclosureGroup("Privacy and exclusions", isExpanded: $privacyExpanded) {
            privacySections(settings)
            }
            }.id("privacy")

            Section {
                Toggle("Fetch link titles, icons and images", isOn: model.binding(\.clipbawd.fetchLinks))
                Text("Off by default. Ting loads copied links without cookies or scripts; the site learns that a link was copied. Local network addresses are checked, but DNS rebinding remains possible. Leave this off on sensitive networks.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { MonoLabel("Links", size: 9).foregroundStyle(Color.tingAmber) }
            .id("links")
    }

    @ViewBuilder private func privacySections(_ settings: ClipbawdSettings) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Never keep copies from").font(.headline)
                if settings.excludedApps.isEmpty {
                    Text("No apps. “Never Keep from…” in Clipbawd adds the app of an item.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(settings.excludedApps, id: \.self) { id in
                    HStack {
                        if let icon = AppIcons.icon(id) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(Self.appName(id))
                        Text(id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { model.update { $0.clipbawd.excludedApps.removeAll { $0 == id } } }
                            .accessibilityLabel("Keep copies from \(Self.appName(id)) again")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add App…", action: addApp)
                }
            }
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("Never keep text that starts with").font(.headline)
                ForEach(settings.ignoredPrefixes, id: \.self) { value in
                    HStack {
                        Text(value).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button("Remove") { model.update { $0.clipbawd.ignoredPrefixes.removeAll { $0 == value } } }
                            .accessibilityLabel("Remove the start \(value)")
                    }
                }
                HStack {
                    TextField("Start of text, such as sk- or ghp_", text: $prefix)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit(addPrefix)
                    Button("Add", action: addPrefix)
                        .disabled(prefix.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Text that starts with one of these, after leading spaces, is never kept. Upper and lower case differ.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("Private windows").font(.headline)
                Text("Never kept: copies while Secure Keyboard Entry is on (password fields, Terminal’s secure entry), copies password managers mark as secret, and recognised private windows of Firefox and its forks (requires Accessibility and a matching window title). Detection is best-effort. Safari does not tell other apps about its private windows.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let browsers = Self.runningChromium()
                if browsers.isEmpty {
                    Text("Incognito windows of Chrome, Brave, Edge and Vivaldi are checked when Ting may ask the browser. Open one of them to allow it here.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(browsers, id: \.id) { browser in
                    HStack {
                        Text("\(browser.name) incognito windows")
                        Spacer()
                        if automation[browser.id] == true {
                            Label("Checked", systemImage: "checkmark").foregroundStyle(.secondary)
                        } else {
                            Button("Allow…") { allow(browser.id) }
                                .help("macOS asks whether Ting may control \(browser.name). Ting only reads whether the front window is incognito.")
                        }
                    }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(Color.tingAmber)
                }
            }
            .padding(.vertical, 8)
            .task { await refreshAutomation() }


    }

    private func expandSearchTarget() {
        if searchTarget == "storage" { storageExpanded = true }
        if searchTarget == "privacy" { privacyExpanded = true }
    }

    private func addPrefix() {
        let value = prefix.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        model.update { if !$0.clipbawd.ignoredPrefixes.contains(value) { $0.clipbawd.ignoredPrefixes.append(value) } }
        prefix = ""
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let id = Bundle(url: url)?.bundleIdentifier else {
            message = "\(url.lastPathComponent) has no bundle identifier."
            return
        }
        message = nil
        model.update { _ = $0.clipbawd.exclude(app: id) }
    }

    private func allow(_ id: String) {
        Task {
            let status = await MicroAppContextReader.askAutomation(bundleID: id)
            message = status == noErr ? nil : "\(Self.appName(id)) did not allow it. Change this in System Settings › Privacy & Security › Automation."
            await refreshAutomation()
        }
    }

    private func refreshAutomation() async {
        for browser in Self.runningChromium() {
            automation[browser.id] = await ClipPrivacyChecker.automationAllowed(bundleID: browser.id)
        }
    }

    /// Chromium browsers that are running: macOS asks about an app only while it runs.
    private static func runningChromium() -> [(id: String, name: String)] {
        let running = NSWorkspace.shared.runningApplications
        return ClipPrivateWindow.modeBrowsers.sorted().compactMap { id in
            running.first { $0.bundleIdentifier == id }.map { (id, $0.localizedName ?? id) }
        }
    }

    static func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
