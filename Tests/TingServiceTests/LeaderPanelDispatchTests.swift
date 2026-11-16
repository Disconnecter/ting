import AppKit
import XCTest
import TingCore
@testable import Ting

@MainActor
final class LeaderPanelDispatchTests: XCTestCase {
    func testCommandShortcutsRemainSwallowed() throws {
        _ = NSApplication.shared
        let panel = LeaderPanel()
        var delivered = false
        panel.onKeyDown = { _ in delivered = true }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "q",
            charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12))
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertFalse(delivered)
    }

    func testKeyEquivalentDispatchReachesSelectaExactlyOnce() throws {
        _ = NSApplication.shared
        let controller = LeaderController(presentsWindow: false)
        var config = Config()
        let first = Item(key: "a", label: "A", action: .url("https://example.com/a"))
        let second = Item(key: "b", label: "B", action: .url("https://example.com/b"))
        config.items = [first, second]
        controller.configure(config)
        controller.leaderPressed(at: 1)
        controller.leaderReleased()
        let panel = LeaderPanel()
        var delivered: [UInt16] = []
        var ran: [Item] = []
        panel.onKeyDown = { delivered.append($0.keyCode); controller.handleKeyDown($0) }
        controller.onRun = { ran.append($0) }
        // AppKit tries key equivalents before normal window dispatch. Never post system events.
        for (code, text, flags) in [(UInt16(125), "\u{F701}", NSEvent.ModifierFlags([.function, .numericPad])),
                                    (UInt16(36), "\r", NSEvent.ModifierFlags())] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
            if !panel.performKeyEquivalent(with: event) { panel.sendEvent(event) }
        }
        XCTAssertEqual(delivered, [125, 36])
        XCTAssertEqual(ran, [second])
    }
}
