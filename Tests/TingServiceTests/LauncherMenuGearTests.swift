import AppKit
import XCTest
import TingCore
@testable import Ting

@MainActor
final class LauncherMenuGearTests: XCTestCase {
    private func gear() -> (StatusItemController, AppModel, NSView, NSWindow) {
        _ = NSApplication.shared
        let model = AppModel()
        let controller = StatusItemController(model: model, makesStatusItem: false, openSettings: {}, openWelcome: {})
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        window.contentView = view
        return (controller, model, view, window)
    }

    func testGearKeepsSelectaOpen() {
        let (controller, model, view, window) = gear()
        defer { withExtendedLifetime(window) {} }
        var config = Config()
        config.items = [Item(key: "a", label: "A", action: .url("https://example.com/a"))]
        model.leader.configure(config)
        model.leader.leaderPressed(at: 1)
        model.leader.leaderReleased()
        XCTAssertTrue(model.leader.isOpen)
        var openWhilePresented = false
        controller.popUp(from: view) { _, _ in
            openWhilePresented = model.leader.isOpen && model.isMenuTracking
        }
        XCTAssertTrue(openWhilePresented)
        XCTAssertTrue(model.leader.isOpen)
        XCTAssertFalse(model.isMenuTracking)
    }

    func testGearKeepsLaunchaOpen() {
        let (controller, model, view, window) = gear()
        defer { withExtendedLifetime(window) {} }
        model.launcha.open()
        XCTAssertTrue(model.launcha.isOpen)
        var openWhilePresented = false
        controller.popUp(from: view) { _, _ in
            openWhilePresented = model.launcha.isOpen && model.isMenuTracking
        }
        XCTAssertTrue(openWhilePresented)
        XCTAssertTrue(model.launcha.isOpen)
        model.launcha.close()
    }
}
