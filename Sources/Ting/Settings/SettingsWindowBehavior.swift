import AppKit
import SwiftUI

/// The app owns titled-window behavior; BobukKit only renders its content surface.
/// Explicitly keep native closing available, including in standalone review hosts.
@MainActor
struct SettingsWindowBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> Host { Host() }
    func updateNSView(_ view: Host, context: Context) { view.configureWindow() }

    final class Host: NSView {
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
            guard let window, window.styleMask.contains(.titled) else { return }
            if !window.styleMask.contains(.closable) { window.styleMask.insert(.closable) }
            window.standardWindowButton(.closeButton)?.isEnabled = true
        }
    }
}
