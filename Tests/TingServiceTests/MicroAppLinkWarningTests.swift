@testable import TingRuntime
import AppKit
import XCTest
import TingCore
@testable import Ting

/// The warning on the first click on a link of a result: shown once, remembered only after Open Link,
/// kept next to `$TING_CONFIG`. Links are never really followed and the panel is never shown.
@MainActor
final class MicroAppLinkWarningTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-link-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testNoticeFileIsNextToTheConfigAndFailsClosed() throws {
        let config = directory.appendingPathComponent("ting-test.json")
        XCTAssertEqual(MicroAppLinkNoticeStore.defaultURL(environment: ["TING_CONFIG": config.path], home: directory).path,
                       config.path + ".micro-link-notice.json")
        XCTAssertEqual(MicroAppLinkNoticeStore.defaultURL(environment: [:], home: directory).path,
                       directory.appendingPathComponent("Library/Application Support/Ting/micro-link-notice.json").path)

        let fresh = MicroAppLinkNoticeStore(url: directory.appendingPathComponent("missing.json"))
        XCTAssertFalse(fresh.seen)
        XCTAssertNil(fresh.error)

        let broken = directory.appendingPathComponent("broken.json")
        try Data("{\"seen\": tru".utf8).write(to: broken)
        let store = MicroAppLinkNoticeStore(url: broken)
        XCTAssertFalse(store.seen)
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.markSeen())
        XCTAssertTrue(MicroAppLinkNoticeStore(url: broken).seen)
    }

    func testFirstClickShowsTheWarningAndOpenLinkIsRemembered() async throws {
        _ = NSApplication.shared
        let text = """
        format: ting.microapp/2
        name: Links
        description: Shows a link.
        input: none
        steps:
          - text: "[site](https://example.com)"
        output:
          to: [panel]
          as: markdown

        """
        let catalog = MicroAppCatalog.load([("links.yaml", text)])
        let entry = try XCTUnwrap(catalog.entries.first)
        XCTAssertEqual(entry.issues, [])
        let approvals = MicroAppApprovalStore(url: directory.appendingPathComponent("approvals.json"))
        try approvals.approve(id: "links", hash: entry.contentHash)
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin:/usr/sbin:/sbin" }
        runner.environment = [:]
        runner.workingDirectory = directory.path
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.bobuk.ting.tests." + UUID().uuidString))
        addTeardownBlock { @MainActor in pasteboard.releaseGlobally() }
        let noticeURL = directory.appendingPathComponent("notice.json")
        var opened: [URL] = []
        let flow = MicroAppFlowController(approvals: approvals,
                                          values: MicroAppValueStore(url: directory.appendingPathComponent("values.json")),
                                          runner: runner, pasteboard: pasteboard, presentsWindow: false,
                                          linkNotice: MicroAppLinkNoticeStore(url: noticeURL),
                                          linkOpener: { opened.append($0) })
        addTeardownBlock { @MainActor in flow.close() }
        let link = try XCTUnwrap(URL(string: "https://example.com"))

        flow.clickLink(link)
        XCTAssertNil(flow.session.pendingLink, "No link is followed without a result")

        flow.setCatalog(catalog)
        flow.start(id: "links")
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            if case .result = flow.session.state { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .result = flow.session.state else { return XCTFail("expected the result panel") }

        // Esc cancels the warning only: the result stays and nothing is remembered.
        flow.clickLink(link)
        XCTAssertEqual(flow.session.pendingLink, link)
        XCTAssertEqual(opened, [])
        flow.handle(.escape)
        XCTAssertNil(flow.session.pendingLink)
        guard case .result = flow.session.state else { return XCTFail("Esc in the warning closed the result") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: noticeURL.path))

        // ↩ opens the link instead of copying the result, and the warning never shows again.
        flow.clickLink(link)
        XCTAssertEqual(flow.session.pendingLink, link)
        flow.handle(.enter)
        XCTAssertEqual(opened, [link])
        XCTAssertNil(flow.session.pendingLink)
        guard case .result = flow.session.state else { return XCTFail("↩ in the warning closed the result") }
        XCTAssertNil(pasteboard.string(forType: .string), "↩ in the warning does not copy the result")
        XCTAssertTrue(MicroAppLinkNoticeStore(url: noticeURL).seen)

        flow.clickLink(link)
        XCTAssertNil(flow.session.pendingLink)
        XCTAssertEqual(opened, [link, link])

        // A warning left open is dropped with the panel.
        let other = MicroAppFlowController(approvals: approvals,
                                           values: MicroAppValueStore(url: directory.appendingPathComponent("values.json")),
                                           runner: runner, pasteboard: pasteboard, presentsWindow: false,
                                           linkNotice: MicroAppLinkNoticeStore(url: directory.appendingPathComponent("other.json")),
                                           linkOpener: { opened.append($0) })
        other.session.state = .result(MicroAppPanelContent(title: "t", text: "x", style: .markdown, isError: false))
        other.clickLink(link)
        XCTAssertEqual(other.session.pendingLink, link)
        other.close()
        XCTAssertNil(other.session.pendingLink)
        XCTAssertEqual(opened.count, 2)
    }
}
