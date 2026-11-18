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

    func testRunning1PasswordFallsThroughToWorkspaceOpen() {
        XCTAssertFalse(ActionRunner.tryActivation(bundleID: "com.1password.1password") {
            XCTFail("Activation would bypass the reopen request")
            return true
        })
        XCTAssertTrue(ActionRunner.tryActivation(bundleID: "io.example.editor") { true })
        XCTAssertFalse(ActionRunner.tryActivation(bundleID: "io.example.editor") { false })
    }

    func testIconsAreReused() {
        AppIcons.prepare([.app("f", "Finder", "com.apple.finder")])
        let first = AppIcons.icon("com.apple.finder")
        XCTAssertNotNil(first)
        XCTAssertTrue(first === AppIcons.icon("com.apple.finder"))
    }
}
