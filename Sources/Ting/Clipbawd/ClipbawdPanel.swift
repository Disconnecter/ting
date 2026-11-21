// The clipbawd window: a non-activating panel like launcha, so the app in front keeps its
// place and ↩ pastes into it. Search on top, the history on the left, the preview on the right.
import AppKit
import ImageIO
import SwiftUI
import TingCore
import BobukUI
import BobukSystem

/// A `BobukPanel` like launcha's, with ⌘↩ copying and ⇧⌘⌫ removing the selected item; ⌘⌫ still
/// erases the search text, as in launcha.
final class ClipbawdPanel: BobukPanel {
    static let width: CGFloat = 800

    var onMove: ((Int) -> Void)?
    /// ⌘↩: copy without pasting.
    var onCopy: (() -> Void)?
    /// ⇧⌘⌫: remove the selected item.
    var onDelete: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 600), kind: .launcher)
        // The card draws its own SwiftUI shadow.
        hasShadow = false
        onCommandKey = { [unowned self] event, command in self.handleCommand(event, command) }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let onMove,
           let delta = LaunchaPanel.navigationDelta(keyCode: event.keyCode, flags: event.modifierFlags,
                                                   composing: KeyEquivalent.isComposing(in: self)) {
            onMove(delta)
            return
        }
        super.sendEvent(event)
    }

    /// clipbawd's own ⌘ shortcuts, on top of BobukPanel's edit routing.
    enum Command: Equatable {
        /// ⌘↩: copy without pasting.
        case copy
        /// ⇧⌘⌫: remove the selected item.
        case delete
    }

    /// nil leaves the key to BobukPanel (text commands, ⌘⌫ in the field, ⌘W, swallowing the rest).
    static func command(_ command: EditCommand, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Command? {
        if command == .commandReturn { return .copy }
        if flags.intersection([.command, .shift, .option, .control]) == [.command, .shift],
           keyCode == VirtualKey.delete { return .delete }
        return nil
    }

    private func handleCommand(_ event: NSEvent, _ command: EditCommand) -> Bool {
        guard let shortcut = Self.command(command, keyCode: event.keyCode, flags: event.modifierFlags) else { return false }
        // While an input method composes, the key is swallowed and does nothing.
        guard !KeyEquivalent.isComposing(in: self) else { return true }
        switch shortcut {
        case .copy: onCopy?()
        case .delete: onDelete?()
        }
        return true
    }
}

/// What the clipbawd window shows: the search, the selection and the presentation settings.
@MainActor
@Observable
final class ClipbawdState {
    let history: ClipbawdHistory
    var query = ""
    var selectedID: Int?
    var showHeader = true
    var isRecording = true
    /// The real keys that open clipbawd, for the footer.
    var shortcut = ""
    var listHeight: CGFloat = 380
    /// Bumped on every open to move focus into the search field.
    var focusToken = 0
    var isOpen = false
    @ObservationIgnored let images = ClipImageCache()

    init(history: ClipbawdHistory) { self.history = history }

    /// The matching items, newest first.
    var results: [ClipEntry] { history.history.search(query) }

    /// The selected item; the first result when the selection is gone.
    var selected: ClipEntry? {
        let results = results
        return results.first { $0.id == selectedID } ?? results.first
    }

    func select(_ id: Int) { selectedID = id }

    func move(by delta: Int) {
        let results = results
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selected?.id } ?? 0
        if let next = PickerSelection.move(current, by: delta, count: results.count) {
            selectedID = results[next].id
        }
    }

    /// Removes the selected item and selects the one after it.
    func removeSelected() {
        let results = results
        guard let selected, let index = results.firstIndex(where: { $0.id == selected.id }) else { return }
        let next = results.indices.contains(index + 1) ? results[index + 1] : index > 0 ? results[index - 1] : nil
        history.remove(id: selected.id)
        selectedID = next?.id
    }
}

/// Shows and hides the clipbawd panel, and pastes or copies the chosen item.
@MainActor
final class ClipbawdController: NSObject {
    let state: ClipbawdState
    private var panel: ClipbawdPanel?
    private var observers: [NSObjectProtocol] = []
    private let presentsWindow: Bool
    private let keyboard: MicroAppKeyboard
    /// The app that was in front at open: ↩ pastes into it.
    private(set) var target: MicroAppTarget?

    var onWillOpen: (() -> Void)?
    /// A paste failed; the error says why (Accessibility, secure input, the app is gone).
    var onPasteError: ((Error) -> Void)?
    var onToast: ((String) -> Void)?
    /// "Never Keep from <app>" was chosen.
    var onExclude: ((ClipSource) -> Void)?

    var isOpen: Bool { state.isOpen }

    init(history: ClipbawdHistory, presentsWindow: Bool = true, keyboard: MicroAppKeyboard? = nil) {
        state = ClipbawdState(history: history)
        self.presentsWindow = presentsWindow
        self.keyboard = keyboard ?? MicroAppKeyboard()
        super.init()
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
        state.showHeader = config.showPanelHeader
        state.isRecording = config.clipbawd.enabled
        state.shortcut = config.clipbawd.activeHotkey.flatMap { $0.isValid ? $0.display : nil } ?? ""
        if !config.clipbawd.enabled { close() }
    }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard !isOpen else { return }
        target = MicroAppTarget.frontmost()
        state.query = ""
        state.selectedID = nil
        state.isOpen = true
        onWillOpen?()
        guard presentsWindow else { return }
        let panel = self.panel ?? makePanel()
        if let visible = Screens.underPointer?.visibleFrame {
            let top = PanelPlacement.top(in: visible, anchor: .upper())
            let height = max(320, min(640, top - visible.minY - 20))
            let width = min(ClipbawdPanel.width, visible.width - 40)
            panel.setFrame(NSRect(x: visible.midX - width / 2, y: top - height, width: width, height: height), display: false)
            // Header, input and footer take about 190 points.
            state.listHeight = max(200, min(420, height - 200))
        }
        state.focusToken += 1
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        guard isOpen else { return }
        state.isOpen = false
        panel?.orderOut(nil)
    }

    /// ↩ pastes into the app that was in front; ⌘↩ (`paste` false) only copies.
    func choose(id: Int? = nil, paste: Bool) {
        guard isOpen, let entry = id.flatMap(state.history.history.entry(id:)) ?? state.selected else { return }
        guard state.history.copy(id: entry.id) else { return }
        let target = self.target
        close()
        guard paste else {
            onToast?("Copied \(entry.title.count > 40 ? String(entry.title.prefix(40)) + "…" : entry.title)")
            return
        }
        Task { [keyboard, weak self] in
            do { try await keyboard.pressPaste(in: target) }
            catch { self?.onPasteError?(error) }
        }
    }

    func removeSelected() {
        guard isOpen else { return }
        state.removeSelected()
    }

    func exclude(_ source: ClipSource) {
        onExclude?(source)
        state.focusToken += 1
    }

    private func makePanel() -> ClipbawdPanel {
        let panel = ClipbawdPanel()
        // Focus loss, Esc and ⌘W close the open panel (not while a menu tracks over it).
        panel.onDismiss = { [weak self] _ in
            guard let self, self.isOpen else { return }
            self.close()
        }
        panel.onMove = { [weak self] delta in self?.state.move(by: delta) }
        panel.onCopy = { [weak self] in self?.choose(paste: false) }
        panel.onDelete = { [weak self] in self?.removeSelected() }
        let view = ClipbawdView(state: state,
                                  onChoose: { [weak self] id, paste in self?.choose(id: id, paste: paste) },
                                  onDismiss: { [weak self] in self?.close() },
                                  onExclude: { [weak self] source in self?.exclude(source) })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    /// While a menu tracks over the panel, losing key status keeps it open.
    func suspendKeys() { panel?.suspendDismissal() }

    /// The menu is gone: take keys again, or close if another window took focus meanwhile.
    func resumeKeys() { panel?.resumeDismissal() }
}

/// Small pictures of copied images and favicons, made off the main thread from the image header
/// and a downsampled decode, never from the full image.
@MainActor
final class ClipImageCache {
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 300 }

    func image(_ data: Data, key: String, maxPixels: Int) async -> NSImage? {
        let cacheKey = "\(key)@\(maxPixels)" as NSString
        if let image = cache.object(forKey: cacheKey) { return image }
        let cgImage = await Task.detached(priority: .userInitiated) { Self.thumbnail(data, maxPixels: maxPixels) }.value
        guard let cgImage else { return nil }
        let image = Self.displayImage(cgImage)
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    func filePreview(_ files: [ClipFile], maxPixels: Int) async -> NSImage? {
        guard files.count == 1, let file = files.first, !file.isDirectory else { return nil }
        let url = URL(fileURLWithPath: file.path)
        guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else { return nil }
        let cgImage = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return Self.thumbnail(source, maxPixels: maxPixels)
        }.value
        return cgImage.map(Self.displayImage)
    }

    private static func displayImage(_ cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    nonisolated static func thumbnail(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source, maxPixels: maxPixels)
    }

    private nonisolated static func thumbnail(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
