@testable import TingRuntime
import AppKit
import CoreServices
import XCTest
import TingCore
@testable import Ting

/// Reads no real context: gives the values it was set up with and records what was asked.
@MainActor
final class FakeContextReader: MicroAppContextReading {
    var context = MicroAppContext()
    var error: Error?
    private(set) var calls: [(sources: [MicroAppContextSource], target: MicroAppTarget?)] = []

    func read(_ sources: [MicroAppContextSource], target: MicroAppTarget?) async throws -> MicroAppContext {
        calls.append((sources, target))
        if let error { throw error }
        return context
    }
}

/// Sends nothing: records each action and its target.
@MainActor
final class FakeKeyboard: MicroAppKeyboardSending {
    var error: Error?
    private(set) var sent: [(action: MicroAppKeyboardAction, target: MicroAppTarget?)] = []

    func send(_ action: MicroAppKeyboardAction, to target: MicroAppTarget?) async throws {
        if let error { throw error }
        sent.append((action, target))
    }
}

/// The context of a start and the keys and text a micro-app sends, through the runner and the
/// real flow controller with a fake reader and a fake keyboard. No panel is shown, no key is
/// sent, and a private pasteboard stands in for the clipboard.
@MainActor
final class MicroAppContextFlowTests: XCTestCase {
    private var directory: URL!
    private var pasteboard: NSPasteboard!
    private var reader: FakeContextReader!
    private var keyboard: FakeKeyboard!
    private var flow: MicroAppFlowController!
    private var toasts: [String] = []
    private let target = MicroAppTarget(pid: 4242, bundleID: "com.example.Editor", name: "Editor", path: "/Applications/Editor.app")

    override func setUp() async throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-context-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.bobuk.ting.tests." + UUID().uuidString))
        reader = FakeContextReader()
        keyboard = FakeKeyboard()
        let config = directory.appendingPathComponent("ting-test.json").path
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.workingDirectory = directory.path
        runner.timeLimit = 20
        let target = self.target
        flow = MicroAppFlowController(approvals: MicroAppApprovalStore(url: URL(fileURLWithPath: config + ".micro-approvals.json")),
                                      values: MicroAppValueStore(url: URL(fileURLWithPath: config + ".micro-values.json")),
                                      runner: runner, pasteboard: pasteboard, presentsWindow: false,
                                      contextReader: reader, keyboard: keyboard, frontmost: { target })
        flow.onToast = { [weak self] in self?.toasts.append($0) }
        toasts = []
    }

    override func tearDown() async throws {
        flow.close()
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    private func load(_ files: [(String, String)], libraries: [MicroAppLibrarySource] = []) {
        let catalog = MicroAppCatalog.load(files, libraries: MicroAppLibraries(libraries))
        XCTAssertEqual(catalog.issues, [])
        flow.setCatalog(catalog)
    }

    /// Starts `id`, approves it, and waits until the run ended.
    private func start(_ id: String) async throws {
        flow.start(id: id)
        try await settle()
        if case .approval = flow.session.state { flow.handle(.commandEnter) }
        try await settle()
        let end = Date().addingTimeInterval(20)
        while case .working = flow.session.state, Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        try await settle()
    }

    private func settle() async throws {
        for _ in 0..<5 { try await Task.sleep(nanoseconds: 20_000_000) }
    }

    private var resultText: String? {
        if case .result(let content) = flow.session.state { return content.text }
        return nil
    }

    private let header = "format: ting.microapp/2\ndescription: Test.\n"

    func testContextIsReadAtTheStartForTheAppInFrontAndReachesTemplatesAndCode() async throws {
        reader.context = MicroAppContext([MicroAppContextField(source: .app, name: "name")!: "Editor",
                                          MicroAppContextField(source: .finder, name: "selection")!: "/a b\n/c"])
        load([("ctx.yaml", header + """
            context: [finder, app]
            input: none
            steps:
              - command: printf '%s|' "$TING_CONTEXT_APP_NAME" "$TING_CONTEXT_FINDER_FOLDER"; printf '%s' "$TING_CONTEXT_FINDER_SELECTION" | wc -l | tr -d ' '
              - text: ${input} ${context.app.name|url}
            output:
              to: [panel]
            """)])
        try await start("ctx")
        XCTAssertEqual(reader.calls.count, 1)
        XCTAssertEqual(reader.calls.first?.sources, [.app, .finder])
        XCTAssertEqual(reader.calls.first?.target, target)
        XCTAssertEqual(resultText, "Editor||1 Editor")
    }

    func testAMicroAppWithoutContextReadsNothing() async throws {
        load([("plain.yaml", header + "input: none\nsteps:\n  - text: hi\noutput:\n  to: [panel]\n")])
        try await start("plain")
        XCTAssertEqual(resultText, "hi")
        XCTAssertTrue(reader.calls.isEmpty)
    }

    func testAContextErrorShowsTheMessageAndRunsNothing() async throws {
        let marker = directory.appendingPathComponent("ran")
        reader.error = MicroAppInputError(message: MicroAppContextScripts.accessibilityMessage)
        load([("sel.yaml", header + "context: [selection]\ninput: none\nsteps:\n  - command: touch '\(marker.path)'; echo \"$TING_CONTEXT_SELECTION_TEXT\"\noutput:\n  to: [panel]\n")])
        try await start("sel")
        guard case .result(let content) = flow.session.state else { return XCTFail("expected the error panel") }
        XCTAssertTrue(content.isError)
        XCTAssertEqual(content.text, MicroAppContextScripts.accessibilityMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testLibrariesReadTheContextOfTheStart() async throws {
        reader.context = MicroAppContext([MicroAppContextField(source: .browser, name: "url")!: "https://example.com"])
        let library = MicroAppLibrarySource(name: "tab", file: "libs/tab.yaml", text: """
            format: ting.microlib/1
            description: The tab.
            context: [browser]
            steps:
              - command: printf '%s' "$TING_CONTEXT_BROWSER_URL"
              - text: <${input}|${context.browser.url}>

            """)
        load([("link.yaml", header + "input: none\nsteps:\n  - call: tab\noutput:\n  to: [panel]\n")], libraries: [library])
        try await start("link")
        XCTAssertEqual(reader.calls.first?.sources, [.browser])
        XCTAssertEqual(resultText, "<https://example.com|https://example.com>")
    }

    func testKeysAndPasteStepsGoToTheAppInFrontInOrder() async throws {
        pasteboard.clearContents()
        pasteboard.setString("query", forType: .string)
        load([("send.yaml", header + "input: clipboard\nsteps:\n  - keys: [cmd+t]\n  - paste: ${input} now\n  - keys: return\n")])
        try await start("send")
        XCTAssertEqual(keyboard.sent.map(\.action), [.keys([Hotkey(string: "cmd+t")!]), .paste("query now", keepOnClipboard: false),
                                                    .keys([Hotkey(string: "return")!])])
        XCTAssertEqual(keyboard.sent.map(\.target), [target, target, target])
        XCTAssertFalse(flow.isOpen)
    }

    func testAKeyboardErrorFailsTheStep() async throws {
        keyboard.error = MicroAppInputError(message: "Editor is no longer in front, so Ting sent nothing to it.")
        load([("send.yaml", header + "input: none\nsteps:\n  - keys: cmd+s\n  - text: after\noutput:\n  to: [panel]\n")])
        try await start("send")
        guard case .result(let content) = flow.session.state else { return XCTFail("expected the error panel") }
        XCTAssertTrue(content.isError)
        XCTAssertTrue(content.notes.contains("not sent"), "\(content.notes)")
        XCTAssertTrue(content.text.contains("no longer in front"))
    }

    func testAppOutputPastesTheResultAndKeepsTheClipboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        reader.context = MicroAppContext([MicroAppContextField(source: .selection, name: "text")!: "b\na"])
        load([("sort.yaml", header + "context: [selection]\ninput: none\nsteps:\n  - command: sort\n    stdin: ${context.selection.text}\noutput:\n  to: [app]\n")])
        try await start("sort")
        try await settle()
        XCTAssertEqual(keyboard.sent.map(\.action), [.paste("a\nb", keepOnClipboard: false)])
        XCTAssertEqual(keyboard.sent.first?.target, target)
        XCTAssertEqual(pasteboard.string(forType: .string), "old")
        XCTAssertFalse(flow.isOpen)
        XCTAssertEqual(toasts, [])
    }

    func testAppAndClipboardOutputLeavesTheResultOnTheClipboard() async throws {
        load([("both.yaml", header + "input: none\nsteps:\n  - text: done\noutput:\n  to: [clipboard, app]\n")])
        try await start("both")
        try await settle()
        XCTAssertEqual(keyboard.sent.map(\.action), [.paste("done", keepOnClipboard: true)])
        XCTAssertEqual(pasteboard.string(forType: .string), "done")
        XCTAssertEqual(toasts, ["Copied"])
    }

    func testAFailedPastePutsTheResultOnTheClipboardAndSaysSo() async throws {
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        keyboard.error = MicroAppInputError(message: "A password field holds the keyboard (secure input), so Ting sent nothing.")
        load([("out.yaml", header + "input: none\nsteps:\n  - text: result\noutput:\n  to: [app]\n")])
        try await start("out")
        try await settle()
        XCTAssertEqual(pasteboard.string(forType: .string), "result")
        guard case .result(let content) = flow.session.state else { return XCTFail("expected the error panel") }
        XCTAssertTrue(content.isError)
        XCTAssertTrue(content.text.hasSuffix("The result is on the clipboard."), content.text)
    }

    // MARK: Runner

    func testRunnerWithoutAKeyboardRefusesToSend() async throws {
        let app = try MicroAppChecker.check(header + "input: none\nsteps:\n  - paste: x\n", fileName: "p.yaml").get()
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin" }
        guard case .stepFailed(let failure) = await runner.run(app) else { return XCTFail("expected a failed step") }
        XCTAssertEqual(failure.note, "not sent")
        XCTAssertTrue(failure.output.stderr.contains("only Ting sends"))
    }

    // MARK: Reader

    private func reader(running: [String], permission: OSStatus = noErr,
                        scripts: @escaping @Sendable (String) -> MicroAppScriptResult) -> MicroAppContextReader {
        let reader = MicroAppContextReader(copySelection: { _ in nil })
        reader.runningApps = { running }
        reader.automationPermission = { _ in permission }
        reader.runScript = { scripts($0) }
        return reader
    }

    func testReaderGivesTheAppTheFinderSelectionAndTheBrowserTab() async throws {
        let reader = reader(running: ["com.apple.finder", "org.chromium.Chromium", "com.apple.Safari"]) { script in
            if script.contains("insertion location") {
                return MicroAppScriptResult(end: .success, stdout: "/Users/a/Desktop/\n/Users/a/Desktop/x y.txt\n/Users/a/Desktop/Dir/\n")
            }
            XCTAssertTrue(script.contains("org.chromium.Chromium") && script.contains("active tab"), script)
            return MicroAppScriptResult(end: .success, stdout: "https://example.com/\nExample\n")
        }
        let chrome = MicroAppTarget(pid: 7, bundleID: "org.chromium.Chromium", name: "Chromium", path: "/Applications/Chromium.app")
        let context = try await reader.read([.app, .finder, .browser], target: chrome)
        func value(_ source: MicroAppContextSource, _ name: String) -> String { context[MicroAppContextField(source: source, name: name)!] }
        XCTAssertEqual(value(.app, "name"), "Chromium")
        XCTAssertEqual(value(.app, "bundle"), "org.chromium.Chromium")
        XCTAssertEqual(value(.app, "path"), "/Applications/Chromium.app")
        XCTAssertEqual(value(.app, "pid"), "7")
        XCTAssertEqual(value(.finder, "folder"), "/Users/a/Desktop")
        XCTAssertEqual(value(.finder, "selection"), "/Users/a/Desktop/x y.txt\n/Users/a/Desktop/Dir")
        XCTAssertEqual(value(.browser, "url"), "https://example.com/")
        XCTAssertEqual(value(.browser, "title"), "Example")
        XCTAssertTrue(["Chromium", "org.chromium.Chromium"].contains(value(.browser, "name")), "its name, or its id when it does not run")
    }

    func testReaderLeavesAGoneAppEmptyAndReportsARefusal() async throws {
        // Finder does not run, no browser runs: empty values, no script.
        let none = reader(running: []) { _ in XCTFail("no script may run"); return MicroAppScriptResult(end: .failure) }
        let empty = try await none.read([.finder, .browser], target: nil)
        XCTAssertTrue(empty.values.values.allSatisfy(\.isEmpty))
        XCTAssertEqual(empty.environment(for: [.finder, .browser]).count, 5)

        // A window that went away: empty.
        let gone = reader(running: ["com.apple.finder"]) { _ in
            MicroAppScriptResult(end: .failure, stderr: "execution error: Can’t get window 1. (-1719)")
        }
        let goneContext = try await gone.read([.finder], target: nil)
        XCTAssertTrue(goneContext.values.values.allSatisfy(\.isEmpty))

        // Automation refused: the message says where to allow it.
        let refused = reader(running: ["com.apple.finder"], permission: OSStatus(errAEEventNotPermitted)) { _ in
            XCTFail("no script may run"); return MicroAppScriptResult(end: .failure)
        }
        do {
            _ = try await refused.read([.finder], target: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Automation › Ting › Finder"), error.localizedDescription)
        }

        let slow = reader(running: ["com.apple.finder"]) { _ in MicroAppScriptResult(end: .timedOut) }
        do {
            _ = try await slow.read([.finder], target: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Finder did not answer in time, so Ting could not read the Finder selection.")
        }
    }
}
