import Foundation

/// Public metadata from Lowkey's settings. Never reads website data, cookies or credentials.
public struct LowkeySite: Equatable, Sendable, Identifiable {
    public enum Command: String, CaseIterable, Sendable { case open, toggle }

    public let id: String
    public let alias: String
    public let name: String
    public let startURL: URL

    public func url(_ command: Command = .open) -> URL {
        // The decoder admits only Lowkey's ASCII aliases, so no URL escaping is needed.
        URL(string: "lowkey://\(alias)/\(command.rawValue)")!
    }

    public var candidate: LaunchaCandidate {
        LaunchaCandidate(id: id, name: name, target: .url(url().absoluteString),
                         searchNames: [alias, startURL.host ?? ""])
    }

    public enum ReadError: Error { case tooLarge, invalidSettings }
    public static let maximumConfigSize = 1_048_576

    /// Tolerates extra keys and skips invalid sites, but never guesses aliases from URLs.
    public static func decode(_ data: Data) throws -> [LowkeySite] {
        guard data.count <= maximumConfigSize else { throw ReadError.tooLarge }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.invalidSettings
        }
        guard let rawSites = object["sites"] else { return [] }
        guard let sites = rawSites as? [Any] else { throw ReadError.invalidSettings }
        var aliases: Set<String> = [], identities: Set<String> = []
        return sites.compactMap { entry in
            guard let site = entry as? [String: Any], let alias = site["alias"] as? String,
                  validAlias(alias), let address = site["startURL"] as? String,
                  let url = startAddress(address) else { return nil }
            let key = alias.lowercased()
            let uuid = (site["id"] as? String).flatMap(UUID.init(uuidString:))
            let id = "lowkey:" + (uuid?.uuidString.lowercased() ?? key)
            guard !aliases.contains(key), !identities.contains(id) else { return nil }
            aliases.insert(key)
            identities.insert(id)
            let title = (site["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return LowkeySite(id: id, alias: alias, name: title.isEmpty ? alias : title, startURL: url)
        }
    }

    /// Lowkey also accepts bare host names in startURL, not just absolute URLs.
    private static func startAddress(_ address: String) -> URL? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if text.contains("://") {
            guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false else { return nil }
            return url
        }
        guard let host = URL(string: "http://" + text)?.host, !host.isEmpty,
              host.contains(".") || host == "localhost" || host.contains(":")
                || text.dropFirst(host.count).hasPrefix(":") else { return nil }
        let plainHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let loopback = plainHost == "localhost" || plainHost.hasSuffix(".localhost")
            || plainHost.hasPrefix("127.") || plainHost == "::1"
        return URL(string: "\(loopback ? "http" : "https")://\(text)")
    }

    private static func validAlias(_ alias: String) -> Bool {
        guard !alias.isEmpty, alias.count <= 32, let first = alias.unicodeScalars.first,
              first.isASCII, CharacterSet.alphanumerics.contains(first) else { return false }
        return alias.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
        }
    }
}
