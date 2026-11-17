// Settings › clipboarda: recording, the hotkey, what is never kept, private windows and links.
import AppKit
import SwiftUI
import TingCore

struct ClipboardaSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var prefix = ""
    @State private var message: String?
    @State private var automation: [String: Bool] = [:]

    var body: some View {
        let settings = model.config.clipboarda
        Form {
            Section {
                Toggle("Use clipboarda", isOn: model.binding(\.clipboarda.enabled))
                Text(settings.enabled
                     ? "Ting keeps what you copy in memory, for this session only. Turning clipboarda off forgets it."
                     : "Off: Ting never reads the clipboard, the hotkey is free and the window does not open.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { MonoLabel("clipboarda", size: 9).foregroundStyle(Color.tingAmber) }
            if settings.enabled { sections(settings) }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 700)
    }

    @ViewBuilder private func sections(_ settings: ClipboardaSettings) -> some View {
            Section {
                LabeledContent("Hotkey") { ClipboardaHotkeyField() }
                Text("A selecta binding can open clipboarda too: add one in Bindings.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Keep at most") {
                    Stepper(value: model.binding(\.clipboarda.maxItems), in: ClipboardaSettings.maxItemsRange, step: 10) {
                        Text("\(settings.maxItems) items").font(.system(size: 12, design: .monospaced))
                    }
                }
                HStack {
                    let history = model.clipboarda.history
                    Text("\(history.entries.count) items, \(ByteCountFormatter.string(fromByteCount: Int64(history.totalBytes), countStyle: .memory)) in memory")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History") { model.clipboarda.clear() }
                        .disabled(history.entries.isEmpty)
                }
            } header: { MonoLabel("History", size: 9).foregroundStyle(Color.tingAmber) }

            Section {
                if settings.excludedApps.isEmpty {
                    Text("No apps. “Never Keep from…” in clipboarda adds the app of an item.")
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
                        Button("Remove") { model.update { $0.clipboarda.excludedApps.removeAll { $0 == id } } }
                            .accessibilityLabel("Keep copies from \(Self.appName(id)) again")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add App…", action: addApp)
                }
            } header: { MonoLabel("Never keep copies from", size: 9).foregroundStyle(Color.tingAmber) }

            Section {
                ForEach(settings.ignoredPrefixes, id: \.self) { value in
                    HStack {
                        Text(value).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button("Remove") { model.update { $0.clipboarda.ignoredPrefixes.removeAll { $0 == value } } }
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
            } header: { MonoLabel("Never keep text that starts with", size: 9).foregroundStyle(Color.tingAmber) }

            Section {
                Text("Never kept: copies while Secure Keyboard Entry is on (password fields, Terminal’s secure entry), copies password managers mark as secret, and copies from private windows of Firefox and its forks. Safari does not tell other apps about its private windows.")
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
            } header: { MonoLabel("Private windows", size: 9).foregroundStyle(Color.tingAmber) }
            .task { await refreshAutomation() }

            Section {
                Toggle("Fetch link titles, icons and images", isOn: model.binding(\.clipboarda.fetchLinks))
                Text("Off by default. When on, Ting loads a copied http or https link once, without cookies and without running scripts, to show its title, icon or image. The site then learns that the link was copied. Local network addresses are never loaded.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { MonoLabel("Links", size: 9).foregroundStyle(Color.tingAmber) }
    }

    private func addPrefix() {
        let value = prefix.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        model.update { if !$0.clipboarda.ignoredPrefixes.contains(value) { $0.clipboarda.ignoredPrefixes.append(value) } }
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
        model.update { _ = $0.clipboarda.exclude(app: id) }
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
