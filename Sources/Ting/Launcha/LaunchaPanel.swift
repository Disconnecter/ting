// The launcha window: a non-activating panel with a real text input. Unlike the selecta
// panel it never routes keys to the sequence handler, so typing, paste and input methods work.
import AppKit
import BobukUI
import SwiftUI
import TingCore
import BobukSystem

extension Notification.Name {
    static let launchaEditAppShortcut = Notification.Name("io.bobuk.ting.launcha.editAppShortcut")
    static let launchaRemoveAppShortcut = Notification.Name("io.bobuk.ting.launcha.removeAppShortcut")
}

/// A `BobukPanel`: it closes on focus loss, Esc and ⌘W, sends ⌘C/⌘V/⌘X/⌘A/⌘Z to the field by
/// the Latin layout and swallows other ⌘ shortcuts (⌘Q). launcha adds ⇧⌘K and ⌘↩.
final class LaunchaPanel: BobukPanel {
    /// ⌘↩: show the selected result in Finder.
    var onReveal: (() -> Void)?
    /// List navigation must keep working when Tab moves focus away from the search field.
    var onMove: ((Int) -> Void)?
    var onEditShortcut: (() -> Void)?
    /// ⌘,: open Settings.
    var onOpenSettings: (() -> Void)?
    /// Returns true only while the inline recorder owns the panel's key events.
    var onRecordShortcut: ((NSEvent) -> Bool)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600), kind: .launcher)
        // The card draws its own SwiftUI shadow.
        hasShadow = false
        onCommandKey = { [unowned self] event, command in self.handleCommand(event, command) }
    }

    static func navigationDelta(keyCode: UInt16, flags: NSEvent.ModifierFlags, composing: Bool) -> Int? {
        guard !composing, flags.intersection([.command, .shift, .option, .control]).isEmpty else { return nil }
        switch keyCode {
        case VirtualKey.up: return -1
        case VirtualKey.down: return 1
        case VirtualKey.pageUp: return -8
        case VirtualKey.pageDown: return 8
        default: return nil
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if (event.type == .keyDown || event.type == .flagsChanged), onRecordShortcut?(event) == true { return }
        if event.type == .keyDown, let onMove,
           let delta = Self.navigationDelta(keyCode: event.keyCode, flags: event.modifierFlags,
                                           composing: KeyEquivalent.isComposing(in: self)) {
            onMove(delta)
            return
        }
        super.sendEvent(event)
    }

    /// launcha's own ⌘ shortcuts, on top of BobukPanel's edit routing.
    enum Command: Equatable {
        /// ⇧⌘K: record a shortcut for the selected app.
        case editShortcut
        /// ⌘↩: show the selected result in Finder.
        case reveal
        /// ⌘,: open Settings.
        case settings
    }

    /// The launcha shortcut of a ⌘ key, matched by the Latin layout; nil leaves the key to
    /// BobukPanel (text commands, ⌘W, swallowing the rest).
    static func command(_ command: EditCommand, latin: String?, flags: NSEvent.ModifierFlags) -> Command? {
        if latin == "k", flags.intersection([.command, .shift, .option, .control]) == [.command, .shift] { return .editShortcut }
        if SettingsOpener.isShortcut(latin: latin, flags: flags) { return .settings }
        return command == .commandReturn ? .reveal : nil
    }

    private func handleCommand(_ event: NSEvent, _ command: EditCommand) -> Bool {
        // The inline recorder takes every key first, including ⌘Q.
        if onRecordShortcut?(event) == true { return true }
        guard let shortcut = Self.command(command, latin: KeyEquivalent.latin(of: event), flags: event.modifierFlags) else {
            return false
        }
        // While an input method composes, the key is swallowed and does nothing.
        guard !KeyEquivalent.isComposing(in: self) else { return true }
        switch shortcut {
        case .editShortcut: onEditShortcut?()
        case .reveal: onReveal?()
        case .settings:
            if !event.isARepeat { onOpenSettings?() }
        }
        return true
    }
}

/// Presentation settings of the launcha panel, from the config.
@MainActor
@Observable
final class LaunchaChrome {
    var showHeader = true
    /// Tooltip and spoken label of the double tuning fork: the real keys that open launcha.
    var tokenDescription = "Open launcha"
    var leader = ""
    var maxListHeight: CGFloat = 360
    /// Bumped on every open to move focus into the search field.
    var focusToken = 0
    var appHotkeys: [AppShortcut] = []
    var appShortcutProblems: [String: String] = [:]
    var shortcutEditor: LaunchaShortcutEditor?
    @ObservationIgnored let icons = LaunchaIconCache()
}

/// Shows and hides the launcha panel for `LaunchaModel`.
@MainActor
final class LaunchaController: NSObject {
    let model: LaunchaModel
    let chrome = LaunchaChrome()
    private var panel: LaunchaPanel?
    private var observers: [NSObjectProtocol] = []
    private var config = Config()
    var onBeginShortcutRecording: ((HotkeyRecordingOwner) -> Void)?
    var onEndShortcutRecording: ((HotkeyRecordingOwner) -> Void)?
    var onSaveShortcut: ((LaunchaRow, Hotkey?) throws -> Void)?
    /// ⌘, in the panel.
    var onOpenSettings: (() -> Void)?

    var isOpen: Bool { model.isOpen }

    /// Tests exercise the controller without showing a window or taking keyboard focus.
    private let presentsWindow: Bool

    init(model: LaunchaModel, presentsWindow: Bool = true) {
        self.model = model
        self.presentsWindow = presentsWindow
        super.init()
        model.onRequestClose = { [weak self] in self?.hidePanel() }
        // A Space change leaves the panel behind on the old Space: close it.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
    }

    func configure(_ config: Config) {
        self.config = config
        chrome.appHotkeys = config.appHotkeys
        chrome.showHeader = config.showPanelHeader
        chrome.leader = config.leaderDisplay
        chrome.tokenDescription = Self.tokenDescription(config)
        model.calculator = config.launcha.calculator
        model.converter = config.launcha.converter
        model.runningApps = config.launcha.runningApps
        model.appSwitching = config.launcha.appSwitching
    }

    /// The real keys that open launcha, e.g. "Open launcha: ⌥Space pressed twice, or ⌘K".
    static func tokenDescription(_ config: Config) -> String {
        var ways: [String] = []
        let keys = HotkeyAssignments(config).launchers
        if config.launcha.doubleTap {
            for slot in [LauncherHotkey.leader, .alternateLeader] {
                if let key = keys[slot] { ways.append("\(key.display) pressed twice") }
            }
        }
        if let hotkey = keys[.launcha] { ways.append(hotkey.display) }
        return ways.isEmpty ? "Open launcha" : "Open launcha: " + ways.joined(separator: ", or ")
    }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard !isOpen else { return }
        guard presentsWindow else {
            model.open()
            return
        }
        let panel = self.panel ?? makePanel()
        if let visible = Screens.underPointer?.visibleFrame {
            // Card near the upper third, so it does not jump while the list grows.
            let top = PanelPlacement.top(in: visible, anchor: .upper())
            let height = max(240, min(640, top - visible.minY - 20))
            let width: CGFloat = 520
            panel.setFrame(NSRect(x: visible.midX - width / 2, y: top - height, width: width, height: height), display: false)
            // Header, input, footer and notices take about 200 points.
            chrome.maxListHeight = max(120, min(420, height - 220))
        }
        model.open()
        chrome.focusToken += 1
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        chrome.shortcutEditor?.cancel()
        hidePanel()
        model.close()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    func editShortcut(for row: LaunchaRow? = nil) {
        guard isOpen, let row = row ?? model.selectedRow, row.isApp else { return }
        chrome.shortcutEditor?.cancel()
        let original = config.appHotkeys.first { $0.id == row.id }?.hotkey
        let editor = LaunchaShortcutEditor(row: row, original: original)
        editor.validate = { [weak self] hotkey in
            guard let self else { return "The launcher closed." }
            return AppShortcutRules.problem(for: hotkey, in: self.config)?.description
        }
        editor.persist = { [weak self] hotkey in
            guard let self, let save = self.onSaveShortcut else {
                throw NSError(domain: "io.bobuk.ting.shortcuts", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot save this shortcut."])
            }
            try save(row, hotkey)
        }
        editor.replacing = { [weak self] hotkey in
            self?.config.appHotkeys.first { $0.id != row.id && $0.hotkey == hotkey }?.name
        }
        editor.onFinish = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.chrome.shortcutEditor = nil
            self.onEndShortcutRecording?(editor)
            self.chrome.focusToken += 1
        }
        chrome.shortcutEditor = editor
        onBeginShortcutRecording?(editor)
    }

    private func makePanel() -> LaunchaPanel {
        let panel = LaunchaPanel()
        // Focus loss, Esc and ⌘W close the open launcher (not while a menu tracks over it).
        panel.onDismiss = { [weak self] _ in
            guard let self, self.isOpen else { return }
            self.close()
        }
        panel.onReveal = { [weak self] in self?.activate(reveal: true) }
        panel.onMove = { [weak self] delta in self?.model.moveSelection(by: delta) }
        panel.onEditShortcut = { [weak self] in self?.editShortcut() }
        panel.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        observers.append(NotificationCenter.default.addObserver(
            forName: .launchaEditAppShortcut, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let id = notification.object as? String,
                          let row = self.model.rows.first(where: { $0.id == id }) else { return }
                    self.editShortcut(for: row)
                }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: .launchaRemoveAppShortcut, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let id = notification.object as? String,
                          let row = self.model.rows.first(where: { $0.id == id }) else { return }
                    do { try self.onSaveShortcut?(row, nil) }
                    catch { self.chrome.appShortcutProblems[id] = error.localizedDescription }
                }
            })
        panel.onRecordShortcut = { [weak self] event in
            guard let editor = self?.chrome.shortcutEditor else { return false }
            return editor.handlePanelEvent(event)
        }
        let view = LaunchaView(model: model, chrome: chrome,
                               onActivate: { [weak self] reveal in self?.activate(reveal: reveal) },
                               onDismiss: { [weak self] in self?.close() },
                               onEditShortcut: { [weak self] row in self?.editShortcut(for: row) })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    private func activate(reveal: Bool) {
        guard isOpen, chrome.shortcutEditor == nil else { return }
        Task { await model.activateSelection(reveal: reveal) }
    }

    /// While a menu tracks over the panel, losing key status keeps it open.
    func suspendKeys() { panel?.suspendDismissal() }

    /// The menu is gone: take keys again, or close if another window took focus meanwhile.
    func resumeKeys() { panel?.resumeDismissal() }
}
