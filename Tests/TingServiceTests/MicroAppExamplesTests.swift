import AppKit
import XCTest
import TingCore
@testable import Ting

/// The five example micro-apps of `docs/micro-apps/examples/` from start to result in the app's
/// own code: the store loads them from a temporary micro-apps folder next to a temporary
/// `TING_CONFIG` file, and the app's flow controller goes through the approval panel (⌘↩), the
/// parameter panel (values set as the panel sets them, ↩), the run with the user's login-shell
/// PATH and the result: the result panel content as drawn, the "Copied" toast and the clipboard.
/// The panel stays off screen and a private pasteboard stands in for the clipboard, so the user's
/// screen, keyboard focus and clipboard are not touched. The DNS example needs the network and
/// runs only with `TING_NETWORK_TESTS=1`.
@MainActor
final class MicroAppExamplesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let examples = root.appendingPathComponent("docs/micro-apps/examples", isDirectory: true)

    private var catalog = MicroAppCatalog()
    private var flow: MicroAppFlowController!
    private var pasteboard: NSPasteboard!
    private var toasts: [String] = []
    private var approvalsURL: URL!

    override func setUp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-examples-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("ting-test.json")
        let environment = ["TING_CONFIG": config.path]
        let store = MicroAppStore(configURL: config, environment: environment)
        try FileManager.default.copyItem(at: Self.examples, to: store.folderURL)

        catalog = store.load()
        XCTAssertEqual(catalog.issues, [])
        XCTAssertEqual(try String(contentsOf: store.logURL, encoding: .utf8), "")
        XCTAssertEqual(catalog.apps.map(\.id), ["change-case", "count-text", "dns-lookup", "encode-decode", "format-json"])

        var runner = MicroAppRunner()
        let path = await UserPATH.shared()
        runner.path = { path }
        runner.timeLimit = 30
        approvalsURL = MicroAppApprovalStore.defaultURL(environment: environment)
        XCTAssertEqual(approvalsURL.path, config.path + ".micro-approvals.json")
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.bobuk.ting.tests." + UUID().uuidString))
        let pb = pasteboard!
        addTeardownBlock { @MainActor in pb.releaseGlobally() }
        flow = MicroAppFlowController(approvals: MicroAppApprovalStore(url: approvalsURL),
                                      values: MicroAppValueStore(url: MicroAppValueStore.defaultURL(environment: environment)),
                                      runner: runner, pasteboard: pasteboard, presentsWindow: false)
        flow.setCatalog(catalog)
        flow.onToast = { [weak self] in self?.toasts.append($0) }
        toasts = []
    }

    private struct Seen {
        var approvalAsked: Bool
        var content: MicroAppPanelContent?
        var clipboard: String?
    }

    /// Starts `id` like its binding does with `clipboard` on the clipboard, approves it when asked,
    /// sets the parameters by name (text typed or option chosen) and waits for the result.
    private func start(_ id: String, clipboard: String?, _ values: [String: String] = [:]) async throws -> Seen {
        pasteboard.clearContents()
        if let clipboard { pasteboard.setString(clipboard, forType: .string) }
        flow.start(id: id)
        var approvalAsked = false
        if case .approval(let app, let file) = flow.session.state {
            approvalAsked = true
            XCTAssertEqual(app.id, id)
            XCTAssertTrue(file.hasSuffix(".yaml"), file)
            flow.handle(.enter) // ↩ alone does nothing in the approval panel.
            guard case .approval = flow.session.state else { XCTFail("↩ must not approve"); return Seen(approvalAsked: true) }
            flow.handle(.commandEnter)
        }
        if case .form = flow.session.state {
            let model = try XCTUnwrap(flow.session.form)
            for (name, value) in values {
                let index = try XCTUnwrap(model.form.fields.firstIndex { $0.param.name == name }, name)
                if model.form.fields[index].choices != nil {
                    model.choose(value, at: index)
                } else {
                    model.setText(value, at: index)
                }
            }
            flow.handle(.enter)
        } else {
            XCTAssertTrue(values.isEmpty, "\(id) showed no parameter panel")
        }
        let end = Date().addingTimeInterval(30)
        while case .working = flow.session.state, Date() < end {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        var content: MicroAppPanelContent?
        if case .result(let shown) = flow.session.state { content = shown }
        let seen = Seen(approvalAsked: approvalAsked, content: content, clipboard: pasteboard.string(forType: .string))
        print("E2E \(id) \(values) clipboard-in=\(String(describing: clipboard)) approval=\(approvalAsked) " +
              "panel=\(String(describing: content?.text)) notes=\(content?.notes ?? []) style=\(String(describing: content?.style)) " +
              "clipboard-out=\(String(describing: seen.clipboard)) toasts=\(toasts)")
        return seen
    }

    private func closeResult() {
        if case .result = flow.session.state { flow.handle(.escape) }
        XCTAssertFalse(flow.isOpen)
    }

    func testFormatJSONClipboardAndPanel() async throws {
        let input = #"{"b":1,"a":[1,2],"имя":"Ёж"}"#
        let pretty = "{\n  \"a\" : [\n    1,\n    2\n  ],\n  \"b\" : 1,\n  \"имя\" : \"Ёж\"\n}"
        let seen = try await start("format-json", clipboard: input)
        XCTAssertTrue(seen.approvalAsked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: approvalsURL.path))
        let content = try XCTUnwrap(seen.content)
        XCTAssertEqual(content.text, pretty)
        XCTAssertEqual(content.style, .code)
        XCTAssertEqual(content.notes, ["Copied"])
        XCTAssertFalse(content.isError)
        XCTAssertEqual(MicroAppOutputRenderer.render(content).string, pretty)
        XCTAssertEqual(seen.clipboard, pretty)
        closeResult()

        // The approval is kept: the next start runs at once. Broken JSON: error panel, clipboard kept.
        let broken = try await start("format-json", clipboard: "{not json")
        XCTAssertFalse(broken.approvalAsked)
        let error = try XCTUnwrap(broken.content)
        XCTAssertTrue(error.isError)
        XCTAssertEqual(error.style, .console)
        XCTAssertEqual(broken.clipboard, "{not json")
        closeResult()
    }

    func testChangeCaseWithCyrillicText() async throws {
        let text = "привет, мир! hello WORLD ёлка"
        let expected = ["upper": "ПРИВЕТ, МИР! HELLO WORLD ЁЛКА",
                        "lower": "привет, мир! hello world ёлка",
                        "title": "Привет, Мир! Hello World Ёлка"]
        var first = true
        for mode in ["upper", "lower", "title"] {
            let seen = try await start("change-case", clipboard: text, ["mode": mode])
            XCTAssertEqual(seen.approvalAsked, first)
            first = false
            XCTAssertEqual(seen.clipboard, expected[mode], mode)
            XCTAssertEqual(seen.content?.text, expected[mode], mode)
            XCTAssertEqual(seen.content?.notes, ["Copied"])
            closeResult()
        }
    }

    func testEncodeDecodeAllFourModes() async throws {
        let text = "Привет, world & a=1/2?"
        let base64 = Data(text.utf8).base64EncodedString()
        let url = "%D0%9F%D1%80%D0%B8%D0%B2%D0%B5%D1%82%2C%20world%20%26%20a%3D1%2F2%3F"
        let steps: [(mode: String, input: String, output: String)] = [
            ("base64-encode", text, base64),
            ("base64-decode", base64, text),
            ("url-encode", text, url),
            ("url-decode", url, text),
            ("url-decode", "a+b%20c", "a b c"),
        ]
        for step in steps {
            let seen = try await start("encode-decode", clipboard: step.input, ["mode": step.mode])
            XCTAssertEqual(seen.clipboard, step.output, step.mode)
            XCTAssertEqual(seen.content?.text, step.output, step.mode)
            XCTAssertEqual(seen.content?.isError, false)
            closeResult()
        }
    }

    func testCountShowsAMarkdownTable() async throws {
        let seen = try await start("count-text", clipboard: "Привет мир\nhello")
        let content = try XCTUnwrap(seen.content)
        XCTAssertEqual(content.style, .markdown)
        XCTAssertEqual(content.notes, [])
        XCTAssertEqual(seen.clipboard, "Привет мир\nhello", "a panel-only micro-app leaves the clipboard alone")
        // Drawn as a table: aligned columns, no `|` or `---` of the markdown source.
        let drawn = MicroAppOutputRenderer.render(content).string
        print("E2E count-text drawn=\(drawn.debugDescription)")
        XCTAssertFalse(drawn.contains("|"))
        XCTAssertFalse(drawn.contains("---"))
        for (label, number) in [("Words", "3"), ("Characters", "16"), ("Lines", "1")] {
            let line = try XCTUnwrap(drawn.components(separatedBy: "\n").first { $0.contains(label) }, label)
            XCTAssertTrue(line.hasSuffix(number) || line.trimmingCharacters(in: .whitespaces).hasSuffix(number), line)
        }
        closeResult()
    }

    func testDNSLookupConsolePanel() async throws {
        guard ProcessInfo.processInfo.environment["TING_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("needs the network; run with TING_NETWORK_TESTS=1")
        }
        let a = try await start("dns-lookup", clipboard: "kept", ["domain": "example.com"])
        XCTAssertTrue(a.approvalAsked)
        let content = try XCTUnwrap(a.content)
        XCTAssertEqual(content.style, .console)
        XCTAssertFalse(content.isError)
        XCTAssertTrue(content.text.contains("example.com.") && content.text.contains("\tA\t"), content.text)
        XCTAssertEqual(a.clipboard, "kept")
        closeResult()

        let mx = try await start("dns-lookup", clipboard: nil, ["domain": "gmail.com", "tool": "dig", "record": "MX"])
        XCTAssertTrue(mx.content?.text.contains("\tMX\t") == true)
        closeResult()

        let whois = try await start("dns-lookup", clipboard: nil, ["domain": "example.com", "tool": "whois"])
        XCTAssertTrue(whois.content?.text.uppercased().contains("EXAMPLE.COM") == true)
        closeResult()

        let option = try await start("dns-lookup", clipboard: nil, ["domain": "-x", "tool": "dig"])
        XCTAssertEqual(option.content?.isError, true)
        XCTAssertTrue(option.content?.text.contains("Not a domain: -x") == true)
        closeResult()
    }

    func testRequiredDomainStopsReturnWhenEmpty() async throws {
        flow.start(id: "dns-lookup")
        flow.handle(.commandEnter)
        guard case .form = flow.session.state else { return XCTFail("expected the parameter panel") }
        flow.session.form?.setText("", at: 0)
        flow.handle(.enter)
        guard case .form = flow.session.state else { return XCTFail("an empty required domain must not run") }
        XCTAssertEqual(flow.session.form?.missing, 0)
        flow.handle(.escape)
        XCTAssertFalse(flow.isOpen)
    }

    func testReadmeExampleIsAGoodFile() throws {
        let readme = try String(contentsOf: Self.root.appendingPathComponent("README.md"), encoding: .utf8)
        let start = try XCTUnwrap(readme.range(of: "```yaml\n"))
        let end = try XCTUnwrap(readme.range(of: "```", range: start.upperBound..<readme.endIndex))
        let text = String(readme[start.upperBound..<end.lowerBound])
        guard case .success(let app) = MicroAppChecker.check(text, fileName: "change-case.yaml") else {
            return XCTFail("\(MicroAppChecker.check(text, fileName: "change-case.yaml"))")
        }
        XCTAssertEqual(app.params.map(\.name), ["mode"])
    }
}
