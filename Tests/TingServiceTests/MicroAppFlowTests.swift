import AppKit
import XCTest
import TingCore
@testable import Ting

/// The start path of a micro-app binding with a temporary `TING_CONFIG`: folder, approvals,
/// runner and result rules. The clipboard and the panels are not touched.
@MainActor
final class MicroAppFlowTests: XCTestCase {
    private var directory: URL!
    private var configURL: URL!
    private var environment: [String: String] = [:]

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-flow-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configURL = directory.appendingPathComponent("ting-test.json")
        environment = ["TING_CONFIG": configURL.path]
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var example: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/micro-apps/examples/format-json.yaml")
    }

    private func runner(timeLimit: TimeInterval = 20, outputLimit: Int = MicroAppRunRules.outputLimit) -> MicroAppRunner {
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.workingDirectory = directory.path
        runner.timeLimit = timeLimit
        runner.outputLimit = outputLimit
        return runner
    }

    private func app(_ command: String, to: [MicroApp.OutputTarget] = [.panel]) -> MicroApp {
        MicroApp(id: "test", description: "Test", input: .clipboard, command: command, output: .init(targets: to, style: .console))
    }

    func testApprovalFileIsNextToTheConfigNotInTheFolderOrConfig() {
        let store = MicroAppStore(configURL: configURL, environment: environment)
        let url = MicroAppApprovalStore.defaultURL(environment: environment)
        XCTAssertEqual(url.path, configURL.path + ".micro-approvals.json")
        XCTAssertFalse(url.path.hasPrefix(store.folderURL.path + "/"))
        XCTAssertNotEqual(url, configURL)
        let home = URL(fileURLWithPath: "/Users/someone")
        XCTAssertEqual(MicroAppApprovalStore.defaultURL(environment: [:], home: home).path,
                       "/Users/someone/Library/Application Support/Ting/micro-approvals.json")
    }

    func testFormatJSONAsksOnceRunsAndAsksAgainAfterAnEdit() async throws {
        let store = MicroAppStore(configURL: configURL, environment: environment)
        try FileManager.default.createDirectory(at: store.folderURL, withIntermediateDirectories: true)
        let fileURL = store.folderURL.appendingPathComponent("format-json.yaml")
        try FileManager.default.copyItem(at: example, to: fileURL)
        let approvalsURL = MicroAppApprovalStore.defaultURL(environment: environment)
        var approvals = MicroAppApprovalStore(url: approvalsURL)

        // First start: approval.
        var catalog = store.load()
        guard case .approve(let app, let hash) = MicroAppStartStep.first(id: "format-json", catalog: catalog,
                                                                          approvals: approvals.approvals, folder: store.displayPath)
        else { return XCTFail("expected the approval panel") }
        XCTAssertEqual(hash, MicroAppApprovals.hash(try Data(contentsOf: fileURL)))

        // Esc refuses: nothing is stored, the next start asks again.
        guard case .approve = MicroAppStartStep.first(id: "format-json", catalog: catalog, approvals: approvals.approvals, folder: "")
        else { return XCTFail("a refusal must not approve") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: approvalsURL.path))

        // ⌘↩ approves and runs.
        try approvals.approve(id: app.id, hash: hash)
        let result = await runner().run(app, stdin: #"{"b":1,"a":[1,2]}"#)
        let plan = MicroAppResultPlan.make(app: app, result: result)
        XCTAssertEqual(plan.clipboard, "{\n  \"a\" : [\n    1,\n    2\n  ],\n  \"b\" : 1\n}")
        guard case .panel(let content) = plan.show else { return XCTFail("expected the result panel") }
        XCTAssertEqual(content.notes, ["Copied"])
        XCTAssertEqual(content.style, .code)

        // Second start, also after a restart of Ting: no approval.
        approvals = MicroAppApprovalStore(url: approvalsURL)
        XCTAssertEqual(MicroAppStartStep.first(id: "format-json", catalog: catalog, approvals: approvals.approvals, folder: ""), .run(app))

        // Any edit asks again.
        try (String(contentsOf: fileURL, encoding: .utf8) + "# edited\n").write(to: fileURL, atomically: true, encoding: .utf8)
        catalog = store.load()
        guard case .approve = MicroAppStartStep.first(id: "format-json", catalog: catalog, approvals: approvals.approvals, folder: "")
        else { return XCTFail("expected the approval panel after an edit") }

        // The approval is not in the folder and not in the config.
        let stored = try String(contentsOf: approvalsURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(hash))
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
        let inFolder = try FileManager.default.contentsOfDirectory(atPath: store.folderURL.path)
        XCTAssertEqual(inFolder, ["format-json.yaml"])
    }

    func testFormatJSONOnBadInputFailsInThePanel() async {
        let app = MicroAppCatalog.load([("format-json.yaml", (try? String(contentsOf: example, encoding: .utf8)) ?? "")]).apps.first
        guard let app else { return XCTFail("the example must load") }
        let result = await runner().run(app, stdin: "not json")
        let plan = MicroAppResultPlan.make(app: app, result: result)
        XCTAssertNil(plan.clipboard)
        guard case .panel(let content) = plan.show else { return XCTFail("expected the result panel") }
        XCTAssertTrue(content.isError)
        XCTAssertEqual(content.style, .console)
        XCTAssertTrue(content.notes.first?.hasPrefix("exit ") == true)
        XCTAssertFalse(content.text.isEmpty)
    }

    func testLongOutputShowsTheCutNote() async {
        let app = app("yes ting | head -c 100000", to: [.panel])
        let plan = MicroAppResultPlan.make(app: app, result: await runner(outputLimit: 1000).run(app), outputLimit: 1000)
        guard case .panel(let content) = plan.show else { return XCTFail("expected the result panel") }
        XCTAssertEqual(content.notes, ["output cut at 1000 bytes"])
        XCTAssertLessThanOrEqual(content.text.utf8.count, 1000)
    }

    func testTimeoutShowsStoppedWithPartialOutput() async {
        let app = app("echo before; sleep 30", to: [.clipboard])
        let runner = runner(timeLimit: 0.5)
        let plan = MicroAppResultPlan.make(app: app, result: await runner.run(app), timeLimit: 0.5)
        XCTAssertNil(plan.clipboard)
        guard case .panel(let content) = plan.show else { return XCTFail("expected the result panel") }
        XCTAssertEqual(content.notes, ["stopped after 1 s"])
        XCTAssertEqual(content.text, "before")
        XCTAssertEqual(MicroAppResultPlan.timeoutNote(), "stopped after 60 s")
    }

    func testEscDuringTheRunStopsSilently() async {
        let app = app("sleep 30; echo late", to: [.clipboard])
        let runner = runner()
        let task = Task { await runner.run(app) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let plan = MicroAppResultPlan.make(app: app, result: await task.value)
        XCTAssertEqual(plan, MicroAppResultPlan(show: .nothing))
    }
}

/// The key-equivalent path of the flow panel: AppKit sends ⌘ shortcuts there before `sendEvent`.
@MainActor
final class MicroAppFlowPanelKeyTests: XCTestCase {
    private func keyDown(_ keyCode: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = .command) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }

    private func press(_ event: NSEvent) -> (handled: Bool, keys: [MicroAppFlowPanel.Key]) {
        let panel = MicroAppFlowPanel()
        var keys: [MicroAppFlowPanel.Key] = []
        panel.onKey = { keys.append($0) }
        let handled = panel.performKeyEquivalent(with: event)
        return (handled, keys)
    }

    func testCommandReturnConfirms() {
        let result = press(keyDown(36, "\r"))
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.keys, [.commandEnter])
    }

    func testCommandKeypadEnterConfirms() {
        let result = press(keyDown(76, "\u{3}"))
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.keys, [.commandEnter])
    }

    func testCommandQIsSwallowed() {
        let result = press(keyDown(12, "q"))
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.keys, [])
    }

    func testCommandShiftReturnIsSwallowedWithoutConfirming() {
        let result = press(keyDown(36, "\r", flags: [.command, .shift]))
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.keys, [])
    }
}
