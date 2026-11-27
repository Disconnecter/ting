import Foundation

/// A UI must explain possible macOS prompts before supplying `.allowed`.
enum ProtectedFolderPolicy: Sendable { case needsConsent, allowed }

struct LaunchaServiceIssue: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case needsConsent, denied, io, limit }
    var kind: Kind
    var url: URL
    var message: String

    static func access(_ error: Error, at url: URL) -> Self {
        let ns = error as NSError
        let denied = (ns.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(ns.code))
            || (ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code))
        return Self(kind: denied ? .denied : .io, url: url, message: error.localizedDescription)
    }
}

struct LaunchaPathPolicy: Sendable {
    var home: URL {
        didSet {
            standardizedHome = home.standardizedFileURL
            standardizedHomeComponents = standardizedHome.pathComponents
            realHome = (Self.realURL(home) ?? standardizedHome).standardizedFileURL
            realHomeComponents = realHome.pathComponents
        }
    }
    var protectedFolders: ProtectedFolderPolicy = .needsConsent
    private var standardizedHome: URL
    private var standardizedHomeComponents: [String]
    private var realHome: URL
    private var realHomeComponents: [String]

    init(home: URL, protectedFolders: ProtectedFolderPolicy = .needsConsent) {
        self.home = home
        self.protectedFolders = protectedFolders
        let standardized = home.standardizedFileURL
        self.standardizedHome = standardized
        self.standardizedHomeComponents = standardized.pathComponents
        let resolved = (Self.realURL(home) ?? standardized).standardizedFileURL
        self.realHome = resolved
        self.realHomeComponents = resolved.pathComponents
    }

    /// The iCloud Drive folder, the only place under `~/Library` that may be searched.
    static let iCloudDrivePath = "Library/Mobile Documents/com~apple~CloudDocs"
    var iCloudDrive: URL { home.appendingPathComponent(Self.iCloudDrivePath, isDirectory: true) }
    var protectedURLs: [URL] { ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0) } + [iCloudDrive] }
    func contains(_ url: URL, in root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }
    private func containsPath(_ path: String, in basePath: String) -> Bool {
        path == basePath || path.hasPrefix(basePath + "/")
    }
    private func firstHomeComponent(_ standardizedURL: URL, homePath: String, homeComponentCount: Int) -> String? {
        guard containsPath(standardizedURL.path, in: homePath) else { return nil }
        return standardizedURL.pathComponents.dropFirst(homeComponentCount).first?.lowercased()
    }
    private func inICloudDrive(_ standardizedPath: String, homePath: String) -> Bool {
        containsPath(standardizedPath, in: homePath + "/" + Self.iCloudDrivePath)
    }
    func needsConsent(_ url: URL) -> Bool {
        guard protectedFolders == .needsConsent else { return false }
        let standardized = url.standardizedFileURL
        if inICloudDrive(standardized.path, homePath: standardizedHome.path) || inICloudDrive(standardized.path, homePath: realHome.path) {
            return true
        }
        if let first = firstHomeComponent(standardized, homePath: standardizedHome.path, homeComponentCount: standardizedHomeComponents.count),
           ["desktop", "documents", "downloads"].contains(first) {
            return true
        }
        if realHome.path != standardizedHome.path,
           let first = firstHomeComponent(standardized, homePath: realHome.path, homeComponentCount: realHomeComponents.count),
           ["desktop", "documents", "downloads"].contains(first) {
            return true
        }
        return false
    }
    /// Foundation may leave intermediate symlinks unresolved when a leaf is missing.
    /// realpath fails closed instead. Never use this before the lexical policy check.
    static func realURL(_ url: URL) -> URL? {
        guard let path = realpath(url.path, nil) else { return nil }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }
    private func valid(_ standardizedPath: URL, homePath: String, homeComponentCount: Int) -> Bool {
        containsPath(standardizedPath.path, in: homePath)
            && (firstHomeComponent(standardizedPath, homePath: homePath, homeComponentCount: homeComponentCount) != "library"
                || inICloudDrive(standardizedPath.path, homePath: homePath))
            && !standardizedPath.pathComponents.contains { $0.hasPrefix(".") || $0.lowercased().hasSuffix(".app") }
            && !needsConsent(standardizedPath)
    }
    func lexicalSearchable(_ url: URL) -> Bool {
        guard !url.pathComponents.contains(where: { $0.hasPrefix(".") || $0.lowercased().hasSuffix(".app") }) else { return false }
        return valid(url.standardizedFileURL, homePath: standardizedHome.path, homeComponentCount: standardizedHomeComponents.count)
    }
    /// Check lexical paths before touching the filesystem, then check resolved paths too.
    func searchable(_ url: URL) -> Bool {
        guard lexicalSearchable(url) else { return false }
        guard let resolved = Self.realURL(url) else { return false }
        return valid(resolved.standardizedFileURL, homePath: realHome.path, homeComponentCount: realHomeComponents.count)
    }
}
