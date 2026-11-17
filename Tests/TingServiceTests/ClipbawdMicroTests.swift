import XCTest
import AppKit
import TingCore
@testable import TingRuntime
@testable import Ting

final class ClipbawdMicroTests: XCTestCase {
    private func app(_ index: String) throws -> MicroApp {
        let yaml = """
        format: ting.microapp/2
        description: Read a clipboard history item
        input: none
        steps:
          - id: read
            command: 'printf %s "$CLIP"'
            env:
              CLIP: ${clipboard[\(index)]}
        output:
          to: [panel]
        """
        switch MicroAppChecker.check(yaml, fileName: "history.yaml") {
        case .success(let app): return app
        case .failure(let failure): XCTFail("\(failure)"); throw NSError(domain: "test", code: 1)
        }
    }

    func testHistoryIndexAndShellSafety() async throws {
        let payload = "$(echo injected); 'quoted'\ntext"
        var runner = MicroAppRunner()
        runner.environment = [:]
        runner.path = { "/usr/bin:/bin" }
        runner.clipboardHistory = [payload, "older"]
        for (index, expected) in [("-1", payload), ("-2", "older")] {
            let result = await runner.run(try app(index))
            guard case .success(let output) = result else { XCTFail("\(result)"); continue }
            XCTAssertEqual(output.stdout, expected)
        }
    }

    func testUnavailableMissingAndImageFail() async throws {
        var runner = MicroAppRunner()
        runner.environment = [:]
        runner.path = { "/usr/bin:/bin" }
        let cases: [[String?]?] = [nil, [], [nil]]
        for history in cases {
            runner.clipboardHistory = history
            let result = await runner.run(try app("-1"))
            if case .success = result { XCTFail("Must not silently succeed") }
        }
    }

    func testApprovalDetectsHistoryAndShellInterpolationIsRejected() throws {
        XCTAssertTrue(try app("-1").readsClipboardHistory)
        let yaml = """
        format: ting.microapp/2
        description: Unsafe history interpolation
        input: none
        steps:
          - command: 'echo ${clipboard[-1]}'
        output:
          to: [panel]
        """
        if case .success = MicroAppChecker.check(yaml, fileName: "unsafe.yaml") {
            XCTFail("History must not be interpolated into shell code")
        }
    }

    func testInvalidIndexesRejected() {
        for index in ["0", "1", "abc", "-", "-999999999999999999999999"] {
            if case .success = MicroAppTemplate.parse("${clipboard[\(index)]}") { XCTFail(index) }
        }
        if case .failure(let error) = MicroAppTemplate.parse("${clipboard[-1]|trim}") {
            XCTFail(error.message)
        }
    }

    @MainActor
    func testSnapshotPreservesHistoryPositionsAndDisabledState() {
        let pasteboard = NSPasteboard(name: .init("io.bobuk.tests." + UUID().uuidString))
        let history = ClipbawdHistory(pasteboard: pasteboard)
        history.record(ClipCapture(types: [ClipboardTypes.plainText], text: "older"))
        history.record(ClipCapture(types: [ClipboardTypes.plainText], text: "newest"))
        XCTAssertEqual(history.microAppSnapshot(), ["newest", "older"])
        var settings = ClipbawdSettings()
        settings.enabled = false
        history.configure(settings)
        XCTAssertNil(history.microAppSnapshot())
    }
}
