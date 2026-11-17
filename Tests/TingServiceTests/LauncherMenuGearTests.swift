import AppKit
import XCTest
import TingCore
@testable import Ting

@MainActor
final class LauncherMenuGearTests: XCTestCase {
    /// No launcher window is ever shown and no menu is presented.
    private func gear() -> (StatusItemController, AppModel, NSView, NSWindow) {
        _ = NSApplication.shared
        let model = AppModel(presentsWindows: false)
        let controller = StatusItemController(model: model, makesStatusItem: false, openSettings: {}, openWelcome: {})
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        window.contentView = view
        return (controller, model, view, window)
    }

    func testGearKeepsSelectaOpenInItsNestedPath() {
        let (controller, model, view, window) = gear()
        defer { withExtendedLifetime(window) {} }
        var config = Config()
        let child = Item(key: "c", label: "C", action: .url("https://example.com/c"))
        config.items = [Item(key: "g", label: "G", action: .group([child]))]
        model.leader.configure(config)
        model.leader.leaderPressed(at: 1)
        model.leader.leaderReleased()
        model.leader.select("g")
        XCTAssertEqual(model.leader.session.path, ["g"])
        let items = model.leader.session.items
        var whilePresented = false
        controller.popUp(from: view) { _, _ in
            whilePresented = model.leader.isOpen && model.isMenuTracking
                && model.leader.session.path == ["g"] && model.leader.session.items == items
        }
        XCTAssertTrue(whilePresented)
        XCTAssertTrue(model.leader.isOpen)
        XCTAssertEqual(model.leader.session.path, ["g"])
        XCTAssertEqual(model.leader.session.items, items)
        XCTAssertFalse(model.isMenuTracking)
    }

    func testGearKeepsLaunchaOpenWithItsQuery() {
        let (controller, model, view, window) = gear()
        defer { withExtendedLifetime(window) {} }
        model.launcha.open()
        model.launcha.model.query = "safari"
        XCTAssertTrue(model.launcha.isOpen)
        var whilePresented = false
        controller.popUp(from: view) { _, _ in
            whilePresented = model.launcha.isOpen && model.isMenuTracking && model.launcha.model.query == "safari"
        }
        XCTAssertTrue(whilePresented)
        XCTAssertTrue(model.launcha.isOpen)
        XCTAssertEqual(model.launcha.model.query, "safari")
        model.launcha.close()
    }
}
