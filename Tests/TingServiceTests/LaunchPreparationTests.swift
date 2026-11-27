import AppKit
import XCTest
import TingCore
@testable import Ting

@MainActor
final class LaunchPreparationTests: XCTestCase {
    func testPreparingNestedBindingsDoesNotLaunchApps() {
        let runner = ActionRunner()
        let missing = "io.bobuk.ting.test.nonexistent"
        let items: [Item] = [.group("a", "Apps", [.app("x", "Missing", missing)])]
        runner.prepare(items)
        AppIcons.prepare(items)
        XCTAssertNil(AppIcons.icon(missing))
        XCTAssertNil(AppIcons.icon(missing))
        XCTAssertNil(runner.activateRunning(items[0]))
        XCTAssertNil(runner.activateRunning(.app("x", "Missing", missing)))
        runner.prepare([])
        AppIcons.prepare([])
    }

    func testActivatingRunningAppAlsoAsksItToReopenItsWindow() {
        var events: [String] = []
        let url = URL(fileURLWithPath: "/Applications/WhatsApp.app")
        let runner = ActionRunner(submitApplication: { requested, _ in
            XCTAssertEqual(requested, url)
            events.append("reopen")
        })
        runner.onPlaySound = { events.append("sound") }
        XCTAssertTrue(runner.tryActivation(bundleURL: url) {
            events.append("activate")
            return true
        })
        XCTAssertEqual(events, ["activate", "reopen", "sound"])
    }

    func testFailedActivationFallsThroughWithoutReopenOrSound() {
        var events: [String] = []
        let runner = ActionRunner(submitApplication: { _, _ in events.append("reopen") })
        runner.onPlaySound = { events.append("sound") }
        XCTAssertFalse(runner.tryActivation(bundleURL: URL(fileURLWithPath: "/Applications/Editor.app")) { false })
        XCTAssertTrue(events.isEmpty)
    }

    func testLaunchSoundFollowsSubmissionWhileApplicationIsOpening() async {
        let submitted = expectation(description: "App open request submitted")
        var finish: (@Sendable (Error?) -> Void)?
        var events: [String] = []
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        let runner = ActionRunner(submitApplication: { requested, completion in
            XCTAssertEqual(requested, url)
            events.append("submit")
            finish = completion
            submitted.fulfill()
        })
        runner.onPlaySound = { events.append("sound") }
        let launch = Task { await runner.openApp(at: url, name: "Editor") }
        await fulfillment(of: [submitted], timeout: 2)
        XCTAssertEqual(events, ["submit", "sound"])
        guard let finish else { return }
        finish(nil)
        let outcome = await launch.value
        XCTAssertEqual(outcome, .opened)
        XCTAssertEqual(events, ["submit", "sound"])
    }

    func testIconsAreReused() {
        AppIcons.prepare([.app("f", "Finder", "com.apple.finder")])
        let first = AppIcons.icon("com.apple.finder")
        XCTAssertNotNil(first)
        XCTAssertTrue(first === AppIcons.icon("com.apple.finder"))
    }
}
