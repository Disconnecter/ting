import AppKit
import XCTest
import TingCore
@testable import Ting

@MainActor
final class LeaderNavigationTests: XCTestCase {
    private func action(_ key: String) -> Item {
        Item(key: key, label: key, action: .url("https://example.com/\(key)"))
    }

    private func controller(_ items: [Item]) -> LeaderController {
        let controller = LeaderController(presentsWindow: false)
        var config = Config()
        config.items = items
        controller.configure(config)
        controller.leaderPressed(at: 1)
        controller.leaderReleased()
        return controller
    }

    private func press(_ code: UInt16, in controller: LeaderController, repeatKey: Bool = false,
                       flags: NSEvent.ModifierFlags = [.numericPad, .function]) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                    isARepeat: repeatKey, keyCode: code)!
        // Direct controller delivery, with window presentation disabled; no system events.
        controller.handleKeyDown(event)
    }

    func testArrowSelectionRepeatsAndClampsThenReturnRunsSelection() {
        let items = [action("a"), action("b"), action("c")]
        let controller = controller(items)
        var ran: [Item] = []
        controller.onRun = { ran.append($0) }
        XCTAssertEqual(controller.session.selectedItem, items[0])
        press(126, in: controller)
        XCTAssertEqual(controller.session.selection, 0)
        press(125, in: controller)
        press(125, in: controller, repeatKey: true)
        press(125, in: controller, repeatKey: true)
        XCTAssertEqual(controller.session.selection, 2)
        press(126, in: controller, repeatKey: true)
        press(36, in: controller)
        XCTAssertEqual(ran, [items[1]])
        XCTAssertFalse(controller.isOpen)
    }

    func testGroupsEnterAndReturnToTheirParentSelection() {
        let child = action("c")
        let group = Item(key: "g", label: "Group", action: .group([child]))
        let controller = controller([action("a"), group])
        press(125, in: controller)
        press(124, in: controller)
        XCTAssertEqual(controller.session.path, ["g"])
        XCTAssertEqual(controller.session.selectedItem, child)
        press(123, in: controller)
        XCTAssertEqual(controller.session.path, [])
        XCTAssertEqual(controller.session.selectedItem, group)
        press(36, in: controller)
        XCTAssertEqual(controller.session.path, ["g"])
        var ran: [Item] = []
        controller.onRun = { ran.append($0) }
        press(76, in: controller)
        XCTAssertEqual(ran, [child])
    }

    func testExplicitReturnBindingWinsForBothEnterKeys() {
        for code: UInt16 in [36, 76] {
            let bound = action("return")
            let controller = controller([action("a"), bound])
            var ran: [Item] = []
            controller.onRun = { ran.append($0) }
            press(code, in: controller)
            XCTAssertEqual(ran, [bound])
        }
    }

    func testEmptyMenuModifiedArrowsAndRepeatedEnterAreHarmless() {
        let empty = controller([])
        for code: UInt16 in [125, 126, 124, 36, 76] { press(code, in: empty) }
        XCTAssertNil(empty.session.selectedItem)
        XCTAssertTrue(empty.isOpen)
        let controller = controller([action("a"), action("b")])
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
            for code: UInt16 in [123, 124, 125, 126] { press(code, in: controller, flags: flags) }
        }
        press(36, in: controller, repeatKey: true)
        press(124, in: controller)
        XCTAssertEqual(controller.session.selection, 0)
        XCTAssertEqual(controller.session.shakeToken, 0)
        XCTAssertTrue(controller.isOpen)
        press(123, in: controller)
        XCTAssertFalse(controller.isOpen)
    }

    func testReconfigurationKeepsSelectedKeyAndReopeningResetsSelection() {
        let a = action("a"), b = action("b")
        let controller = controller([a, b])
        press(125, in: controller)
        var config = Config()
        config.items = [b, a]
        controller.configure(config)
        XCTAssertEqual(controller.session.selectedItem, b)
        config.items = [a]
        controller.configure(config)
        XCTAssertEqual(controller.session.selectedItem, a)
        controller.close()
        controller.leaderPressed(at: 5)
        XCTAssertEqual(controller.session.selection, 0)
    }
}
