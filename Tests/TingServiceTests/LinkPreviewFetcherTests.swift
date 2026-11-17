import AppKit
import XCTest
import TingCore
@testable import Ting

/// Answers requests from a fixed table; never touches the network.
final class StubProtocol: URLProtocol {
    struct Answer {
        var status = 200
        var type = "text/html"
        var body = Data()
        var redirect: String?
    }
    nonisolated(unsafe) static var answers: [String: Answer] = [:]
    nonisolated(unsafe) static var requested: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requested.append(url.absoluteString)
        let answer = Self.answers[url.absoluteString] ?? Answer(status: 404, type: "text/plain")
        if let target = answer.redirect, let next = URL(string: target) {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: next), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": answer.type, "Content-Length": "\(answer.body.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LinkPreviewFetcherTests: XCTestCase {
    private func fetcher(publicHosts: Bool = true) -> LinkPreviewFetcher {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return LinkPreviewFetcher(configuration: configuration, resolvesPublic: { _ in publicHosts })
    }

    private static func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    override func setUp() {
        StubProtocol.answers = [:]
        StubProtocol.requested = []
    }

    func testPageTitleAndIcon() async {
        let icon = Self.png(width: 16, height: 16)
        StubProtocol.answers["https://example.org/post"] = .init(body: Data(#"<title>Hello &amp; bye</title><link rel=icon href="/i.png">"#.utf8))
        StubProtocol.answers["https://example.org/i.png"] = .init(type: "image/png", body: icon)
        let preview = await fetcher().preview(for: "https://example.org/post")
        XCTAssertEqual(preview.state, .done)
        XCTAssertEqual(preview.title, "Hello & bye")
        XCTAssertEqual(preview.icon, icon)
    }

    func testImageLink() async {
        let image = Self.png(width: 40, height: 30)
        StubProtocol.answers["https://cdn.example.org/a.png"] = .init(type: "image/png", body: image)
        let preview = await fetcher().preview(for: "https://cdn.example.org/a.png")
        XCTAssertEqual(preview.state, .done)
        XCTAssertEqual(preview.image, ClipImageInfo(width: 40, height: 30, format: "PNG", byteCount: image.count))
        XCTAssertEqual(preview.imageData, image)
        XCTAssertNil(preview.icon)
    }

    func testRefusals() async {
        let local = await fetcher(publicHosts: false).preview(for: "https://intranet.example.org/")
        XCTAssertEqual(local.state, .failed("The link points to a local network address."))
        let blocked = await fetcher().preview(for: "http://192.168.1.1/")
        XCTAssertEqual(blocked.state, .failed("Ting loads only public http and https links."))
        XCTAssertTrue(StubProtocol.requested.isEmpty)

        StubProtocol.answers["https://example.org/file.zip"] = .init(type: "application/zip", body: Data([1, 2]))
        let zip = await fetcher().preview(for: "https://example.org/file.zip")
        XCTAssertEqual(zip.state, .failed("Not a web page or an image (application/zip)."))

        StubProtocol.answers["https://example.org/go"] = .init(redirect: "http://127.0.0.1/admin")
        let redirected = await fetcher().preview(for: "https://example.org/go")
        XCTAssertNotEqual(redirected.state, .done)
        XCTAssertFalse(StubProtocol.requested.contains("http://127.0.0.1/admin"))

        StubProtocol.answers["https://example.org/huge.png"] = .init(type: "image/png", body: Data(count: LinkPreviewFetcher.imageLimit + 1))
        let huge = await fetcher().preview(for: "https://example.org/huge.png")
        XCTAssertEqual(huge.state, .failed("Too big to preview."))
    }

    func testResolverRejectsLocalAddresses() {
        XCTAssertFalse(LinkPreviewFetcher.resolvesPublic("127.0.0.1"))
        XCTAssertFalse(LinkPreviewFetcher.resolvesPublic("localhost"))
        XCTAssertTrue(LinkPreviewFetcher.resolvesPublic("8.8.8.8"))
    }

    @MainActor
    func testHistoryLoadsLinksOnlyWhenAllowed() async throws {
        StubProtocol.answers["https://example.org/"] = .init(body: Data("<title>Example</title>".utf8))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.bobuk.ting.tests." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, frontmost: { nil }, secureInput: { false })
        let history = ClipbawdHistory(monitor: monitor, pasteboard: pasteboard, fetcher: fetcher())
        defer { monitor.stop() }
        let link = ClipCapture(types: [ClipboardTypes.plainText], text: "https://example.org/",
                               representations: [ClipRepresentation(type: ClipboardTypes.plainText, data: Data("https://example.org/".utf8))])
        history.configure(ClipbawdSettings())
        history.record(link)
        XCTAssertNil(history.entries[0].link)
        XCTAssertTrue(StubProtocol.requested.isEmpty)

        var settings = ClipbawdSettings()
        settings.fetchLinks = true
        history.configure(settings)
        for _ in 0..<200 where history.entries[0].link?.state != .done { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(history.entries[0].link?.title, "Example")
        XCTAssertEqual(history.entries[0].title, "Example")

        // A failed link is not loaded again on every save of an unrelated setting.
        let missing = ClipCapture(types: [ClipboardTypes.plainText], text: "https://example.org/missing",
                                  representations: [ClipRepresentation(type: ClipboardTypes.plainText, data: Data("https://example.org/missing".utf8))])
        history.record(missing)
        for _ in 0..<200 where history.entries[0].link?.state == .loading { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(history.entries[0].link?.state, .failed("The site answered 404."))
        let requests = StubProtocol.requested.count
        settings.maxItems = 300
        history.configure(settings)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(StubProtocol.requested.count, requests)
    }
}
