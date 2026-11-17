import TingRuntime
// App state shared by the status menu, Welcome and Settings. Views read it and call its methods;
// file IO, hotkeys and actions live in the services it owns.
import AppKit
import Observation
import SwiftUI
import TingCore

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// The last good config.
    private(set) var config = Config()
    /// Why the config file could not be read or written; the last good config stays in use.
    private(set) var configError: String?
    private(set) var issues: [ConfigIssue] = []
    private(set) var hotkeyStatus: HotkeyService.Status = .inactive
    private(set) var launchaHotkeyStatus: HotkeyService.Status = .inactive
    private(set) var clipboardaHotkeyStatus: HotkeyService.Status = .inactive
    private(set) var loginItemError: String?
    /// Every file of the micro-apps folder, good and broken, by file name.
    private(set) var microApps: [MicroAppEntry] = []
    /// Problems of the micro-app files, by file name, then by line.
    private(set) var microAppIssues: [MicroAppIssue] = []
    /// Session-only: the leader is off while paused.
    var isPaused = false {
        didSet { applyHotkey() }
    }
    /// All hotkeys are off while a new one is recorded, so an existing shortcut can be captured.
    private(set) var isRecordingHotkey = false
    /// launcha may search Desktop, Documents and Downloads. Stored apart from the config.
    var protectedFoldersAllowed: Bool { launchaModel.protectedFolders == .allowed }
    var launchaConsentError: String? { launchaModel.consentError }

    @ObservationIgnored let store: ConfigStore
    @ObservationIgnored private(set) lazy var microStore = MicroAppStore(configURL: store.url)
    @ObservationIgnored private let hotkeys: HotkeyService
    @ObservationIgnored private var activeAppShortcuts: [AppShortcut] = []
    @ObservationIgnored let leader: LeaderController
    @ObservationIgnored private let runner: ActionRunner
    @ObservationIgnored private let toast = ToastController()
    @ObservationIgnored private let launchaModel: LaunchaModel
    @ObservationIgnored let launcha: LaunchaController
    /// The clipboard history of this session.
    @ObservationIgnored let clipboarda: ClipboardaHistory
    @ObservationIgnored let clipboardaPanel: ClipboardaController
    /// True while the gear menu tracks: the launchers stay open but take no keys or hotkeys.
    @ObservationIgnored private(set) var isMenuTracking = false
    /// The one open micro-app flow: approval, working state and result.
    @ObservationIgnored private let microFlow = MicroAppFlowController()
    /// The Accessibility window, and whether Ting may use Accessibility.
    @ObservationIgnored let accessibility = AccessibilityWindowController()
    /// Held-key guard for the launcha hotkey: a repeat while held never toggles twice.
    @ObservationIgnored private var launchaKey = LeaderDoubleTap(isEnabled: false)
    @ObservationIgnored private var clipboardaKey = LeaderDoubleTap(isEnabled: false)
    @ObservationIgnored private lazy var recordingGate = HotkeyRecordingGate { [weak self] in self?.setRecordingHotkey($0) }
    /// Loaded "ting" sounds by name; nil marks a name that cannot be loaded.
    @ObservationIgnored private var sounds: [String: NSSound?] = [:]

    /// `presentsWindows` false: the launchers keep their state but show no window (tests).
    init(presentsWindows: Bool = true, store: ConfigStore? = nil, hotkeys: HotkeyService? = nil,
         clipboarda: ClipboardaHistory? = nil) {
        self.store = store ?? ConfigStore()
        // Tests (no windows) never watch the person's clipboard.
        self.clipboarda = clipboarda ?? ClipboardaHistory(pasteboard: presentsWindows ? .general
            : NSPasteboard(name: NSPasteboard.Name("io.bobuk.ting.tests." + UUID().uuidString)))
        clipboardaPanel = ClipboardaController(history: self.clipboarda, presentsWindow: presentsWindows)
        self.hotkeys = hotkeys ?? HotkeyService()
        leader = LeaderController(presentsWindow: presentsWindows)
        let runner = ActionRunner()
        self.runner = runner
        let environment = store.map { ["TING_CONFIG": $0.url.path] } ?? ProcessInfo.processInfo.environment
        launchaModel = LaunchaModel(opener: runner,
            historyStore: LaunchaHistoryStore(url: LaunchaHistoryStore.defaultURL(environment: environment)),
            consent: LaunchaConsentStore(url: LaunchaConsentStore.defaultURL(environment: environment)))
        launcha = LaunchaController(model: launchaModel, presentsWindow: presentsWindows)
        launcha.onBeginShortcutRecording = { [weak self] owner in self?.beginHotkeyRecording(owner) }
        launcha.onEndShortcutRecording = { [weak self] owner in self?.endHotkeyRecording(owner) }
        launcha.onSaveShortcut = { [weak self] row, hotkey in
            guard let self else { throw CancellationError() }
            try self.setAppShortcut(for: row, hotkey: hotkey)
        }
    }

    var leaderDisplay: String { config.leader?.display ?? "Not set" }
    var isLeaderActive: Bool { hotkeyStatus == .active && !isPaused }

    var hotkeyProblem: String? {
        switch hotkeyStatus {
        case .failed(let reason): reason
        case .inactive, .active: nil
        }
    }

    /// The menu-bar item shows its problem mark.
    var needsAttention: Bool {
        configError != nil || hotkeyProblem != nil || launchaHotkeyProblem != nil || clipboardaHotkeyProblem != nil
            || !microAppIssues.isEmpty
            || !launcha.chrome.appShortcutProblems.isEmpty || issues.contains { $0.kind == .appHotkey }
    }

    var launchaHotkeyDisplay: String { config.launcha.hotkey?.display ?? "Not set" }

    /// Why the launcha hotkey does not work: invalid, the same as the leader, or taken.
    var launchaHotkeyProblem: String? {
        if let issue = issues.first(where: { $0.kind == .invalidLaunchaHotkey || $0.kind == .launchaHotkeyConflict }) {
            return issue.message
        }
        switch launchaHotkeyStatus {
        case .failed(let reason): return reason
        case .inactive, .active: return nil
        }
    }

    /// Why the clipboarda hotkey does not work: invalid, the same as another Ting key, or taken.
    var clipboardaHotkeyProblem: String? {
        guard config.clipboarda.enabled else { return nil }
        if let issue = issues.first(where: { $0.kind == .invalidClipboardaHotkey || $0.kind == .clipboardaHotkeyConflict }) {
            return issue.message
        }
        switch clipboardaHotkeyStatus {
        case .failed(let reason): return reason
        case .inactive, .active: return nil
        }
    }

    // MARK: Lifecycle

    func start() {
        hotkeys.onStatusChange = { [weak self] slot, status in
            switch slot {
            case .leader: self?.hotkeyStatus = status
            case .launcha: self?.launchaHotkeyStatus = status
            case .clipboarda: self?.clipboardaHotkeyStatus = status
            case .application: self?.refreshAppShortcutProblems()
            }
        }
        hotkeys.onPress = { [weak self] slot, time in self?.hotkeyPressed(slot, at: time) }
        hotkeys.onRelease = { [weak self] slot in self?.hotkeyReleased(slot) }
        leader.onRun = { [weak self] item in self?.run(item) }
        leader.onDoubleTap = { [weak self] in self?.launcha.open() }
        launchaModel.onWillOpen = { [weak self] in self?.playSound() }
        launchaModel.onCopyValue = { [weak self] value in self?.copyValue(value) }
        launchaModel.onStartMicro = { [weak self] start in
            switch start {
            case .id(let id): self?.microFlow.start(id: id)
            case .file(let file): self?.microFlow.start(file: file)
            }
        }
        runner.onError = { [weak self] message in self?.toast.show(message) }
        clipboardaPanel.onToast = { [weak self] message in self?.toast.show(message) }
        clipboardaPanel.onPasteError = { [weak self] error in
            if error.needsAccessibility { self?.accessibility.show() }
            self?.toast.show("Copied, not pasted: \(error.localizedDescription)")
        }
        clipboardaPanel.onExclude = { [weak self] source in
            guard let id = source.bundleID else { return }
            self?.update { _ = $0.clipboarda.exclude(app: id) }
            self?.toast.show("clipboarda will never keep copies from \(source.name).")
        }
        microFlow.onToast = { [weak self] message in self?.toast.show(message) }
        microFlow.onAccessibilityNeeded = { [weak self] in self?.accessibility.show() }
        accessibility.onGranted = { [weak self] in self?.toast.show("Accessibility is on. Start the micro-app again.") }
        microFlow.folderDisplay = { [weak self] in self?.microStore.displayPath ?? "the micro-apps folder" }

        if !store.fileExists {
            do {
                try store.write(.sample)
            } catch {
                apply(.sample)
                configError = "Cannot create \(store.displayPath): \(error.localizedDescription)"
            }
        }
        // The user's PATH is read at start (the first load) and again on each load of the folder.
        microStore.onLoad = { UserPATH.refresh() }
        reload()
        store.watch { [weak self] in self?.reload() }
        microStore.watch { [weak self] previous, current in
            self?.applyMicroApps(current)
            if let message = current.toastMessage(since: previous) { self?.toast.show(message) }
        }
        launchaModel.prewarm()
    }

    /// Loads the config file and the micro-apps folder again.
    func reload() {
        switch store.load() {
        case .success(let loaded):
            configError = nil
            apply(loaded)
        case .failure(let error):
            configError = error.message
        }
        applyMicroApps(microStore.load())
    }

    private func applyMicroApps(_ catalog: MicroAppCatalog) {
        leader.setMicroApps(catalog)
        microFlow.setCatalog(catalog)
        launchaModel.setMicroApps(catalog.launchaCandidates(bindings: config.items), folder: microStore.folderURL)
        if microApps != catalog.entries { microApps = catalog.entries }
        if microAppIssues != catalog.issues { microAppIssues = catalog.issues }
    }

    /// The loaded micro-apps, for the bindings editor and the Settings list.
    var microCatalog: MicroAppCatalog { MicroAppCatalog(entries: microApps) }

    /// Opens the micro-apps folder in Finder and creates it first when it is missing. The folder
    /// watch sees the new folder and loads it. Returns an error message when the folder cannot
    /// be created or opened.
    @discardableResult
    func openMicroAppsFolder() -> String? {
        let url = microStore.folderURL
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return "Cannot create \(microStore.displayPath): \(error.localizedDescription)"
        }
        return NSWorkspace.shared.open(url) ? nil : "Cannot open \(microStore.displayPath) in Finder."
    }

    /// Puts the agent prompt on the clipboard and shows the toast.
    /// The value of a launcha calculation goes to the clipboard.
    func copyValue(_ value: String, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        toast.show("Copied \(value)")
    }

    func copyAgentPrompt(pasteboard: NSPasteboard = .general) {
        AgentPromptSource.copy(AgentPromptSource.text(), to: pasteboard)
        toast.show(AgentPrompt.toast)
    }

    // MARK: Editing (every edit writes the file atomically)

    func update(_ change: (inout Config) -> Void) {
        var next = config
        change(&next)
        guard next != config else { return }
        do {
            try store.write(next)
            configError = nil
            apply(next)
        } catch {
            configError = "Cannot save \(store.displayPath): \(error.localizedDescription)"
        }
    }

    /// A binding that writes the config on every change.
    func binding<Value>(_ keyPath: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(get: { self.config[keyPath: keyPath] },
                set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    func setLeader(_ hotkey: Hotkey) {
        update { $0.leader = hotkey }
    }

    /// nil removes the separate launcha hotkey.
    func setLaunchaHotkey(_ hotkey: Hotkey?) {
        update { $0.launcha.hotkey = hotkey }
    }

    /// nil removes the clipboarda hotkey.
    func setClipboardaHotkey(_ hotkey: Hotkey?) {
        update { $0.clipboarda.hotkey = hotkey }
    }

    /// Saves exactly the retained app selected in launcha, never a different bundle-ID match.
    func setAppShortcut(for row: LaunchaRow, hotkey: Hotkey?) throws {
        guard case .app(let id) = row.kind else { throw AppShortcutRules.Problem.invalidTarget }
        var next = config
        if let hotkey {
            let shortcut = AppShortcut(id: id, name: row.name, path: row.url.path, hotkey: hotkey)
            try AppShortcutRules.assign(shortcut, in: &next)
            // The editor suspends Ting's registrations first. OS conflicts fail without a save.
            if isRecordingHotkey, let error = hotkeys.checkAvailable(hotkey) {
                throw NSError(domain: "io.bobuk.ting.shortcuts", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: error])
            }
        } else { next.appHotkeys.removeAll { $0.id == id } }
        try store.write(next)
        configError = nil
        apply(next)
    }

    private func refreshAppShortcutProblems() {
        var problems: [String: String] = [:]
        for (index, shortcut) in activeAppShortcuts.enumerated() {
            if case .failed(let reason) = hotkeys.status(.application(index)) { problems[shortcut.id] = reason }
        }
        launcha.chrome.appShortcutProblems = problems
    }

    /// Turns all hotkeys off until `owner` ends recording. A new recording cancels the
    /// previous one; the hotkeys stay off between them.
    func beginHotkeyRecording(_ owner: HotkeyRecordingOwner) {
        recordingGate.begin(owner)
    }

    /// Turns the hotkeys back on only if `owner` is the current recording.
    func endHotkeyRecording(_ owner: HotkeyRecordingOwner) {
        recordingGate.end(owner)
    }

    private func setRecordingHotkey(_ recording: Bool) {
        guard recording != isRecordingHotkey else { return }
        isRecordingHotkey = recording
        applyHotkey()
    }

    // MARK: launcha

    func openLauncha() {
        guard !isPaused, !isRecordingHotkey else { return }
        leader.close()
        launcha.open()
    }

    func openClipboarda() {
        guard !isPaused, !isRecordingHotkey else { return }
        guard config.clipboarda.enabled else {
            toast.show("clipboarda is off. Turn it on in Settings › clipboarda.")
            return
        }
        leader.close()
        launcha.close()
        clipboardaPanel.open()
    }

    /// Call only after the user read what this allows and which macOS prompts may follow.
    func setProtectedFoldersAllowed(_ allowed: Bool) {
        if allowed { launchaModel.allowProtectedFolders() } else { launchaModel.revokeProtectedFolders() }
    }

    func replaceConfig(_ imported: Config) {
        update { $0 = imported }
    }

    // MARK: Bindings

    func insertBinding(_ item: Item, at sequence: [String]) throws {
        var items = config.items
        try BindingTree.insert(item, at: sequence, in: &items)
        update { $0.items = items }
    }

    func moveBinding(from: [String], to: [String]) throws {
        var items = config.items
        try BindingTree.move(from: from, to: to, in: &items)
        update { $0.items = items }
    }

    func convertToGroup(at prefix: [String]) {
        update { try? BindingTree.convertToGroup(at: prefix, in: &$0.items) }
    }

    func updateBinding(at sequence: [String], _ change: (inout Item) -> Void) {
        update { try? BindingTree.update(at: sequence, in: &$0.items, change) }
    }

    func removeBindings(_ sequences: [[String]]) {
        // Deepest first, so removing a child before its group still works.
        update { config in
            for sequence in sequences.sorted(by: { $0.count > $1.count }) {
                try? BindingTree.remove(at: sequence, in: &config.items)
            }
        }
    }

    // MARK: Config file

    func openConfigFile() {
        let url = store.url
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil, NSWorkspace.shared.open(url) { return }
        // No app claims .json: fall back to TextEdit.
        guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    // MARK: Private

    private func apply(_ next: Config) {
        let previous = config
        config = next
        issues = ConfigValidator.validate(next)
        runner.prepare(next.items)
        leader.configure(next)
        launcha.configure(next)
        clipboarda.configure(next.clipboarda)
        clipboardaPanel.configure(next)
        microFlow.configure(next)
        // Binding labels name the micro-apps in launcha.
        launchaModel.setMicroApps(microCatalog.launchaCandidates(bindings: next.items), folder: microStore.folderURL)
        next.appearance.apply()
        applyHotkey()
        if next.launchAtLogin != previous.launchAtLogin {
            loginItemError = LoginItemService.set(next.launchAtLogin)
        }
    }

    private func applyHotkey() {
        let wanted = isPaused || isRecordingHotkey ? [] : AppShortcutRules.active(in: config)
        hotkeys.prepareApplications(wanted)
        activeAppShortcuts = wanted
        if isPaused || isRecordingHotkey {
            leader.close()
            clipboardaPanel.close()
            if isPaused || launcha.chrome.shortcutEditor == nil { launcha.close() }
            hotkeys.activate(nil, for: .launcha)
            hotkeys.activate(nil, for: .clipboarda)
            hotkeys.activate(nil, for: .leader)
        } else {
            // The leader wins a conflict, then launcha: free the other slots first.
            let separate = config.launcha.hotkey.flatMap { $0.isValid && $0 != config.leader ? $0 : nil }
            let clipboard = config.clipboarda.activeHotkey.flatMap {
                $0.isValid && $0 != config.leader && $0 != config.launcha.hotkey ? $0 : nil
            }
            if hotkeys.hotkey(.launcha) != separate { hotkeys.activate(nil, for: .launcha) }
            if hotkeys.hotkey(.clipboarda) != clipboard { hotkeys.activate(nil, for: .clipboarda) }
            hotkeys.activate(config.leader, for: .leader)
            hotkeys.activate(separate, for: .launcha)
            hotkeys.activate(clipboard, for: .clipboarda)
            hotkeys.activateApplications(wanted)
        }
        refreshAppShortcutProblems()
        hotkeyStatus = hotkeys.status(.leader)
        launchaHotkeyStatus = hotkeys.status(.launcha)
        clipboardaHotkeyStatus = hotkeys.status(.clipboarda)
    }

    func hotkeyReleased(_ slot: HotkeyService.Slot) {
        switch slot {
        case .leader: leader.leaderReleased()
        case .launcha: launchaKey.release()
        case .clipboarda: clipboardaKey.release()
        case .application: break
        }
    }

    func hotkeyPressed(_ slot: HotkeyService.Slot, at time: TimeInterval) {
        guard !isMenuTracking else { return }
        switch slot {
        case .leader:
            // The leader switches from launcha back to selecta. A repeat of a held leader
            // is ignored and leaves launcha open.
            leader.leaderPressed(at: time) { [launcha] in
                if launcha.isOpen { launcha.close() }
            }
        case .application(let index):
            guard !isPaused, !isRecordingHotkey, activeAppShortcuts.indices.contains(index) else { return }
            let shortcut = activeAppShortcuts[index]
            leader.close()
            launcha.close()
            playSound()
            Task { [runner, launchaModel] in
                let outcome = await runner.openApp(at: URL(fileURLWithPath: shortcut.path), name: shortcut.name)
                await launchaModel.record(outcome, id: shortcut.id)
            }
        case .launcha:
            guard launchaKey.press(at: time, menuOpen: false, menuOpenAtRoot: false) != .ignored else { return }
            if leader.isOpen { leader.close() }
            launcha.toggle()
        case .clipboarda:
            guard !isPaused, !isRecordingHotkey, config.clipboarda.enabled,
                  clipboardaKey.press(at: time, menuOpen: false, menuOpenAtRoot: false) != .ignored else { return }
            if leader.isOpen { leader.close() }
            if launcha.isOpen { launcha.close() }
            clipboardaPanel.toggle()
        }
    }

    func beginMenuTracking() {
        isMenuTracking = true
        leader.keysSuspended = true
        launcha.keysSuspended = true
        clipboardaPanel.keysSuspended = true
    }

    /// The menu ended. A launcher takes keys again unless a chosen item opened another window.
    func endMenuTracking() {
        isMenuTracking = false
        leader.resumeKeys()
        launcha.resumeKeys()
        clipboardaPanel.resumeKeys()
    }

    /// The "ting" for an opened app, link or file: `config.sound` at `config.soundVolume`.
    private func playSound() {
        if config.playSound { previewSound() }
    }

    /// Plays the configured sound once, whatever `playSound` says (the Settings preview).
    /// A name that cannot be loaded plays the default "Tink".
    func previewSound() {
        guard let sound = loadSound(config.sound) ?? loadSound(SystemSounds.defaultName) else { return }
        sound.stop()
        sound.volume = Float(config.soundVolume)
        sound.play()
    }

    private func loadSound(_ name: String) -> NSSound? {
        if let cached = sounds[name] { return cached }
        let sound = NSSound(named: NSSound.Name(name))
        sounds[name] = sound
        return sound
    }

    /// Opens a selecta binding and counts a successful launch once. A micro-app binding starts
    /// its flow; a missing or broken micro-app only shows its error.
    private func run(_ item: Item) {
        if case .micro(let id) = item.action {
            microFlow.start(id: id)
            return
        }
        if case .open(let panel) = item.action {
            // The leader panel is closing: open once it has handed the keyboard back.
            DispatchQueue.main.async { [weak self] in
                switch panel {
                case .launcha: self?.openLauncha()
                case .clipboarda: self?.openClipboarda()
                }
            }
            return
        }
        playSound()
        let id: String? = switch item.action {
        case .app(let bundleID): LaunchaCandidate.app(bundleID: bundleID, name: "").id
        case .url(let url): LaunchaCandidate.url(url, name: "").id
        case .group, .micro, .open: nil
        }
        let activated = runner.activateRunning(item)
        Task {
            let outcome: LaunchOutcome
            if let activated { outcome = activated } else { outcome = await runner.run(item) }
            if let id { await launchaModel.record(outcome, id: id) }
        }
    }
}
