import AppKit
import XCTest
import TingCore
@testable import Ting

/// The real values of the agent prompt, the copy to a private pasteboard and `Ting --agent-prompt`.
/// The person's clipboard and `~/.config/ting` are never touched.
final class AgentPromptSourceTests: XCTestCase {
    /// The executable next to the test bundle in the build products folder.
    private var executable: URL {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("Ting")
    }

    func testTheFolderFollowsTingConfig() {
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("ting spec \(UUID().uuidString).json")
        let text = AgentPromptSource.text(environment: ["TING_CONFIG": config.path])
        let folder = config.standardizedFileURL.path + ".micro"
        XCTAssertTrue(text.contains("micro-apps folder `\(folder)`"), text)
        XCTAssertTrue(text.contains("mkdir -p '\(folder)'"), text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    func testWithoutTingConfigTheFolderIsNextToTheDefaultConfig() {
        let text = AgentPromptSource.text(environment: [:])
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ting/micro").path
        XCTAssertTrue(text.contains("micro-apps folder `\(folder)`"), text)
    }

    func testABundleWithoutTheDocumentNamesOnlyTheLink() throws {
        // The test bundle has no FORMAT.md and no version of Ting.
        let bundle = Bundle(for: Self.self)
        XCTAssertNil(AgentPromptSource.formatDocument(bundle: bundle))
        let text = AgentPromptSource.text(bundle: bundle, environment: [:])
        XCTAssertFalse(text.contains("Resources/FORMAT.md"))
        XCTAssertTrue(text.contains("https://raw.githubusercontent.com/bobuk-io/ting/"), text)
    }

    func testABundleWithTheDocumentNamesItFirst() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("Ting Test \(UUID().uuidString).app")
        addTeardownBlock { try? FileManager.default.removeItem(at: app) }
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try "# format\n".write(to: contents.appendingPathComponent("Resources/FORMAT.md"), atomically: true, encoding: .utf8)
        let plist: [String: Any] = ["CFBundleIdentifier": "io.bobuk.ting.test." + UUID().uuidString,
                                    "CFBundleShortVersionString": "9.8.7", "CFBundleExecutable": "Ting",
                                    "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: app))

        let text = AgentPromptSource.text(bundle: bundle, environment: ["TING_CONFIG": "/tmp/x.json"])
        let document = contents.appendingPathComponent("Resources/FORMAT.md").resolvingSymlinksInPath().path
        let link = "https://raw.githubusercontent.com/bobuk-io/ting/v9.8.7/docs/micro-apps/FORMAT.md"
        let documentAt = try XCTUnwrap(text.range(of: "`\(document)`")).lowerBound
        let linkAt = try XCTUnwrap(text.range(of: link)).lowerBound
        XCTAssertLessThan(documentAt, linkAt)
    }

    func testCopyUsesTheGivenPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.bobuk.ting.tests." + UUID().uuidString))
        addTeardownBlock { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        let text = AgentPromptSource.text(environment: ["TING_CONFIG": "/tmp/ting-copy-test.json"])
        AgentPromptSource.copy(text, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        XCTAssertEqual(AgentPrompt.toast, "Agent prompt copied")
    }

    /// `Ting --agent-prompt` prints the same text as the menu action, exits with 0 and writes nothing.
    func testAgentPromptModePrintsTheTextAndExits() throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path), executable.path)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting agent " + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("ting-spec.json")

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--agent-prompt"]
        var environment = ProcessInfo.processInfo.environment
        environment["TING_CONFIG"] = config.path
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let output = out.fileHandleForReading.readDataToEndOfFile()
        if exited.wait(timeout: .now() + 20) == .timedOut {
            process.terminate()
            XCTFail("Ting --agent-prompt did not exit")
        }
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        // Built with SwiftPM the executable has no bundle: no document inside the app, the link of main.
        let expected = AgentPrompt.text(
            formatDocument: nil, link: AgentPrompt.formatLink(version: nil),
            microAppsFolder: config.standardizedFileURL.path + ".micro",
            executable: executable.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), expected + "\n")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }
}
