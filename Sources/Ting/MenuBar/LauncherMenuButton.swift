import AppKit
import SwiftUI

/// A small native button anchors the shared status menu without taking search focus.
struct LauncherMenuButton: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!,
                              target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        button.contentTintColor = NSColor(Color.tingMuted)
        button.focusRingType = .none
        button.refusesFirstResponder = true
        button.toolTip = "Ting menu"
        button.setAccessibilityLabel("Ting menu")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        @objc func openMenu(_ sender: NSButton) {
            StatusItemController.current?.popUp(from: sender)
        }
    }
}
