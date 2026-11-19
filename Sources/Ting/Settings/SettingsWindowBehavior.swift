import AppKit
import SwiftUI

@MainActor
final class SettingsWindowReference {
    weak var window: NSWindow?
    func close() { window?.performClose(nil) }
}

/// Connect in-surface controls to their own host, never NSApp.keyWindow or another app.
@MainActor
struct SettingsWindowBehavior: NSViewRepresentable {
    let reference: SettingsWindowReference

    func makeNSView(context: Context) -> Host {
        let view = Host()
        view.reference = reference
        return view
    }

    func updateNSView(_ view: Host, context: Context) {
        view.reference = reference
        view.configureWindow()
    }

    final class Host: NSView {
        var reference: SettingsWindowReference?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w", let window {
                window.performClose(nil)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        func configureWindow() {
            reference?.window = window
            guard let window else { return }
            if !window.styleMask.contains(.closable) { window.styleMask.insert(.closable) }
        }
    }
}
