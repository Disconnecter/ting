// Loads the title and icon of a copied web page, or the size of a copied image link, when
// Settings › clipbawd allows it. One plain GET: no cookies, no cache, no scripts, no
// credentials, never a local network address, and only a few bytes of each answer.
import Foundation
import ImageIO
import TingCore

final class LinkPreviewFetcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    /// Bytes of an image link that are loaded; a bigger image only shows its link.
    static let imageLimit = 8 * 1024 * 1024
    /// Bytes of a favicon.
    static let iconLimit = 256 * 1024
    static let timeout: TimeInterval = 6

    /// True when every address of the host is public; tests replace the DNS lookup.
    private let resolvesPublic: @Sendable (String) -> Bool
    /// Set once in `init`, before any fetch can run.
    private var session: URLSession!

    init(configuration: URLSessionConfiguration = .ephemeral,
         resolvesPublic: @escaping @Sendable (String) -> Bool = { LinkPreviewFetcher.resolvesPublic($0) }) {
        let configuration = configuration
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout * 2
        configuration.httpAdditionalHeaders = ["User-Agent": "Ting link preview", "Accept": "text/html, image/*;q=0.9"]
        self.resolvesPublic = resolvesPublic
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func preview(for link: String) async -> ClipLinkPreview {
        guard let url = ClipLinkPolicy.fetchableURL(link) else {
            return ClipLinkPreview(state: .failed("Ting loads only public http and https links."))
        }
        do {
            let (data, response) = try await load(url, limit: Self.imageLimit, htmlLimit: ClipHTMLHead.readLimit)
            let type = response.mimeType?.lowercased() ?? ""
            let base = response.url ?? url
            if type.hasPrefix("image/") {
                guard let info = Self.imageInfo(data, mimeType: type) else {
                    return ClipLinkPreview(state: .failed("The image cannot be shown."))
                }
                let icon = await favicon(ClipHTMLHead.parse(Data(), base: base).icon)
                return ClipLinkPreview(state: .done, icon: icon, image: info, imageData: data)
            }
            guard type == "text/html" || type == "application/xhtml+xml" else {
                return ClipLinkPreview(state: .failed("Not a web page or an image (\(type.isEmpty ? "no type" : type))."))
            }
            let head = ClipHTMLHead.parse(data, base: base)
            return ClipLinkPreview(state: .done, title: head.title, icon: await favicon(head.icon))
        } catch let error as FetchError {
            return ClipLinkPreview(state: .failed(error.message))
        } catch {
            return ClipLinkPreview(state: .failed((error as NSError).localizedDescription))
        }
    }

    private struct FetchError: Error {
        var message: String
    }

    /// GET with a byte limit: an HTML page stops at `htmlLimit`, anything else at `limit`.
    private func load(_ url: URL, limit: Int, htmlLimit: Int) async throws -> (Data, URLResponse) {
        guard let host = url.host, resolvesPublic(host) else {
            throw FetchError(message: "The link points to a local network address.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError(message: "The site answered \(http.statusCode).")
        }
        let isHTML = response.mimeType?.lowercased().contains("html") == true
        let cap = isHTML ? htmlLimit : limit
        if !isHTML, response.expectedContentLength > Int64(cap) {
            throw FetchError(message: "Too big to preview.")
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= cap {
                if isHTML { break }
                throw FetchError(message: "Too big to preview.")
            }
        }
        return (data, response)
    }

    private func favicon(_ url: URL?) async -> Data? {
        guard let url, let allowed = ClipLinkPolicy.fetchableURL(url.absoluteString),
              let (data, response) = try? await load(allowed, limit: Self.iconLimit, htmlLimit: 0),
              response.mimeType?.lowercased().hasPrefix("image/") == true || allowed.path.hasSuffix(".ico"),
              CGImageSourceCreateWithData(data as CFData, nil).map({ CGImageSourceGetCount($0) > 0 }) == true
        else { return nil }
        return data
    }

    static func imageInfo(_ data: Data, mimeType: String) -> ClipImageInfo? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let subtype = mimeType.split(separator: "/").last.map(String.init) ?? ""
        let format = subtype.replacingOccurrences(of: "x-", with: "").replacingOccurrences(of: "+xml", with: "").uppercased()
        return ClipImageInfo(width: width, height: height, format: format, byteCount: data.count)
    }

    /// A redirect is followed only to another public http(s) address.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, let allowed = ClipLinkPolicy.fetchableURL(url.absoluteString),
              let host = allowed.host, resolvesPublic(host) else { return nil }
        return request
    }

    /// No site may ask for a password or a client certificate.
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            return (.performDefaultHandling, nil)
        }
        return (.cancelAuthenticationChallenge, nil)
    }

    /// Every address the name resolves to must be public, so a name of the local network or
    /// one that points to it is never loaded.
    static func resolvesPublic(_ host: String) -> Bool {
        if ClipLinkPolicy.ipv4(host) != nil || host.contains(":") { return ClipLinkPolicy.isPublicHost(host) }
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }
        var found = false
        for info in sequence(first: first, next: { $0.pointee.ai_next }) {
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0
            else { return false }
            let address = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard ClipLinkPolicy.isPublicHost(address) else { return false }
            found = true
        }
        return found
    }
}
