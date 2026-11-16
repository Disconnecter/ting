import XCTest
import TingCore
@testable import Ting

/// The example micro-apps of `docs/micro-apps/examples/`, loaded by the store from a temporary
/// micro-apps folder next to a temporary `TING_CONFIG` file and run by the app's runner with the
/// user's login-shell PATH. The DNS example needs the network and is only checked, not run.
@MainActor
final class MicroAppExamplesTests: XCTestCase {
    private static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/micro-apps/examples", isDirectory: true)

    private var apps: [String: MicroApp] = [:]
    private var runner = MicroAppRunner()

    override func setUp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-examples-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config.json")
        let store = MicroAppStore(configURL: config, environment: ["TING_CONFIG": config.path])
        try FileManager.default.copyItem(at: Self.examples, to: store.folderURL)

        let catalog = store.load()
        XCTAssertEqual(catalog.issues, [])
        XCTAssertEqual(try String(contentsOf: store.logURL, encoding: .utf8), "")
        apps = Dictionary(uniqueKeysWithValues: catalog.apps.map { ($0.id, $0) })
        XCTAssertEqual(apps.keys.sorted(), ["change-case", "count-text", "dns-lookup", "encode-decode", "format-json"])

        let path = await UserPATH.shared()
        runner.path = { path }
        runner.timeLimit = 20
    }

    private func run(_ id: String, _ values: [String: String] = [:], stdin: String) async throws -> String {
        let app = try XCTUnwrap(apps[id])
        let result = await runner.run(app, values: values, stdin: stdin)
        guard case .success(let output) = result else {
            XCTFail("\(id) \(values): \(result)")
            return ""
        }
        return output.stdout
    }

    func testFormatJSON() async throws {
        let app = try XCTUnwrap(apps["format-json"])
        XCTAssertEqual(app.output.targets, [.clipboard, .panel])
        let out = try await run("format-json", stdin: #"{"b":1,"a":[1,2],"имя":"Ёж"}"#)
        XCTAssertEqual(out, """
        {
          "a" : [
            1,
            2
          ],
          "b" : 1,
          "имя" : "Ёж"
        }
        """)
    }

    func testFormatJSONRefusesBrokenJSON() async throws {
        let app = try XCTUnwrap(apps["format-json"])
        let result = await runner.run(app, stdin: "{not json")
        guard case .failure(let code, let output) = result else { return XCTFail("\(result)") }
        XCTAssertNotEqual(code, 0)
        XCTAssertFalse(output.stderr.isEmpty)
    }

    func testChangeCaseWithCyrillicText() async throws {
        let text = "привет, мир! hello WORLD ёлка"
        let upper = try await run("change-case", ["mode": "upper"], stdin: text)
        let lower = try await run("change-case", ["mode": "lower"], stdin: text)
        let title = try await run("change-case", ["mode": "title"], stdin: text)
        XCTAssertEqual(upper, "ПРИВЕТ, МИР! HELLO WORLD ЁЛКА")
        XCTAssertEqual(lower, "привет, мир! hello world ёлка")
        XCTAssertEqual(title, "Привет, Мир! Hello World Ёлка")
    }

    func testEncodeDecodeAllFourModes() async throws {
        let text = "Привет, world & a=1/2?"
        let base64 = try await run("encode-decode", ["mode": "base64-encode"], stdin: text)
        XCTAssertEqual(base64, Data(text.utf8).base64EncodedString())
        let decoded = try await run("encode-decode", ["mode": "base64-decode"], stdin: base64)
        XCTAssertEqual(decoded, text)
        let url = try await run("encode-decode", ["mode": "url-encode"], stdin: text)
        XCTAssertEqual(url, "%D0%9F%D1%80%D0%B8%D0%B2%D0%B5%D1%82%2C%20world%20%26%20a%3D1%2F2%3F")
        let back = try await run("encode-decode", ["mode": "url-decode"], stdin: url)
        XCTAssertEqual(back, text)
        let plus = try await run("encode-decode", ["mode": "url-decode"], stdin: "a+b%20c")
        XCTAssertEqual(plus, "a b c")
    }

    func testCountWordsAndCharacters() async throws {
        let app = try XCTUnwrap(apps["count-text"])
        XCTAssertEqual(app.output.targets, [.panel])
        XCTAssertEqual(app.output.style, .markdown)
        let out = try await run("count-text", stdin: "Привет мир\nhello")
        XCTAssertEqual(out, """
        | | |
        |---|---:|
        | Words | 3 |
        | Characters | 16 |
        | Lines | 1 |
        """)
    }

    func testReadmeExampleIsAGoodFile() throws {
        let readme = try String(contentsOf: Self.examples.appendingPathComponent("../../../README.md").standardizedFileURL,
                                encoding: .utf8)
        let start = try XCTUnwrap(readme.range(of: "```yaml\n"))
        let end = try XCTUnwrap(readme.range(of: "```", range: start.upperBound..<readme.endIndex))
        let text = String(readme[start.upperBound..<end.lowerBound])
        guard case .success(let app) = MicroAppChecker.check(text, fileName: "change-case.yaml") else {
            return XCTFail("\(MicroAppChecker.check(text, fileName: "change-case.yaml"))")
        }
        XCTAssertEqual(app.params.map(\.name), ["mode"])
    }

    func testDNSLookupIsChecked() throws {
        let app = try XCTUnwrap(apps["dns-lookup"])
        XCTAssertEqual(app.output.targets, [.panel])
        XCTAssertEqual(app.output.style, .console)
        XCTAssertEqual(app.params.map(\.name), ["domain", "tool", "record"])
        XCTAssertEqual(app.params.map(\.required), [true, false, false])
    }
}
