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
                SettingsToggle("Use Clipbawd", detail: settings.enabled
                    ? "Record copies. Turning this off deletes all clipboard history."
                    : "Recording is off. The window and hotkey are unavailable.",
                    isOn: Binding(get: { settings.enabled }, set: { enabled in
                        if enabled { model.update { $0.clipbawd.enabled = true } }
                        else { pendingAction = "disable" }
                    }))
                if settings.enabled { LabeledContent("Hotkey") { ClipbawdHotkeyField() } }
            } header: { SettingsSectionTitle("Recording") }
            .id("clipbawd")
            if settings.enabled { sections(settings) }
        }
        .tingSettingsForm()
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
                SettingsToggle("Keep history between launches", detail: settings.persistent
                    ? "Saved on this Mac. Turning this off deletes the archive."
                    : "Session only. History is forgotten when Ting quits.",
                    isOn: Binding(get: { settings.persistent }, set: { enabled in
                        if enabled { model.update { $0.clipbawd.persistent = true } }
                        else { pendingAction = "persistent" }
                    }))
                DisclosureGroup(isExpanded: $storageExpanded) {
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
                    Text("Set days to 0 for no age limit. Cleanup runs hourly; using a copy again does not renew its age. Limits also apply to session-only history.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Retention limits")
                        Spacer(minLength: 12)
                        Text("\(settings.maxItems) items · \(settings.maxMegabytes) MiB · " + (settings.maxDays == 0 ? "No age limit" : "\(settings.maxDays) days"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                HStack(spacing: 12) {
                    let history = model.clipbawd.history
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(history.entries.count) items in history").font(.system(size: 13)).monospacedDigit()
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(history.totalBytes), countStyle: .memory)) in memory" + (settings.persistent ? " · \(ByteCountFormatter.string(fromByteCount: Int64(model.clipbawd.storedBytes), countStyle: .file)) on disk" : ""))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear History", role: .destructive) { pendingAction = "clear" }
                        .disabled(history.entries.isEmpty && model.clipbawd.storageError == nil && !model.clipbawd.isLoading && model.clipbawd.storedBytes == 0)
                }
                .padding(.vertical, 4)
                if model.clipbawd.isLoading { ProgressView("Restoring history…").controlSize(.small) }
                if let error = model.clipbawd.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.tingAmber)
                }
            } header: { SettingsSectionTitle("History") }
            .id("storage")

            Section {
                DisclosureGroup("Privacy and exclusions", isExpanded: $privacyExpanded) {
                    privacySections(settings)
                }
            } header: { SettingsSectionTitle("Privacy") }
            .id("privacy")

            Section {
                SettingsToggle("Fetch link titles, icons and images",
                               detail: "Off by default. Sites can see the request. No cookies or scripts are used.",
                               isOn: model.binding(\.clipbawd.fetchLinks))
            } header: { SettingsSectionTitle("Link previews") }
            .id("links")
    }

    @ViewBuilder private func privacySections(_ settings: ClipbawdSettings) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stored data").font(.headline).foregroundStyle(.primary)
                Text("History is stored locally without additional encryption and is excluded from backups. Clear History deletes memory and disk history. Deletion cannot erase existing backups or filesystem snapshots.")
                Text("Copied links are not fetched unless link previews are enabled. Public-address checks do not prevent DNS rebinding; leave previews off on sensitive networks.")
                Text("Text, images and one MP4/MOV/M4V video per copy are supported. Videos are limited to 30 seconds and 32 MiB, with a thumbnail but no playback. Other files remain references, not backups.")
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)

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
