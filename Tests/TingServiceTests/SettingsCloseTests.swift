import AppKit
import SwiftUI
import XCTest
import TingCore
@testable import Ting

@MainActor
final class SettingsCloseTests: XCTestCase {
    func testNativeCloseAndCommandWWithSearchFocused() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")))
        for command in [false, true] {
            let hosting = NSHostingView(rootView: SettingsRoot().environment(model))
            // Reproduce the review host that originally forgot .closable.
            let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1040, height: 720),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            XCTAssertFalse(window.styleMask.contains(.closable))
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertTrue(window.styleMask.contains(.closable))
            let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
            XCTAssertTrue(close.isEnabled)
            let search = try XCTUnwrap(descendants(hosting).first { $0 is NSSearchField } as? NSSearchField)
            XCTAssertTrue(window.makeFirstResponder(search))
            XCTAssertFalse(window.isKeyWindow, "Review/testing must not take the user's focus.")
            if command {
                // Invoke a local menu key equivalent, never a system/synthetic key press.
                let menu = NSMenu()
                let item = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
                item.keyEquivalentModifierMask = .command
                item.target = window
                menu.addItem(item)
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "w",
                    charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
                XCTAssertTrue(menu.performKeyEquivalent(with: event))
            } else {
                close.performClick(nil)
            }
            XCTAssertFalse(window.isVisible)
        }
    }

    func testWindowCommandWClosesEvenWithoutApplicationMenu() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")))
        let hosting = NSHostingView(rootView: SettingsRoot().environment(model))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1040, height: 720),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let search = try XCTUnwrap(descendants(hosting).first { $0 is NSSearchField } as? NSSearchField)
        XCTAssertTrue(window.makeFirstResponder(search))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "w",
            charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertFalse(window.isVisible)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
