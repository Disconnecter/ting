import CryptoKit
import Foundation

// Clipbawd capture, retention and serialization. Pure logic; no pasteboard or AppKit.

// MARK: - Settings

/// clipbawd settings.
/// JSON keys are optional; persistence, count/size/age bounds and privacy rules are independent.
/// Every key is optional when decoding; a missing key takes the default below.
public struct ClipbawdSettings: Equatable, Sendable, Codable {
    /// Allowed range of `maxItems`. Decoding clamps to it.
    public static let maxItemsRange: ClosedRange<Int> = 20...1000

    /// Separate global hotkey for clipbawd. nil (default) means no separate hotkey.
    public var hotkey: Hotkey? = nil
    /// Off: Ting never reads the clipboard, the hotkey is free and all history is forgotten.
    /// Recording is on by default; persistence is a separate opt-in.
    public var enabled: Bool = true

    /// The hotkey that is in use: none while clipbawd is off.
    public var activeHotkey: Hotkey? { enabled ? hotkey : nil }
    /// Fetch the title, icon or image of a copied link. Off by default: a fetch tells the site
    /// that the link was copied.
    public var fetchLinks: Bool = false
    /// The oldest items are dropped above this count.
    public var maxItems: Int = 100
    public var persistent: Bool = false
    public static let maxMegabytesRange = 1...4096
    public static let maxDaysRange = 0...3650
    public var maxMegabytes: Int = 50
    /// Zero means no age limit. Age starts at the latest external copy, not reuse.
    public var maxDays: Int = 30
    /// Bundle identifiers of apps whose copies are never kept.
    public var excludedApps: [String] = []
    /// Text that starts with one of these strings (after leading spaces) is never kept.
    /// Case-sensitive, so `sk-` does not drop "Sk-ating".
    public var ignoredPrefixes: [String] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case hotkey, enabled, fetchLinks, maxItems, persistent, maxMegabytes, maxDays, excludedApps, ignoredPrefixes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ClipbawdSettings()
        hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        fetchLinks = try container.decodeIfPresent(Bool.self, forKey: .fetchLinks) ?? defaults.fetchLinks
        let count = try container.decodeIfPresent(Int.self, forKey: .maxItems) ?? defaults.maxItems
        let range = ClipbawdSettings.maxItemsRange
        maxItems = min(max(count, range.lowerBound), range.upperBound)
        persistent = try container.decodeIfPresent(Bool.self, forKey: .persistent) ?? defaults.persistent
        maxMegabytes = min(max(try container.decodeIfPresent(Int.self, forKey: .maxMegabytes) ?? defaults.maxMegabytes, 1), 4096)
        maxDays = min(max(try container.decodeIfPresent(Int.self, forKey: .maxDays) ?? defaults.maxDays, 0), 3650)
        excludedApps = try container.decodeIfPresent([String].self, forKey: .excludedApps) ?? defaults.excludedApps
        ignoredPrefixes = try container.decodeIfPresent([String].self, forKey: .ignoredPrefixes) ?? defaults.ignoredPrefixes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let hotkey {
            try container.encode(hotkey, forKey: .hotkey)
        } else {
            try container.encodeNil(forKey: .hotkey)
        }
        try container.encode(enabled, forKey: .enabled)
        try container.encode(fetchLinks, forKey: .fetchLinks)
        try container.encode(maxItems, forKey: .maxItems)
        try container.encode(persistent, forKey: .persistent)
        try container.encode(maxMegabytes, forKey: .maxMegabytes)
        try container.encode(maxDays, forKey: .maxDays)
        try container.encode(excludedApps, forKey: .excludedApps)
        try container.encode(ignoredPrefixes, forKey: .ignoredPrefixes)
    }

    /// The rules a capture is checked against.
    public var rules: ClipRules {
        ClipRules(excludedApps: Set(excludedApps), ignoredPrefixes: ignoredPrefixes)
    }

    /// Adds an app to `excludedApps` once. Returns false when it was already there or empty.
    @discardableResult
    public mutating func exclude(app bundleID: String) -> Bool {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !excludedApps.contains(id) else { return false }
        excludedApps.append(id)
        return true
    }
}

// MARK: - Pasteboard types

/// Pasteboard type identifiers clipbawd reads or respects.
public enum ClipboardTypes {
    public static let plainText = "public.utf8-plain-text"
    public static let rtf = "public.rtf"
    public static let html = "public.html"
    public static let png = "public.png"
    public static let tiff = "public.tiff"
    public static let jpeg = "public.jpeg"
    public static let fileURL = "public.file-url"
    public static let markdown = "net.daringfireball.markdown"
    public static let mpeg4 = "public.mpeg-4"
    public static let quickTime = "com.apple.quicktime-movie"
    public static let videoTypes = [mpeg4, quickTime]

    /// Markers of http://nspasteboard.org: a password, a value that is replaced at once, or
    /// one made by a program rather than the person. Such a change is never kept.
    public static let concealed = "org.nspasteboard.ConcealedType"
    public static let transient = "org.nspasteboard.TransientType"
    public static let autoGenerated = "org.nspasteboard.AutoGeneratedType"
    public static let skipMarkers: Set<String> = [concealed, transient, autoGenerated]

    /// Types the app reads; everything else on the pasteboard is never loaded.
    public static let read: [String] = [plainText, markdown, rtf, html, png, tiff, jpeg, fileURL] + videoTypes
}

// MARK: - Capture

/// One pasteboard type and its bytes, kept to put the item back on the clipboard.
public struct ClipRepresentation: Equatable, Sendable, Codable {
    public var type: String
    public var data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

public struct ClipImageInfo: Equatable, Sendable, Codable {
    public var width: Int
    public var height: Int
    /// Upper-case short name: "PNG", "TIFF", "JPEG".
    public var format: String
    public var byteCount: Int

    public init(width: Int, height: Int, format: String, byteCount: Int) {
        self.width = width
        self.height = height
        self.format = format
        self.byteCount = byteCount
    }
}

public struct ClipFile: Equatable, Sendable, Codable {
    public var path: String
    /// nil for a folder or a file that could not be read.
    public var byteCount: Int64?
    public var isDirectory: Bool

    public init(path: String, byteCount: Int64?, isDirectory: Bool) {
        self.path = path
        self.byteCount = byteCount
        self.isDirectory = isDirectory
    }

    public var name: String { (path as NSString).lastPathComponent }
}

/// The app that was in front when the clipboard changed.
public struct ClipSource: Equatable, Sendable, Codable {
    public var bundleID: String?
    public var name: String

    public init(bundleID: String?, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// What the app read from one clipboard change.
public struct ClipCapture: Equatable, Sendable {
    /// Every type on the pasteboard (the list only, without data).
    public var types: [String]
    /// `public.utf8-plain-text`, if present.
    public var text: String?
    public var image: ClipImageInfo?
    public var files: [ClipFile]
    public var video: ClipVideoInfo?
    /// Set when video validation failed: never fall back to storing its file reference.
    public var rejectedVideo = false
    /// The known representations, written back on paste or copy.
    public var representations: [ClipRepresentation]
    public var source: ClipSource?
    /// Set by the app when the copy must not be kept: a private browser window, secure
    /// keyboard input or a locked screen.
    public var privateContext: Bool

    public init(types: [String], text: String? = nil, image: ClipImageInfo? = nil, files: [ClipFile] = [],
                representations: [ClipRepresentation] = [], source: ClipSource? = nil, privateContext: Bool = false,
                video: ClipVideoInfo? = nil) {
        self.types = types
        self.text = text
        self.image = image
        self.files = files
        self.video = video
        self.representations = representations
        self.source = source
        self.privateContext = privateContext
    }
}

// MARK: - Content

public struct ClipVideoInfo: Equatable, Sendable, Codable {
    public var duration: Double
    public var thumbnail: Data?
    public var name: String

    public init(duration: Double, thumbnail: Data? = nil, name: String = "Video") {
        self.duration = duration
        self.thumbnail = thumbnail
        self.name = name
    }
}

public enum ClipKind: String, Sendable, CaseIterable, Codable {
    case text, link, image, files, color, video
}

public enum ClipContent: Equatable, Sendable, Codable {
    /// `rich` when RTF or HTML came with the text.
    case text(String, rich: Bool)
    /// One http or https URL and nothing else.
    case link(String)
    case image(ClipImageInfo)
    case video(ClipVideoInfo)
    case files([ClipFile])
    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA`, as copied.
    case color(String)

    public var kind: ClipKind {
        switch self {
        case .text: .text
        case .link: .link
        case .image: .image
        case .video: .video
        case .files: .files
        case .color: .color
        }
    }

    /// The content of a capture, or nil when there is nothing clipbawd keeps.
    /// Files win (Finder also puts the icon and the name). Text wins over an image, since
    /// Word or Keynote add a picture of the copied text, unless the text is only the link of the
    /// image, as a browser's Copy Image gives.
    public static func classify(_ capture: ClipCapture) -> ClipContent? {
        if capture.rejectedVideo { return nil }
        if let video = capture.video {
            guard video.duration.isFinite, video.duration > 0, video.duration <= 30 else { return nil }
            return .video(video)
        }
        if !capture.files.isEmpty { return .files(capture.files) }
        let text = capture.text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let image = capture.image, text == nil || isLink(trimmed) { return .image(image) }
        guard let text else { return nil }
        let rich = capture.types.contains(ClipboardTypes.rtf) || capture.types.contains(ClipboardTypes.html)
        if isLink(trimmed) { return .link(trimmed) }
        if isColor(trimmed) { return .color(trimmed) }
        return .text(text, rich: rich)
    }

    /// One http(s) URL with a host and no spaces.
    static func isLink(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    static func isColor(_ text: String) -> Bool {
        guard text.first == "#" else { return false }
        let digits = text.dropFirst()
        return [3, 6, 8].contains(digits.count) && digits.allSatisfy(\.isHexDigit)
    }

    /// The representations an item keeps: text never holds the picture of itself.
    func kept(_ representations: [ClipRepresentation]) -> [ClipRepresentation] {
        switch self {
        case .text, .link, .color:
            let text: Set<String> = [ClipboardTypes.plainText, ClipboardTypes.markdown, ClipboardTypes.rtf, ClipboardTypes.html]
            return representations.filter { text.contains($0.type) }
        case .image, .files, .video:
            return representations
        }
    }

    /// What "paste as plain text" pastes: the text without RTF or HTML; nil for images, videos and files.
    public var plainText: String? { checkedText }

    /// The string checked against `ignoredPrefixes`; nil for images and files.
    var checkedText: String? {
        switch self {
        case .text(let text, _): text
        case .link(let text), .color(let text): text
        case .image, .files, .video: nil
        }
    }

    /// Bytes that identify the content: equal content gives an equal digest, whatever app it
    /// came from and whether the text was rich or plain.
    func identity(representations: [ClipRepresentation]) -> Data {
        var data = Data(kind.rawValue.utf8)
        data.append(0)
        switch self {
        case .text(let text, _): data.append(contentsOf: text.utf8)
        case .link(let text), .color(let text): data.append(contentsOf: text.utf8)
        case .image(let info):
            let types = [ClipboardTypes.png, ClipboardTypes.tiff, ClipboardTypes.jpeg]
            if let image = representations.first(where: { types.contains($0.type) }) {
                data.append(image.data)
            } else {
                data.append(contentsOf: "\(info.width)x\(info.height)".utf8)
            }
        case .video:
            for representation in representations where ClipboardTypes.videoTypes.contains(representation.type) {
                data.append(representation.data)
            }
        case .files(let files): data.append(contentsOf: files.map(\.path).joined(separator: "\n").utf8)
        }
        return data
    }
}

/// SHA-256 of a content identity. Computed once per clipboard change.
public struct ClipDigest: Hashable, Sendable, Codable {
    public let bytes: Data

    public init(_ data: Data) { bytes = Data(SHA256.hash(data: data)) }
}

// MARK: - Link preview

/// What a link fetch found. Filled only when `fetchLinks` is on.
public struct ClipLinkPreview: Equatable, Sendable, Codable {
    public enum State: Equatable, Sendable, Codable {
        case loading
        case done
        /// The link is not fetched: not http(s), a local address, or the fetch failed.
        case failed(String)
    }

    public var state: State
    public var title: String?
    /// Favicon bytes, any image format.
    public var icon: Data?
    /// The link itself is an image.
    public var image: ClipImageInfo?
    public var imageData: Data?

    public init(state: State, title: String? = nil, icon: Data? = nil, image: ClipImageInfo? = nil, imageData: Data? = nil) {
        self.state = state
        self.title = title
        self.icon = icon
        self.image = image
        self.imageData = imageData
    }
}

// MARK: - Entry

public struct ClipEntry: Equatable, Sendable, Identifiable, Codable {
    /// Unique across the retained history; never reused.
    public let id: Int
    public let digest: ClipDigest
    public var content: ClipContent
    public var representations: [ClipRepresentation]
    /// The app of the latest copy.
    public var source: ClipSource?
    public var firstCopied: Date
    public var lastCopied: Date
    /// How many times this content was copied; a repeat moves the item up instead of adding one.
    public var copyCount: Int
    public var link: ClipLinkPreview?
    /// Folded text for search, at most `ClipHistory.searchLimit` characters of the content.
    let searchText: String

    init(id: Int, digest: ClipDigest, capture: ClipCapture, content: ClipContent, at date: Date) {
        self.id = id
        self.digest = digest
        self.content = content
        representations = content.kept(capture.representations)
        source = capture.source
        firstCopied = date
        lastCopied = date
        copyCount = 1
        searchText = ClipEntry.searchText(for: content)
    }

    /// Bytes held in memory for this item.
    public var byteCount: Int {
        let thumbnail: Int
        if case .video(let info) = content { thumbnail = info.thumbnail?.count ?? 0 } else { thumbnail = 0 }
        return representations.reduce(0) { $0 + $1.data.count } + (link?.icon?.count ?? 0) + (link?.imageData?.count ?? 0) + thumbnail
    }

    /// One line for the list.
    public var title: String {
        switch content {
        case .text(let text, _):
            let line = text.split(whereSeparator: \.isNewline)
                .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
            return line.count > 200 ? String(line.prefix(200)) + "…" : line
        case .link(let url): return link?.title ?? url
        case .image(let info): return "Image \(info.width) × \(info.height)"
        case .video(let info): return info.name
        case .files(let files):
            guard let first = files.first else { return "" }
            return files.count == 1 ? first.name : "\(first.name) and \(files.count - 1) more"
        case .color(let hex): return hex
        }
    }

    private static func searchText(for content: ClipContent) -> String {
        let raw: String = switch content {
        case .text(let text, _): String(text.prefix(ClipHistory.searchLimit))
        case .link(let url): url
        case .image(let info): "image \(info.format) \(info.width)x\(info.height)"
        case .video(let info): "video \(info.name)"
        case .files(let files): files.map(\.name).joined(separator: " ")
        case .color(let hex): hex
        }
        return NameMatcher.fold(raw)
    }
}

// MARK: - History

/// Why a capture was not kept.
public enum ClipSkipReason: Equatable, Sendable {
    /// Recording is off.
    case disabled
    /// Nothing clipbawd keeps: empty text or only unknown types.
    case empty
    /// A password manager or a program marked the value (nspasteboard.org markers).
    case marked
    /// A private browser window, secure keyboard input or a locked screen.
    case privateContext
    case excludedApp(String)
    case ignoredPrefix(String)
    /// Bigger than `ClipHistory.maxItemBytes`.
    case tooLarge
}

public enum ClipRecordResult: Equatable, Sendable {
    case added(Int)
    /// Equal content was already in the list: it moved to the top.
    case merged(Int)
    case skipped(ClipSkipReason)
}

public struct ClipRules: Equatable, Sendable {
    public var excludedApps: Set<String>
    public var ignoredPrefixes: [String]

    public init(excludedApps: Set<String> = [], ignoredPrefixes: [String] = []) {
        self.excludedApps = excludedApps
        self.ignoredPrefixes = ignoredPrefixes
    }

    /// Why the capture must not be kept, or nil. Checked before any hash is computed.
    public func skipReason(for capture: ClipCapture, content: ClipContent?) -> ClipSkipReason? {
        if capture.types.contains(where: ClipboardTypes.skipMarkers.contains) { return .marked }
        if capture.privateContext { return .privateContext }
        if let id = capture.source?.bundleID, excludedApps.contains(id) { return .excludedApp(id) }
        guard let content else { return .empty }
        if let text = content.checkedText {
            let start = text.drop { $0.isWhitespace }
            if let prefix = ignoredPrefixes.first(where: { !$0.isEmpty && start.hasPrefix($0) }) {
                return .ignoredPrefix(prefix)
            }
        }
        return nil
    }
}

/// The retained history, newest first by copy or reuse.
public struct ClipHistory: Sendable, Codable {
    /// Characters of a text kept for search; the rest is still pasted.
    public static let searchLimit = 4096
    /// One item above this size is not kept.
    public static let maxItemBytes = 32 * 1024 * 1024
    public private(set) var entries: [ClipEntry] = []
    public var maxItems: Int
    public var byteLimit: Int = 50 * 1024 * 1024
    public var maxDays: Int = 30
    private var nextID = 1

    public init(maxItems: Int = ClipbawdSettings().maxItems) {
        self.maxItems = maxItems
    }

    public var totalBytes: Int { entries.reduce(0) { $0 + $1.byteCount } }

    public func entry(id: Int) -> ClipEntry? { entries.first { $0.id == id } }

    /// Keeps a capture, merges it with equal content, or says why it was skipped.
    public mutating func record(_ capture: ClipCapture, rules: ClipRules, at date: Date) -> ClipRecordResult {
        let content = ClipContent.classify(capture)
        if let reason = rules.skipReason(for: capture, content: content) { return .skipped(reason) }
        guard let content else { return .skipped(.empty) }
        let bytes = content.kept(capture.representations).reduce(0, { $0 + $1.data.count })
            + (capture.video?.thumbnail?.count ?? 0)
        guard bytes <= min(Self.maxItemBytes, byteLimit) else { return .skipped(.tooLarge) }
        prune(at: date)
        let digest = ClipDigest(content.identity(representations: capture.representations))
        if let index = entries.firstIndex(where: { $0.digest == digest }) {
            var entry = entries.remove(at: index)
            entry.lastCopied = date
            entry.copyCount += 1
            entry.source = capture.source ?? entry.source
            entry.content = content
            let kept = content.kept(capture.representations)
            if !kept.isEmpty { entry.representations = kept }
            entries.insert(entry, at: 0)
            prune(at: date)
            return .merged(entry.id)
        }
        let entry = ClipEntry(id: nextID, digest: digest, capture: capture, content: content, at: date)
        nextID += 1
        entries.insert(entry, at: 0)
        prune(at: date)
        return .added(entry.id)
    }

    /// Moves an item to the top after Ting put it back on the clipboard.
    public mutating func promote(id: Int, at date: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        // Reuse changes ordering, not the retention age of the external copy.
        entries.insert(entry, at: 0)
    }

    public mutating func remove(id: Int) { entries.removeAll { $0.id == id } }

    public mutating func removeAll() { entries.removeAll() }

    /// Drops every item from these apps, after an app was excluded.
    public mutating func removeAll(fromApp bundleID: String) {
        entries.removeAll { $0.source?.bundleID == bundleID }
    }

    public mutating func setLink(_ preview: ClipLinkPreview, for id: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].link = preview
    }

    /// Drop expired entries first, then the oldest external copies until every bound holds.
    public mutating func prune(at date: Date = Date()) {
        if maxDays > 0 {
            let cutoff = date.addingTimeInterval(-Double(maxDays) * 86_400)
            entries.removeAll { $0.lastCopied < cutoff }
        }
        var total = totalBytes
        while entries.count > max(0, maxItems) || total > max(0, byteLimit) {
            guard let index = entries.indices.min(by: {
                entries[$0].lastCopied == entries[$1].lastCopied ? $0 > $1 : entries[$0].lastCopied < entries[$1].lastCopied
            }) else { break }
            total -= entries.remove(at: index).byteCount
        }
    }

    public mutating func apply(_ settings: ClipbawdSettings, at date: Date) {
        maxItems = settings.maxItems
        byteLimit = settings.maxMegabytes * 1024 * 1024
        maxDays = settings.maxDays
        entries.removeAll { entry in
            if let id = entry.source?.bundleID, settings.excludedApps.contains(id) { return true }
            guard let text = entry.content.checkedText else { return false }
            return settings.ignoredPrefixes.contains { !$0.isEmpty && text.drop(while: \.isWhitespace).hasPrefix($0) }
        }
        prune(at: date)
    }

    /// Restored entries retain identities and copy metadata, without replaying capture rules.
    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ClipHistory {
        var history = try PropertyListDecoder().decode(ClipHistory.self, from: data)
        guard Set(history.entries.map(\.id)).count == history.entries.count,
              history.entries.allSatisfy({ $0.id > 0 && $0.id < Int.max && $0.copyCount > 0 }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        history.nextID = (history.entries.map(\.id).max() ?? 0) + 1
        return history
    }

    /// Items whose text contains every query word, newest first. A query without letters or
    /// digits lists every item. Also tries the query as typed with the wrong keyboard layout.
    public func search(_ query: String) -> [ClipEntry] {
        let variants = KeyboardLayoutSwap.variants(of: query).map(NameMatcher.words(in:)).filter { !$0.isEmpty }
        guard !variants.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = entry.link?.title.map { entry.searchText + " " + NameMatcher.fold($0) } ?? entry.searchText
            let source = entry.source.map { NameMatcher.fold($0.name) } ?? ""
            return variants.contains { words in
                words.allSatisfy { haystack.contains($0) || source.contains($0) }
            }
        }
    }
}

// MARK: - Details for the preview

public enum ClipDetails {
    /// Label and value rows for the preview of one item, without the dates and the source.
    /// Counting runs only for the selected item, never at capture.
    public static func rows(for entry: ClipEntry) -> [(label: String, value: String)] {
        switch entry.content {
        case .text(let text, let rich):
            return [("Type", rich ? "Rich text" : "Text"),
                    ("Characters", number(text.count)),
                    ("Words", number(wordCount(text))),
                    ("Lines", number(lineCount(text)))]
        case .link(let url):
            var rows: [(label: String, value: String)] = [("Type", "Link")]
            if let host = URL(string: url)?.host { rows.append(("Host", host)) }
            rows.append(("Length", number(url.count)))
            if let image = entry.link?.image {
                rows.append(("Image", "\(image.width) × \(image.height) px, \(image.format)"))
                rows.append(("Size", bytes(Int64(image.byteCount))))
            }
            return rows
        case .image(let info):
            return [("Type", "Image"),
                    ("Dimensions", "\(info.width) × \(info.height) px"),
                    ("Format", info.format),
                    ("Size", bytes(Int64(info.byteCount)))]
        case .video(let info):
            return [("Type", "Video"), ("Duration", String(format: "%.1f s", info.duration)),
                    ("Size", bytes(Int64(entry.byteCount)))]
        case .files(let files):
            var rows: [(label: String, value: String)] = [("Type", files.count == 1 ? (files[0].isDirectory ? "Folder" : "File") : "Files")]
            if files.count > 1 { rows.append(("Items", number(files.count))) }
            let sizes = files.compactMap(\.byteCount)
            if !sizes.isEmpty { rows.append(("Size", bytes(sizes.reduce(0, +)))) }
            if files.count == 1 { rows.append(("Path", files[0].path)) }
            return rows
        case .color(let hex):
            return [("Type", "Color"), ("Value", hex)]
        }
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    static func lineCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let breaks = text.reduce(0) { $1.isNewline ? $0 + 1 : $0 }
        return text.last?.isNewline == true ? breaks : breaks + 1
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

// MARK: - Link fetching

public enum ClipLinkPolicy {
    /// The URL a link preview may fetch, or nil. Only http(s) without a user name or a
    /// password, and never a local or private address: a GET to a router or an intranet
    /// page can change something there.
    public static func fetchableURL(_ text: String) -> URL? {
        guard ClipContent.isLink(text), let url = URL(string: text),
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
              isPublicHost(host) else { return nil }
        return url
    }

    /// False for localhost, single-label and `.local` names and private or special IP addresses.
    public static func isPublicHost(_ host: String) -> Bool {
        let host = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard !host.isEmpty else { return false }
        if let octets = ipv4(host) { return isPublicIPv4(octets) }
        if host.contains(":") { return isPublicIPv6(host) }
        guard host.contains(".") else { return false }
        let local = ["localhost", "local", "internal", "lan", "home", "arpa", "test", "invalid", "example"]
        return !local.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    public static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part), value <= 255 else { return nil }
            return value
        }
        return octets.count == 4 ? octets : nil
    }

    static func isPublicIPv4(_ o: [Int]) -> Bool {
        switch (o[0], o[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168), (255, _): return false
        case (172, 16...31), (100, 64...127): return false
        case (224...239, _), (240...254, _): return false
        default: return true
        }
    }

    static func isPublicIPv6(_ host: String) -> Bool {
        let address = (host.split(separator: "%").first.map(String.init) ?? host).lowercased()
        if address == "::1" || address == "::" { return false }
        guard let first = address.split(separator: ":", omittingEmptySubsequences: false).first,
              let group = UInt16(first.isEmpty ? "0" : first, radix: 16) else { return false }
        if group & 0xfe00 == 0xfc00 { return false }   // fc00::/7 unique local
        if group & 0xffc0 == 0xfe80 { return false }   // fe80::/10 link local
        if group & 0xff00 == 0xff00 { return false }   // multicast
        if address.hasPrefix("::ffff:") { return false } // mapped IPv4: not resolved here
        // Permit only global unicast. Reject IPv4-compatible/mapped, NAT64 and other
        // translation ranges as well as their alternate uppercase spellings.
        return group & 0xe000 == 0x2000
    }
}

/// The title and icon of an HTML page, read from its first bytes without running anything.
public struct ClipHTMLHead: Equatable, Sendable {
    /// Bytes of a page that are read.
    public static let readLimit = 64 * 1024

    public var title: String?
    /// The icon named by the page, or `/favicon.ico` of the host.
    public var icon: URL?

    public init(title: String?, icon: URL?) {
        self.title = title
        self.icon = icon
    }

    public static func parse(_ data: Data, base: URL) -> ClipHTMLHead {
        let text = String(decoding: data.prefix(readLimit), as: UTF8.self)
        return ClipHTMLHead(title: title(in: text), icon: icon(in: text, base: base))
    }

    static func title(in text: String) -> String? {
        guard let open = text.range(of: "<title", options: .caseInsensitive),
              let openEnd = text[open.upperBound...].firstIndex(of: ">"),
              let close = text.range(of: "</title", options: .caseInsensitive, range: text.index(after: openEnd)..<text.endIndex) else { return nil }
        let raw = text[text.index(after: openEnd)..<close.lowerBound]
        let words = decodeEntities(String(raw)).split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let title = words.joined(separator: " ")
        guard !title.isEmpty else { return nil }
        return title.count > 300 ? String(title.prefix(300)) + "…" : title
    }

    static func icon(in text: String, base: URL) -> URL? {
        var best: (rank: Int, url: URL)?
        var cursor = text.startIndex
        while let open = text.range(of: "<link", options: .caseInsensitive, range: cursor..<text.endIndex) {
            guard let end = text[open.upperBound...].firstIndex(of: ">") else { break }
            let tag = String(text[open.upperBound..<end])
            cursor = end
            let attributes = attributes(of: tag)
            guard let rel = attributes["rel"]?.lowercased(), let href = attributes["href"],
                  let url = URL(string: decodeEntities(href), relativeTo: base)?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            let tokens = Set(rel.split(separator: " ").map(String.init))
            let rank: Int
            if tokens.contains("icon") { rank = 0 }
            else if tokens.contains("apple-touch-icon") { rank = 1 }
            else { continue }
            if best == nil || rank < best!.rank { best = (rank, url) }
        }
        if let best { return best.url }
        var components = URLComponents()
        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port
        components.path = "/favicon.ico"
        return components.url
    }

    /// Attribute names in lower case; values without quotes or entity decoding.
    static func attributes(of tag: String) -> [String: String] {
        var result: [String: String] = [:]
        var index = tag.startIndex
        func skipSpaces() { while index < tag.endIndex, tag[index].isWhitespace { index = tag.index(after: index) } }
        while index < tag.endIndex {
            skipSpaces()
            let nameStart = index
            while index < tag.endIndex, !tag[index].isWhitespace, tag[index] != "=", tag[index] != "/" { index = tag.index(after: index) }
            let name = tag[nameStart..<index].lowercased()
            skipSpaces()
            guard index < tag.endIndex, tag[index] == "=" else {
                if index < tag.endIndex, name.isEmpty { index = tag.index(after: index) }
                continue
            }
            index = tag.index(after: index)
            skipSpaces()
            guard index < tag.endIndex else { break }
            let value: Substring
            if tag[index] == "\"" || tag[index] == "'" {
                let quote = tag[index]
                let start = tag.index(after: index)
                let end = tag[start...].firstIndex(of: quote) ?? tag.endIndex
                value = tag[start..<end]
                index = end < tag.endIndex ? tag.index(after: end) : end
            } else {
                let start = index
                while index < tag.endIndex, !tag[index].isWhitespace { index = tag.index(after: index) }
                value = tag[start..<index]
            }
            if !name.isEmpty, result[name] == nil { result[name] = String(value) }
        }
        return result
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: Character] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                                          "mdash": "—", "ndash": "–", "hellip": "…", "laquo": "«", "raquo": "»"]
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semicolon = after.prefix(10).firstIndex(of: ";") {
                let name = after[..<semicolon]
                var decoded: Character?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(Character.init)
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map(Character.init)
                } else {
                    decoded = named[name.lowercased()]
                }
                if let decoded {
                    result.append(decoded)
                    rest = after[after.index(after: semicolon)...]
                    continue
                }
            }
            result.append("&")
            rest = after
        }
        return result + rest
    }
}

// MARK: - Private windows

/// How Ting tells that a copy came from a private browser window. Checked only when the app in
/// front is a known browser; an answer Ting cannot get keeps the copy.
public enum ClipPrivateWindow {
    public enum Check: Equatable, Sendable {
        /// Read the front window title through Accessibility (Firefox family).
        case title
        /// Ask the browser with AppleScript for `mode of front window` (Chromium family).
        case script(String)
    }

    /// Firefox and its forks name a private window in its title.
    public static let titleBrowsers: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "org.mozilla.librewolf", "app.zen-browser.zen", "net.waterfox.waterfox", "io.gitlab.librewolf-community",
    ]

    /// Chromium browsers whose AppleScript window has `mode` ("normal" or "incognito").
    public static let modeBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
    ]

    public static func check(for bundleID: String?) -> Check? {
        guard let bundleID else { return nil }
        if titleBrowsers.contains(bundleID) { return .title }
        if modeBrowsers.contains(bundleID) {
            return .script("""
                with timeout of 2 seconds
                    tell application id "\(bundleID)"
                        if (count of windows) is 0 then return "normal"
                        return mode of front window
                    end tell
                end timeout
                """)
        }
        return nil
    }

    /// "Mozilla Firefox Private Browsing", "Page — Private Browsing", "Page (Private Browsing)".
    public static func isPrivate(title: String) -> Bool {
        title.range(of: "Private Browsing", options: [.caseInsensitive]) != nil
    }

    public static func isPrivate(mode: String) -> Bool {
        mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "incognito"
    }
}
