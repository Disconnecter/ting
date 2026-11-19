import AppKit
import SwiftUI
import XCTest
import TingCore
import BobukUI
@testable import Ting

@MainActor
final class SettingsBorderlessWindowTests: XCTestCase {
    func testKitSurfaceIsTheWholeWindowWithoutNativeChrome() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")))
        let controller = SettingsWindowController(model: model, remembersFrame: false)
        defer { controller.close() }
        controller.show(activate: false)
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor?.alphaComponent, 0)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertNil(window.toolbar)
        XCTAssertFalse(window.isKeyWindow)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(type) {
                XCTAssertTrue(button.superview == nil || button.isHiddenOrHasHiddenAncestor)
            }
        }
        let content = try XCTUnwrap(window.contentView)
        let surface = try XCTUnwrap(descendants(content).compactMap { $0 as? PickerSurfaceView }.first)
        XCTAssertEqual(surface.convert(surface.bounds, to: content), content.bounds, "No padded second frame around the kit.")
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, window.frame.size, "No titlebar reservation.")
        controller.show(activate: false)
        XCTAssertTrue(controller.window === window, "All opens reuse one window.")

        if let marker = ProcessInfo.processInfo.environment["TING_BORDERLESS_SETTINGS_REVIEW"] {
            try JSONSerialization.data(withJSONObject: ["window": window.windowNumber]).write(to: URL(fileURLWithPath: marker))
            defer { try? FileManager.default.removeItem(atPath: marker) }
            let deadline = Date().addingTimeInterval(90)
            while window.isVisible, FileManager.default.fileExists(atPath: marker), Date() < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func testSurfaceCloseActionAndCommandWCloseWhileSearchIsFocused() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")))
        let controller = SettingsWindowController(model: model, remembersFrame: false)
        defer { controller.close() }
        for command in [false, true] {
            controller.show(activate: false)
            let window = try XCTUnwrap(controller.window)
            let content = try XCTUnwrap(window.contentView)
            content.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            let search = try XCTUnwrap(descendants(content).first { $0 is NSSearchField } as? NSSearchField)
            XCTAssertTrue(window.makeFirstResponder(search))
            if command {
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "w",
                    charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
                XCTAssertTrue(window.performKeyEquivalent(with: event))
            } else {
                // This is the exact reference used by the in-surface SwiftUI close button.
                // xctest does not expose SwiftUI AX descendants; verify the binding directly.
                let host = try XCTUnwrap(descendants(content).compactMap { $0 as? SettingsWindowBehavior.Host }.first)
                let reference = try XCTUnwrap(host.reference)
                XCTAssertTrue(reference.window === window)
                reference.close()
            }
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertFalse(window.isVisible)
            XCTAssertNil(controller.window)
            XCTAssertNil(window.contentView, "Release the view and any shortcut recorder on close.")
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

}
