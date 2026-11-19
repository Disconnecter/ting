import AppKit
import SwiftUI
import TingCore

/// BobukKit is the window surface itself, not a card inside a native titled window.
@MainActor
final class SettingsWindow: NSWindow {
    init(size: NSSize = NSSize(width: 1040, height: 720)) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .closable, .resizable], backing: .buffered, defer: false)
        title = "Ting Settings" // Accessibility/Mission Control only; no titlebar is drawn.
        identifier = NSUserInterfaceItemIdentifier("io.bobuk.ting.settings")
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        contentMinSize = NSSize(width: 900, height: 600)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // AppKit's default performClose requires a native titlebar button. This window has none.
    override func performClose(_ sender: Any?) {
        guard delegate?.windowShouldClose?(self) != false else { return }
        close()
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private(set) var window: SettingsWindow?
    private let model: AppModel
    private let remembersFrame: Bool
    private static let frameName = "io.bobuk.ting.settings.frame"

    init(model: AppModel, remembersFrame: Bool = true) {
        self.model = model
        self.remembersFrame = remembersFrame
    }

    func show(activate: Bool = true) {
        let window = self.window ?? makeWindow()
        if activate {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderBack(nil)
        }
    }

    func close() { window?.performClose(nil) }

    /// Destroy the view on close so shortcut recording cannot keep intercepting keys.
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }

    private func makeWindow() -> SettingsWindow {
        let window = SettingsWindow()
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsRoot().environment(model))
        if remembersFrame {
            if !window.setFrameUsingName(Self.frameName) { window.center() }
            window.setFrameAutosaveName(Self.frameName)
        } else {
            window.center()
        }
        self.window = window
        return window
    }
}
