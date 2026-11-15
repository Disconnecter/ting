import XCTest
import TingCore
@testable import Ting

/// The parameter panel model and the remembered values with a temporary `TING_CONFIG`, on the
/// example files. No panel is shown.
@MainActor
final class MicroAppFormFlowTests: XCTestCase {
    private var directory: URL!
    private var environment: [String: String] = [:]

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-form-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        environment = ["TING_CONFIG": directory.appendingPathComponent("ting-test.json").path]
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func example(_ name: String) throws -> MicroApp {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/micro-apps/examples/\(name).yaml")
        let catalog = MicroAppCatalog.load([("\(name).yaml", try String(contentsOf: url, encoding: .utf8))])
        return try XCTUnwrap(catalog.apps.first)
    }

    private var valuesStore: MicroAppValueStore {
        MicroAppValueStore(url: MicroAppValueStore.defaultURL(environment: environment))
    }

    func testValuesFileIsNextToTheConfigOrInApplicationSupport() {
        XCTAssertEqual(MicroAppValueStore.defaultURL(environment: environment).path,
                       directory.appendingPathComponent("ting-test.json").path + ".micro-values.json")
        XCTAssertEqual(MicroAppValueStore.defaultURL(environment: [:], home: URL(fileURLWithPath: "/Users/someone")).path,
                       "/Users/someone/Library/Application Support/Ting/micro-values.json")
    }

    func testDNSLookupShowsOnlyDomainAndRefusesAnEmptyDomain() throws {
        let app = try example("dns-lookup")
        let store = valuesStore
        let model = MicroAppFormModel(app: app, form: MicroAppForm.start(app, remembered: store.remembered))
        XCTAssertEqual(model.form.visibleIndexes.map { model.form.fields[$0].param.shownPrompt }, ["Domain"])
        XCTAssertTrue(model.form.hasOptionalToggle)

        // ⌘O opens 'Tool' and 'Record' and moves the focus into them.
        model.toggleOptional()
        XCTAssertEqual(model.form.visibleIndexes.count, 3)
        XCTAssertEqual(model.focus, 1)
        model.toggleOptional()
        XCTAssertEqual(model.form.visibleIndexes, [0])
        XCTAssertEqual(model.focus, 0)

        // ↩ with an empty domain: no values, the domain field is marked and focused.
        XCTAssertNil(model.submit())
        XCTAssertEqual(model.missing, 0)
        XCTAssertEqual(model.focus, 0)
        model.setText("example.com", at: 0)
        XCTAssertNil(model.missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path), "nothing is saved before a run")
    }

    func testAfterARunWithMXTheNextStartOpensTheOptionalFields() throws {
        let app = try example("dns-lookup")
        let store = valuesStore
        let model = MicroAppFormModel(app: app, form: MicroAppForm.start(app, remembered: store.remembered))
        model.setText("example.com", at: 0)
        model.toggleOptional()
        model.focus(2)
        model.setText("m", at: 2) // letters filter: MX, then CNAME
        XCTAssertEqual(model.filtered(2), ["MX", "CNAME"])
        XCTAssertEqual(model.form.fields[2].value, "MX")
        let values = try XCTUnwrap(model.submit())
        XCTAssertEqual(values, ["domain": "example.com", "tool": "dig", "record": "MX"])
        try store.remember(values, for: app)

        let next = valuesStore
        let form = MicroAppForm.start(app, remembered: next.remembered)
        XCTAssertTrue(form.optionalOpen)
        XCTAssertEqual(form.fields.map(\.value), ["example.com", "dig", "MX"])
        XCTAssertTrue(form.fields[0].isRemembered)
        XCTAssertEqual(MicroAppFormModel(app: app, form: form).focus, 0, "the domain gets the focus, its text selected")
    }

    func testChangeCaseAndEncodeDecodeAreOpenLists() throws {
        for name in ["change-case", "encode-decode"] {
            let app = try example(name)
            let model = MicroAppFormModel(app: app, form: MicroAppForm.start(app, remembered: MicroAppRememberedValues()))
            XCTAssertTrue(model.form.isSingleChoiceList, name)
            XCTAssertEqual(model.form.visibleIndexes, [0], name)
            let first = model.form.fields[0].value
            model.move(1, at: 0)
            XCTAssertNotEqual(model.form.fields[0].value, first, name)
            XCTAssertNotNil(model.submit(), name)
        }
    }

    func testFormValuesReachTheCommandAsTingVariables() async throws {
        let app = try example("change-case")
        let model = MicroAppFormModel(app: app, form: MicroAppForm.start(app, remembered: MicroAppRememberedValues()))
        model.setText("lo", at: 0)
        XCTAssertEqual(model.form.fields[0].value, "lower")
        let values = try XCTUnwrap(model.submit())
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.workingDirectory = directory.path
        let result = await runner.run(app, values: values, stdin: "HeLLo ПРИВЕТ")
        XCTAssertEqual(result, .success(MicroAppRunOutput(stdout: "hello привет")))

        let echo = MicroApp(id: "echo", description: "Echo",
                            params: [.init(name: "domain", kind: .text, required: true),
                                     .init(name: "sep", kind: .text, required: false, defaultValue: ",")],
                            input: .none, command: #"printf '%s|%s' "$TING_DOMAIN" "$TING_SEP""#,
                            output: .init(targets: [.panel]))
        let form = MicroAppFormModel(app: echo, form: MicroAppForm.start(echo, remembered: MicroAppRememberedValues()))
        form.setText("a b; $(x)", at: 0)
        form.setText("", at: 1)
        let echoed = await runner.run(echo, values: try XCTUnwrap(form.submit()))
        XCTAssertEqual(echoed, .success(MicroAppRunOutput(stdout: "a b; $(x)|")))
    }

    func testRememberFalseSavesNothing() throws {
        var app = try example("dns-lookup")
        app.remember = false
        let store = valuesStore
        try store.remember(["domain": "example.com"], for: app)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testAppWithoutParametersHasNoForm() throws {
        let app = try example("format-json")
        XCTAssertTrue(MicroAppForm.start(app, remembered: MicroAppRememberedValues()).isEmpty)
    }
}
