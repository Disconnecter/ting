import AppKit
import SwiftUI
import XCTest
import TingCore
import BobukUI
@testable import Ting

/// The Settings window is BobukKit's `ChromeWindow`: the strip's close button and ⌘W are its only
/// close controls. The window is ordered behind the user's windows and never takes focus.
@MainActor
final class SettingsWindowTests: XCTestCase {
    private func model() -> (AppModel, URL) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json"))), directory)
    }

    func testChromeWindowInTingColorsWithTheContentInItsBody() async throws {
        let (model, _) = model()
        let controller = SettingsWindowController(model: model, remembersFrame: false)
        defer { controller.close() }
        controller.show(activate: false)
        let window = try XCTUnwrap(controller.window as? ChromeWindow)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(window.title, "Ting Settings")
        XCTAssertEqual(window.identifier, SettingsWindow.identifier)
        XCTAssertTrue(window.styleMask.contains(.titled), "a real window: native corners, shadow and resizing")
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.chromeStyle, TingPickerStyle.palette.chromeStyle)
        XCTAssertEqual(window.contentMinSize, ChromeMetrics.windowSize(forBody: NSSize(width: 900, height: 600)))
        XCTAssertNil(window.toolbar)
        XCTAssertFalse(window.isKeyWindow)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(type) {
                XCTAssertTrue(button.superview == nil || button.isHiddenOrHasHiddenAncestor)
            }
        }
        XCTAssertEqual(window.strip.buttons.count, 1, "the strip's close button is the only window control")
        XCTAssertEqual(window.closeButton.label, "Close · ⌘W")
        let hosting = try XCTUnwrap(window.body.subviews.first)
        XCTAssertEqual(hosting.frame, window.body.bounds, "the content fills the body")
        let views = descendants(hosting)
        XCTAssertFalse(views.contains { $0 is PickerSurfaceView }, "the window draws the chrome, not a panel inside it")
        XCTAssertFalse(views.contains { $0 is NSSplitView }, "no split controller can collapse the column")
        controller.show(activate: false)
        XCTAssertTrue(controller.window === window, "all opens reuse one window")
    }

    func testStripCloseAndCommandWCloseWhileSearchIsFocusedAndReleaseTheContent() async throws {
        let (model, _) = model()
        let controller = SettingsWindowController(model: model, remembersFrame: false)
        defer { controller.close() }
        for command in [false, true] {
            controller.show(activate: false)
            let window = try XCTUnwrap(controller.window as? ChromeWindow)
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            let search = try XCTUnwrap(descendants(window.body).first { $0 is NSSearchField } as? NSSearchField)
            XCTAssertTrue(window.makeFirstResponder(search))
            if command {
                // A key equivalent given to the window directly, never a system or synthetic key press.
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "w",
                    charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
                XCTAssertTrue(window.performKeyEquivalent(with: event))
            } else {
                window.closeButton.performPress()
            }
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertFalse(window.isVisible)
            XCTAssertNil(controller.window)
            XCTAssertTrue(window.body.subviews.isEmpty, "release the view and any shortcut recorder on close")
        }
    }

    /// BobukKit 0.2.1 routes ⌘A/⌘C/⌘V/⌘X/⌘Z by the Latin key to the window's first responder;
    /// other ⌘ keys stay with the app menu. No pasteboard is touched.
    func testEditCommandsReachTheFocusedSearchField() async throws {
        let (model, _) = model()
        let controller = SettingsWindowController(model: model, remembersFrame: false)
        defer { controller.close() }
        controller.show(activate: false)
        let window = try XCTUnwrap(controller.window as? ChromeWindow)
        XCTAssertTrue(window.routesEditCommands)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
        let search = try XCTUnwrap(descendants(window.body).first { $0 is NSSearchField } as? NSSearchField)
        search.stringValue = "days"
        XCTAssertTrue(window.makeFirstResponder(search))
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        func command(_ name: String) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: name,
                                           charactersIgnoringModifiers: name, isARepeat: false,
                                           keyCode: KeyCodes.code(for: name)!))
        }
        XCTAssertTrue(window.performKeyEquivalent(with: try command("a")))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 4))
        XCTAssertFalse(window.performKeyEquivalent(with: try command("q")), "⌘Q is left to the app menu")
        XCTAssertTrue(window.isVisible)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
