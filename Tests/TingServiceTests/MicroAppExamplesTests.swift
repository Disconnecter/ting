import AppKit
import XCTest
import TingCore
@testable import Ting

/// The five example micro-apps of `docs/micro-apps/examples/` from start to result through the
/// app's real flow panel. The store loads them from a temporary micro-apps folder next to a
/// temporary `TING_CONFIG` file. The flow controller builds its real panel (the SwiftUI views,
/// the NSTextField of each parameter, the result text view), and every step is a real key event
/// given to that panel: ⌘↩ approves, letters are typed into the focused field, ↓/↑ choose an
/// option, ⌘O opens the optional fields, Tab moves on, ↩ runs, ↩/Esc close the result. What the
/// test reads back is what the panel's views show and what lands on the clipboard.
///
/// The panel is never put on screen and never takes keyboard focus, and a private pasteboard
/// stands in for the clipboard, so the user's screen, typing and clipboard are not touched. The
/// DNS example needs the network and runs only with `TING_NETWORK_TESTS=1`.
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
        _ = NSApplication.shared
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
        let controller = flow!
        addTeardownBlock { @MainActor in controller.close() }
    }

    // MARK: The panel

    private var panel: MicroAppFlowPanel { get throws { try XCTUnwrap(flow.flowPanel, "no flow panel") } }

    /// Lets SwiftUI update the panel's views and the deferred focus changes run.
    private func settle() async throws {
        for _ in 0..<3 {
            try panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    private func views<T: NSView>(_ type: T.Type) throws -> [T] {
        var found: [T] = []
        func walk(_ view: NSView) {
            if let match = view as? T { found.append(match) }
            view.subviews.forEach(walk)
        }
        if let content = try panel.contentView { walk(content) }
        return found
    }

    /// The text of the read-only text views: the command in the approval panel, the result.
    private func shownTexts() throws -> [String] {
        try views(NSTextView.self).filter { !$0.isEditable && !$0.isFieldEditor }.map(\.string)
    }

    /// The parameter field that has keyboard focus in the panel.
    private func focusedField() throws -> NSTextField? {
        let responder = try panel.firstResponder
        if let editor = responder as? NSTextView, editor.isFieldEditor { return editor.delegate as? NSTextField }
        return responder as? NSTextField
    }

    private enum Key {
        case commandReturn, enter, escape, tab, down, up, commandO
        case text(String)
    }

    /// One key event, given to the panel as AppKit gives it: ⌘ shortcuts to `performKeyEquivalent` first.
    private func press(_ key: Key) async throws {
        let panel = try self.panel
        func event(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                             windowNumber: panel.windowNumber, context: nil, characters: chars,
                             charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        switch key {
        case .commandReturn:
            let e = event(36, "\r", .command)
            if !panel.performKeyEquivalent(with: e) { panel.sendEvent(e) }
        case .commandO:
            let e = event(31, "o", .command)
            if !panel.performKeyEquivalent(with: e) { panel.sendEvent(e) }
        case .enter: panel.sendEvent(event(36, "\r"))
        case .escape: panel.sendEvent(event(53, "\u{1b}"))
        case .tab: panel.sendEvent(event(48, "\t"))
        case .down: panel.sendEvent(event(125, down, [.numericPad, .function]))
        case .up: panel.sendEvent(event(126, up, [.numericPad, .function]))
        case .text(let text):
            for character in text { panel.sendEvent(event(0, String(character))) }
        }
        try await settle()
    }

    /// In the focused choice field, presses ↓ (then ↑) until the panel marks `option`.
    private func choose(_ option: String, field index: Int) async throws {
        let model = try XCTUnwrap(flow.session.form)
        let count = (model.form.fields[index].choices ?? []).count
        for key in [Key.down, Key.up] {
            for _ in 0...count {
                if model.form.fields[index].value == option { break }
                try await press(key)
            }
        }
        XCTAssertEqual(model.form.fields[index].value, option)
        // A choice field shows its marked option as its placeholder.
        XCTAssertEqual(try focusedField()?.placeholderString ?? focusedField()?.placeholderAttributedString?.string, option)
    }

    private struct Seen {
        var approvalAsked = false
        var approvalCommand: String?
        var shown: String?
        var content: MicroAppPanelContent?
        var clipboard: String?
    }

    private enum Param {
        case type(String)
        case choose(String)
        case optionalOpen
        case next
    }

    /// Starts `id` as its binding does, with `clipboard` on the clipboard, answers the approval panel
    /// and the parameter panel with key events, and waits for the result panel.
    private func start(_ id: String, clipboard: String?, _ steps: [Param] = []) async throws -> Seen {
        pasteboard.clearContents()
        if let clipboard { pasteboard.setString(clipboard, forType: .string) }
        flow.start(id: id)
        try await settle()
        var seen = Seen()
        if case .approval(let app, _) = flow.session.state {
            seen.approvalAsked = true
            seen.approvalCommand = try shownTexts().first
            XCTAssertEqual(seen.approvalCommand, app.command, "the approval panel shows the full command")
            try await press(.enter) // ↩ alone does nothing in the approval panel.
            guard case .approval = flow.session.state else { XCTFail("↩ must not approve"); return seen }
            try await press(.commandReturn)
        }
        if case .form = flow.session.state {
            for step in steps {
                switch step {
                case .type(let text):
                    let field = try XCTUnwrap(try focusedField(), "no focused field")
                    (field.currentEditor() as? NSTextView)?.selectAll(nil)
                    try await press(.text(text))
                    XCTAssertEqual(field.stringValue, text)
                case .choose(let option):
                    let model = try XCTUnwrap(flow.session.form)
                    try await choose(option, field: model.focus)
                case .optionalOpen:
                    // ⌘O opens the optional fields and focuses the first one. They are open already
                    // when a remembered optional value differs from its default; then Tab goes there.
                    let model = try XCTUnwrap(flow.session.form)
                    if model.form.optionalOpen {
                        try await press(.tab)
                    } else {
                        try await press(.commandO)
                        XCTAssertTrue(model.form.optionalOpen)
                    }
                    XCTAssertTrue(model.form.fields[model.focus].isOptional)
                case .next:
                    try await press(.tab)
                }
            }
            try await press(.enter)
        } else {
            XCTAssertTrue(steps.isEmpty, "\(id) showed no parameter panel")
        }
        let end = Date().addingTimeInterval(30)
        while case .working = flow.session.state, Date() < end {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await settle()
        if case .result(let content) = flow.session.state {
            seen.content = content
            seen.shown = try shownTexts().first
        }
        seen.clipboard = pasteboard.string(forType: .string)
        print("E2E \(id) steps=\(steps) clipboard-in=\(String(describing: clipboard)) approval=\(seen.approvalAsked) " +
              "shown=\(String(describing: seen.shown)) notes=\(seen.content?.notes ?? []) error=\(seen.content?.isError ?? false) " +
              "style=\(seen.content.map { "\($0.style)" } ?? "-") clipboard-out=\(String(describing: seen.clipboard)) toasts=\(toasts)")
        return seen
    }

    private func closeResult(with key: Key = .escape) async throws {
        if case .result = flow.session.state { try await press(key) }
        XCTAssertFalse(flow.isOpen)
    }

    // MARK: The five examples

    func testFormatJSONClipboardAndPanel() async throws {
        let input = #"{"b":1,"a":[1,2],"имя":"Ёж"}"#
        let pretty = "{\n  \"a\" : [\n    1,\n    2\n  ],\n  \"b\" : 1,\n  \"имя\" : \"Ёж\"\n}"
        let seen = try await start("format-json", clipboard: input)
        XCTAssertTrue(seen.approvalAsked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: approvalsURL.path))
        XCTAssertEqual(seen.shown, pretty)
        XCTAssertEqual(seen.content?.style, .code)
        XCTAssertEqual(seen.content?.notes, ["Copied"])
        XCTAssertEqual(seen.clipboard, pretty)
        try await closeResult()

        // The approval is kept: the next start runs at once. Broken JSON: error panel, clipboard kept.
        let broken = try await start("format-json", clipboard: "{not json")
        XCTAssertFalse(broken.approvalAsked)
        XCTAssertEqual(broken.content?.isError, true)
        XCTAssertEqual(broken.content?.style, .console)
        XCTAssertTrue(broken.shown?.contains("JSON") == true)
        XCTAssertEqual(broken.clipboard, "{not json")
        try await closeResult()
    }

    func testChangeCaseWithCyrillicText() async throws {
        let text = "привет, мир! hello WORLD ёлка"
        let expected = ["upper": "ПРИВЕТ, МИР! HELLO WORLD ЁЛКА",
                        "lower": "привет, мир! hello world ёлка",
                        "title": "Привет, Мир! Hello World Ёлка"]
        var first = true
        for mode in ["title", "lower", "upper"] {
            let seen = try await start("change-case", clipboard: text, [.choose(mode)])
            XCTAssertEqual(seen.approvalAsked, first)
            first = false
            XCTAssertEqual(seen.clipboard, expected[mode], mode)
            XCTAssertEqual(seen.shown, expected[mode], mode)
            XCTAssertEqual(seen.content?.notes, ["Copied"])
            try await closeResult()
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
            let seen = try await start("encode-decode", clipboard: step.input, [.choose(step.mode)])
            XCTAssertEqual(seen.clipboard, step.output, step.mode)
            XCTAssertEqual(seen.shown, step.output, step.mode)
            XCTAssertEqual(seen.content?.isError, false)
            try await closeResult()
        }
    }

    func testCountShowsAMarkdownTable() async throws {
        let seen = try await start("count-text", clipboard: "Привет мир\nhello")
        XCTAssertEqual(seen.content?.style, .markdown)
        XCTAssertEqual(seen.content?.notes, [])
        XCTAssertEqual(seen.clipboard, "Привет мир\nhello", "a panel-only micro-app leaves the clipboard alone")
        // Drawn as a table: aligned columns, no `|` or `---` of the markdown source.
        let shown = try XCTUnwrap(seen.shown)
        XCTAssertFalse(shown.contains("|"))
        XCTAssertFalse(shown.contains("---"))
        let rows = shown.components(separatedBy: "\n").map { $0.split(separator: "\t").map(String.init) }
        XCTAssertEqual(rows, [["Words", "3"], ["Characters", "16"], ["Lines", "1"]])
        // ↩ in the result panel copies everything and closes.
        try await closeResult(with: .enter)
        XCTAssertEqual(pasteboard.string(forType: .string), seen.content?.plainText)
    }

    func testDNSLookupConsolePanel() async throws {
        guard ProcessInfo.processInfo.environment["TING_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("needs the network; run with TING_NETWORK_TESTS=1")
        }
        let a = try await start("dns-lookup", clipboard: "kept", [.type("example.com")])
        XCTAssertTrue(a.approvalAsked)
        XCTAssertEqual(a.content?.style, .console)
        XCTAssertEqual(a.content?.isError, false)
        XCTAssertTrue(a.shown?.contains("example.com.") == true && a.shown?.contains("\tA\t") == true, a.shown ?? "")
        XCTAssertEqual(a.clipboard, "kept")
        try await closeResult()

        // The domain comes back remembered and fully selected; ⌘O opens tool and record.
        let mx = try await start("dns-lookup", clipboard: nil,
                                 [.type("gmail.com"), .optionalOpen, .choose("dig"), .next, .choose("MX")])
        XCTAssertTrue(mx.shown?.contains("\tMX\t") == true, mx.shown ?? "")
        try await closeResult()

        let whois = try await start("dns-lookup", clipboard: nil,
                                    [.type("example.com"), .optionalOpen, .choose("whois"), .next, .choose("A")])
        XCTAssertTrue(whois.shown?.uppercased().contains("EXAMPLE.COM") == true)
        XCTAssertEqual(whois.content?.isError, false)
        try await closeResult()

        let option = try await start("dns-lookup", clipboard: nil,
                                     [.type("-x"), .optionalOpen, .choose("dig")])
        XCTAssertEqual(option.content?.isError, true)
        XCTAssertTrue(option.shown?.contains("Not a domain: -x") == true)
        try await closeResult()
    }

    func testRequiredDomainStopsReturnWhenEmpty() async throws {
        flow.start(id: "dns-lookup")
        try await settle()
        try await press(.commandReturn)
        guard case .form = flow.session.state else { return XCTFail("expected the parameter panel") }
        let field = try XCTUnwrap(try focusedField())
        XCTAssertEqual(field.stringValue, "")
        try await press(.enter)
        guard case .form = flow.session.state else { return XCTFail("an empty required domain must not run") }
        XCTAssertEqual(flow.session.form?.missing, 0)
        try await press(.escape)
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
