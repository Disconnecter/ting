// Settings: native Form/Table (HIG) with Ting's mono labels, amber keycaps and Ting buttons.
// System toggles keep the system accent.
import AppKit
import SwiftUI
import TingCore
import UniformTypeIdentifiers

struct SettingsRoot: View {
    @Environment(AppModel.self) private var model
    @State private var page: SettingsPage? = .general
    @State private var query = ""
    @State private var target: String?

    init(page: SettingsPage = .general, query: String = "", target: String? = nil) {
        _page = State(initialValue: page)
        _query = State(initialValue: query)
        _target = State(initialValue: target)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                TextField("Search settings", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search all Ting settings")
                    .padding(.horizontal, 12).padding(.top, 12)
                List(SettingsPage.allCases, selection: $page) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
                .onChange(of: page) { query = "" }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
        VStack(spacing: 0) {
            if let error = model.configError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.tingAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.tingAmber.opacity(0.1))
            }
            if !model.microAppIssues.isEmpty {
                Button { page = .microApps; query = "" } label: {
                Label("Some micro-app files have errors. Open Micro-apps.", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.tingAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.tingAmber.opacity(0.1))
            }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let results = SettingsCatalog.search(query)
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { result in
                        Button {
                            page = result.page
                            query = ""
                            target = result.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title).font(.headline)
                                Text(result.page.title).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .accessibilityLabel("Matching settings")
                }
            } else {
                ScrollViewReader { proxy in
                    Group {
                        switch page ?? .general {
                        case .general: GeneralSettings(activation: false)
                        case .activation: GeneralSettings(activation: true)
                        case .bindings: BindingsSettings()
                        case .clipbawd: ClipbawdSettingsView(searchTarget: target)
                        case .microApps:
                            Form { MicroAppsSection().id("micro-apps") }.formStyle(.grouped)
                        case .advanced: AdvancedSettings()
                        }
                    }
                    .id(page)
                    .onAppear { if let target { proxy.scrollTo(target, anchor: .top) } }
                    .onChange(of: target) { if let target { proxy.scrollTo(target, anchor: .top) } }
                }
            }
        }
        .navigationTitle(query.isEmpty ? (page ?? .general).title : "Search Settings")
        }
        .frame(minWidth: 900, idealWidth: 1040, minHeight: 600, idealHeight: 720)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let activation: Bool
    @Environment(AppModel.self) private var model
    @Bindable private var updates = UpdateService.shared

    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            if !activation {
            Picker("Appearance", selection: model.binding(\.appearance)) {
                Text(Appearance.light.title).tag(Appearance.light)
                Text(Appearance.dark.title).tag(Appearance.dark)
            }
            .pickerStyle(.segmented)
            Section {
                Toggle("Show panel title", isOn: model.binding(\.showPanelHeader))
                Text("Show the Ting · selecta / launcha / Clipbawd title row. The leader symbol and input stay visible.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { MonoLabel("Panel", size: 9).foregroundStyle(Color.tingAmber) }
            .id("appearance")
            }
            if activation {
            Section {
                LabeledContent("Leader") { LeaderField() }
                LabeledContent("Second leader") {
                    HStack {
                        LeaderField(alternate: true)
                        if model.config.alternateLeader != nil {
                            Button("Clear") { model.update { $0.alternateLeader = nil } }
                                .accessibilityLabel("Clear second leader key")
                        }
                    }
                }
                LabeledContent("Show menu after") {
                    HStack {
                        Slider(value: model.binding(\.showDelay), in: 0...1, step: 0.05).frame(width: 160)
                        Text(model.config.showDelay == 0 ? "instantly" : String(format: "%.2f s", model.config.showDelay))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                    }
                }
                Text("Type the whole sequence faster than this and the menu never appears.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Unknown key", selection: model.binding(\.unknownKey)) {
                    Text("Shake and stay open").tag(UnknownKeyBehavior.shake)
                    Text("Close the menu").tag(UnknownKeyBehavior.close)
                }
            } header: { MonoLabel("Activation", size: 9).foregroundStyle(Color.tingAmber) }
            .id("activation")
            LaunchaSettingsSection().id("launcha")
            }
            if !activation {
            Section {
                Toggle("Launch at login", isOn: model.binding(\.launchAtLogin))
                if let error = model.loginItemError {
                    Text(error).font(.caption).foregroundStyle(Color.tingAmber)
                }
                Toggle("Show icon in menu bar", isOn: model.binding(\.showMenuBarIcon))
                if !model.config.showMenuBarIcon {
                    Text("Open Ting again from Finder or Spotlight to get back to Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { MonoLabel("System", size: 9).foregroundStyle(Color.tingAmber) }
            .id("system")
            Section {
                Toggle("Play a “ting” when opening an app, link or file", isOn: model.binding(\.playSound))
                SoundSettings()
            } header: { MonoLabel("Sound", size: 9).foregroundStyle(Color.tingAmber) }
            .id("sound")
            if updates.isAvailable {
                Section {
                    Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                    HStack {
                        Text("Version \(Self.version)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Now") { updates.checkForUpdates() }
                    }
                } header: { MonoLabel("Updates", size: 9).foregroundStyle(Color.tingAmber) }
                .id("updates")
            } else if let homebrew = updates.homebrew {
                Section {
                    Text("Homebrew installed this copy (\(homebrew.prefix.path)), so Homebrew updates it.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Version \(Self.version)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Update Ting via Homebrew…") { updates.checkForUpdates() }
                    }
                } header: { MonoLabel("Updates", size: 9).foregroundStyle(Color.tingAmber) }
                .id("updates")
            }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sound

/// The sound and its volume, under the "ting" toggle. Both are disabled while the toggle is off.
private struct SoundSettings: View {
    @Environment(AppModel.self) private var model
    /// Read once: the sounds in /System/Library/Sounds do not change while Ting runs.
    private static let systemNames = SystemSounds.names()

    var body: some View {
        let config = model.config
        let names = Self.systemNames.contains(config.sound) ? Self.systemNames : Self.systemNames + [config.sound]
        let sound = model.binding(\.sound)
        // Choosing a sound saves it and plays it once; a reload of the file plays nothing.
        let choice = Binding(get: { sound.wrappedValue },
                             set: { sound.wrappedValue = $0; model.previewSound() })
        Group {
            Picker("Sound", selection: choice) {
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("Volume") {
                HStack {
                    Slider(value: model.binding(\.soundVolume), in: 0...1) { editing in
                        if !editing { model.previewSound() }
                    }
                    .frame(width: 160)
                    Text("\(Int((config.soundVolume * 100).rounded())) %")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                }
            }
        }
        .disabled(!config.playSound)
    }
}

// MARK: - launcha

private struct LaunchaSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingFolders = false

    var body: some View {
        let launcha = model.config.launcha
        Section {
            LabeledContent("Hotkey") { LaunchaHotkeyField() }
            Toggle("Double-tap the leader", isOn: model.binding(\.launcha.doubleTap))
            LabeledContent("Double-tap interval") {
                HStack {
                    Slider(value: model.binding(\.launcha.doubleTapWindow),
                           in: LaunchaSettings.doubleTapWindowRange, step: 0.05)
                        .frame(width: 160)
                        .accessibilityValue(String(format: "%.2f seconds", launcha.doubleTapWindow))
                    Text(String(format: "%.2f s", launcha.doubleTapWindow))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                }
            }
            .disabled(!launcha.doubleTap)
            Text("Press the leader twice to open launcha. The first press opens selecta at once, so sequences are never delayed. A separate hotkey is optional.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Calculate in launcha", isOn: model.binding(\.launcha.calculator))
            Text("Type digits and an operator, such as 2*(3+4) or 1,5 × 4: the result comes first, and Return copies it.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Convert in launcha", isOn: model.binding(\.launcha.converter))
            Text("Units, number bases and dates, such as 5 yd to m, 255 to hex, 1700000000 to date or now + 2 days: the result comes first, and Return copies it.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Search Desktop, Documents and Downloads", isOn: Binding(
                get: { model.protectedFoldersAllowed },
                set: { allowed in
                    if allowed { confirmingFolders = true } else { model.setProtectedFoldersAllowed(false) }
                }))
            Text("Off by default. Ting saves this choice outside the config file.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.launchaConsentError {
                Text(error).font(.caption).foregroundStyle(Color.tingAmber)
            }
        } header: { MonoLabel("launcha", size: 9).foregroundStyle(Color.tingAmber) }
        .alert("Search Desktop, Documents and Downloads?", isPresented: $confirmingFolders) {
            Button("Allow Access") { model.setProtectedFoldersAllowed(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("launcha will also list apps on your Desktop and find files in these folders. macOS may ask you to allow Ting to access each folder.")
        }
    }
}

// MARK: - Advanced

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Location") {
                    Text(model.store.displayPath).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
                HStack {
                    Button("Reveal in Finder") { model.revealConfigFile() }
                    Button("Open in Editor") { model.openConfigFile() }
                    Spacer()
                    Button("Reload") { model.reload() }
                }
                Text("Ting reloads the file when it changes on disk. Micro-apps live in \(model.microStore.displayPath), next to it. Set TING_CONFIG to use another file.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { MonoLabel("Configuration file", size: 9).foregroundStyle(Color.tingAmber) }
            .id("config")
            Section {
                HStack {
                    Button("Export…", action: export)
                    Button("Import…", action: importConfig)
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(Color.tingAmber)
                }
            } header: { MonoLabel("Backup", size: 9).foregroundStyle(Color.tingAmber) }
            .id("backup")
        }
        .formStyle(.grouped)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ting-config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigCodec.encode(model.config).write(to: url, options: .atomic)
            message = "Exported to \(url.lastPathComponent)."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try ConfigCodec.decode(Data(contentsOf: url))
            model.replaceConfig(imported)
            message = "Imported \(url.lastPathComponent)."
        } catch let error as ConfigError {
            message = "Import failed: " + ConfigStore.LoadError.invalid(error).message
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Micro-apps

private struct MicroAppsSection: View {
    @Environment(AppModel.self) private var model
    @State private var folderError: String?

    var body: some View {
        Section {
            LabeledContent("Folder") {
                Text(model.microStore.displayPath).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }
            let working = model.microApps.filter { !$0.isBroken }.count
            let broken = model.microApps.count - working
            Text(model.microApps.isEmpty ? "No micro-apps."
                 : "\(working) working, \(broken) broken.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.microApps.isEmpty {
                MicroAppList(entries: model.microApps)
            }
            if model.microAppIssues.isEmpty {
                Label("No errors.", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(model.microAppIssues.enumerated()), id: \.offset) { _, issue in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(issue.file):\(issue.line)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.tingAmber)
                                Text(issue.message).font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
            }
            HStack {
                Button("Open Folder in Finder") { folderError = model.openMicroAppsFolder() }
                Button("Copy Agent Prompt") { model.copyAgentPrompt() }
                    .help("Copy a text for a coding agent such as Claude Code, Codex or pi; add your task after it.")
                Spacer()
                Button("Reload") { model.reload() }
            }
            if let folderError {
                Text(folderError).font(.caption).foregroundStyle(Color.tingAmber)
            }
            let access = model.accessibility.access
            LabeledContent("Accessibility") {
                HStack(spacing: 8) {
                    if access.isTrusted {
                        Label("Allowed", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    } else {
                        Text("Not allowed").foregroundStyle(Color.tingAmber)
                        Button("Allow…") { model.accessibility.show() }
                    }
                }
            }
            .onAppear { access.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in access.refresh() }
            Text("Only micro-apps that read the selected text or the front window, press keys or paste need it.")
                .font(.caption).foregroundStyle(.secondary)
            Text("One micro-app per .yaml file. Ting creates the folder when you open it, loads it again when it changes and writes the errors to \(model.microStore.logDisplayPath).")
                .font(.caption).foregroundStyle(.secondary)
        } header: { MonoLabel("Micro-apps", size: 9).foregroundStyle(Color.tingAmber) }
    }
}

/// Read-only: every file of the micro-apps folder with its name, id and state.
private struct MicroAppList: View {
    let entries: [MicroAppEntry]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                ForEach(["Name", "Id", "File", "State"], id: \.self) { title in
                    MonoLabel(title, size: 9, weight: .regular, tracking: 1).foregroundStyle(.secondary)
                }
            }
            ForEach(entries, id: \.file) { entry in
                GridRow {
                    Text(entry.app?.shownName ?? "—").lineLimit(1)
                    Text(entry.app?.id ?? entry.fileID).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    Text(entry.file).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    if entry.isBroken {
                        Label("broken", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.tingAmber)
                            .help(entry.issues.first.map { "line \($0.line): \($0.message)" } ?? "")
                    } else {
                        Label("good", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
