import AppKit
import XCTest
@testable import Ting

@MainActor
final class LaunchaNavigationTests: XCTestCase {
    func testListNavigationWithFocusOutsideSearchFieldAndKeyRepeat() throws {
        _ = NSApplication.shared
        let panel = LaunchaPanel()
        // Never show or activate the panel: these events only reach this test window.
        let responder = NSView(frame: .zero)
        panel.contentView = responder
        XCTAssertTrue(panel.makeFirstResponder(panel))
        var moves: [Int] = []
        panel.onMove = { moves.append($0) }
        for (code, repeated) in [(UInt16(125), false), (125, true), (126, false), (121, false), (116, false)] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: repeated, keyCode: code))
            panel.sendEvent(event)
        }
        XCTAssertEqual(moves, [1, 1, -1, 8, -8])
    }

    func testCommandDownJumpsToFilesAndNothingElseDoes() throws {
        _ = NSApplication.shared
        let panel = LaunchaPanel()
        panel.contentView = NSView(frame: .zero)
        var jumps = 0
        var moves: [Int] = []
        panel.onJumpToFiles = { jumps += 1 }
        panel.onMove = { moves.append($0) }
        for (code, flags): (UInt16, NSEvent.ModifierFlags) in [(125, .command), (125, []), (126, .command)] {
            // Real arrow events carry the arrow function-key character; BobukPanel reads it for ⌘ keys.
            let arrow = String(Character(UnicodeScalar(code == 125 ? NSDownArrowFunctionKey : NSUpArrowFunctionKey)!))
            panel.sendEvent(try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags.union([.numericPad, .function]), timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: arrow, charactersIgnoringModifiers: arrow,
                isARepeat: false, keyCode: code)))
        }
        XCTAssertEqual(jumps, 1)
        XCTAssertEqual(moves, [1])
        for flags: NSEvent.ModifierFlags in [[], .shift, .option, .control, [.command, .shift], [.command, .option]] {
            XCTAssertFalse(LaunchaPanel.isJumpToFiles(keyCode: 125, flags: flags, composing: false))
        }
        XCTAssertFalse(LaunchaPanel.isJumpToFiles(keyCode: 125, flags: .command, composing: true))
        XCTAssertFalse(LaunchaPanel.isJumpToFiles(keyCode: 126, flags: .command, composing: false))
    }

    func testEditingAndCompositionDoNotNavigateTheList() {
        for code: UInt16 in [125, 126, 116, 121] {
            for flags: NSEvent.ModifierFlags in [.shift, .option, .control, .command, [.command, .shift]] {
                XCTAssertNil(LaunchaPanel.navigationDelta(keyCode: code, flags: flags, composing: false))
            }
            XCTAssertNil(LaunchaPanel.navigationDelta(keyCode: code, flags: [], composing: true))
        }
        for code: UInt16 in [123, 124, 36, 53, 0] {
            XCTAssertNil(LaunchaPanel.navigationDelta(keyCode: code, flags: [], composing: false))
        }
    }
}
