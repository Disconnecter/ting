import AppKit
import Darwin
import TingCore

struct IndexedLaunchaApp: Equatable, Sendable {
    var candidate: LaunchaCandidate
    /// Always launch this URL, not a new bundle-ID lookup.
    var url: URL
}

/// App scans run on this actor. Call refreshOnOpen for every panel opening; it skips the
/// filesystem walk when no watched app directory changed since the last scan.
/// While open, call refreshIfNeeded periodically; it scans at most once per minute.
actor LaunchaAppIndex {
    struct Snapshot: Equatable, Sendable {
        var apps: [IndexedLaunchaApp]
        var issues: [LaunchaServiceIssue]
    }

    private struct FileStamp: Equatable {
        var inode: UInt64
        var nlink: UInt16
        var size: Int64
        var mtimeSec: Int
        var mtimeNsec: Int

        static func read(path: String) -> FileStamp? {
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            return FileStamp(inode: info.st_ino, nlink: info.st_nlink, size: info.st_size,
                             mtimeSec: info.st_mtimespec.tv_sec, mtimeNsec: info.st_mtimespec.tv_nsec)
        }
    }

    private struct AppStamp: Equatable {
        var bundle: FileStamp?
        var infoPlist: FileStamp?
    }

    /// Root is depth 0 (`/Applications`); depth 1 is `/Applications/Safari.app` or `/Applications/Utilities`;
    /// depth 2 is `/Applications/Utilities/Terminal.app`. Deeper non-app subtrees are never walked.
    static let defaultMaxDepth = 2

    /// Common macOS package extensions skipped without hitting LaunchServices.
    private static let packageExtensions: Set<String> = [
        "action", "appex", "bundle", "framework", "kext", "mdimporter", "mpkg", "photoslibrary",
        "pkg", "playground", "plugin", "prefpane", "qlgenerator", "rtfd", "saver", "scptd",
        "workflow", "xcarchive", "xcodeproj", "xcworkspace", "xpc"
    ]

    private let roots: [URL]
    private let policy: LaunchaPathPolicy
    private let maxDepth: Int
    private var cached = Snapshot(apps: [], issues: [])
    private var lastRefresh: Date?
    /// Last observed stat of every scanned (or missing) root/directory.
    private var scannedDirs: [String: FileStamp?] = [:]
    /// Cached bundle metadata keyed by resolved `.app` path so unchanged apps skip `Bundle(url:)`.
    private var bundleCache: [String: (stamp: AppStamp, app: IndexedLaunchaApp)] = [:]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         protectedFolders: ProtectedFolderPolicy = .needsConsent, roots: [URL]? = nil,
         maxDepth: Int = LaunchaAppIndex.defaultMaxDepth) {
        self.roots = roots ?? [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            // Include Finder without indexing the other CoreServices bundles.
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            home.appendingPathComponent("Applications"),
            home.appendingPathComponent("Desktop")
        ]
        self.maxDepth = max(0, maxDepth)
        policy = LaunchaPathPolicy(home: home, protectedFolders: protectedFolders)
    }

    func refreshIfNeeded(now: Date = Date()) -> Snapshot {
        if let lastRefresh, now.timeIntervalSince(lastRefresh) < 60 { return cached }
        return refreshOnOpen()
    }

    func refreshOnOpen() -> Snapshot {
        guard !Task.isCancelled else { return cached }
        if lastRefresh != nil, directoriesUnchanged() {
            return cached
        }
        let fm = FileManager.default
        var result = Snapshot(apps: [], issues: [])
        var visited: Set<String> = []
        var ids: Set<String> = []
        var watchedDirs: [String: FileStamp?] = [:]
        var nextBundleCache: [String: (stamp: AppStamp, app: IndexedLaunchaApp)] = [:]
        // Keep directory iterators, not recursive calls or complete child lists.
        enum Work {
            case visit(URL, depth: Int, isRoot: Bool, prefetched: URLResourceValues?)
            case children(FileManager.DirectoryEnumerator, depth: Int)
        }
        // Only prefetch true filesystem attributes; `.isPackageKey` is checked separately on
        // non-`.app` directories so Foundation's enumerator never caches a stale false for `.bundle`.
        let prefetchKeys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey]
        var work = roots.reversed().map { Work.visit($0, depth: 0, isRoot: true, prefetched: nil) }
        while !Task.isCancelled, let next = work.popLast() {
            let lexical: URL
            let depth: Int
            let isRoot: Bool
            let prefetched: URLResourceValues?
            switch next {
            case .visit(let url, let d, let root, let values):
                lexical = url
                depth = d
                isRoot = root
                prefetched = values
            case .children(let children, let childDepth):
                guard let child = children.nextObject() as? URL else { continue }
                work.append(.children(children, depth: childDepth))
                let name = child.lastPathComponent
                if name.hasPrefix(".") { continue }
                let isAppName = child.pathExtension.lowercased() == "app"
                // At maxDepth only `.app` entries can yield results; skip everything else with zero syscalls.
                if childDepth >= maxDepth, !isAppName { continue }
                let values = try? child.resourceValues(forKeys: Set(prefetchKeys))
                // Skip ordinary files immediately without realpath, consent or LaunchServices lookups.
                if let values {
                    let isDir = values.isDirectory == true
                    let isLink = values.isSymbolicLink == true
                    if !isDir && !isLink { continue }
                    if values.isHidden == true && !(isAppName && isLink) { continue }
                }
                work.append(.visit(child, depth: childDepth, isRoot: false, prefetched: values))
                continue
            }
            if policy.needsConsent(lexical) {
                result.issues.append(.init(kind: .needsConsent, url: lexical, message: "Folder access needs a user action."))
                continue
            }
            guard let url = LaunchaPathPolicy.realURL(lexical) else {
                let fallback = lexical.standardizedFileURL
                if isRoot {
                    watchedDirs[fallback.path] = nil
                } else {
                    let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    result.issues.append(.access(error, at: fallback))
                }
                continue
            }
            if policy.needsConsent(url) {
                result.issues.append(.init(kind: .needsConsent, url: url, message: "Folder access needs a user action."))
                continue
            }
            do {
                let lexicalValues: URLResourceValues? = prefetched
                // Safari's public .app symlink has the hidden flag. Only admit hidden
                // entries when they link directly to an application bundle.
                if !isRoot {
                    let hidden: Bool?
                    if let cached = lexicalValues?.isHidden { hidden = cached }
                    else { hidden = try lexical.resourceValues(forKeys: [.isHiddenKey]).isHidden }
                    if hidden == true {
                        let isLink: Bool?
                        if let cached = lexicalValues?.isSymbolicLink { isLink = cached }
                        else { isLink = try lexical.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink }
                        guard lexical.pathExtension.lowercased() == "app", url.pathExtension.lowercased() == "app",
                              isLink == true else { continue }
                    }
                }
                guard visited.insert(url.path).inserted else { continue }
                let isApp = url.pathExtension.lowercased() == "app"
                let targetValues: URLResourceValues
                if let lexicalValues, lexicalValues.isSymbolicLink != true, url.path == lexical.path {
                    targetValues = lexicalValues
                } else {
                    targetValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isHiddenKey])
                }
                guard targetValues.isDirectory == true, targetValues.isHidden != true else { continue }
                if isApp {
                    let indexed = loadApp(at: url, nextCache: &nextBundleCache)
                    if isRoot { watchedDirs[url.path] = FileStamp.read(path: url.path) }
                    if ids.insert(indexed.candidate.id).inserted { result.apps.append(indexed) }
                    continue
                }
                guard depth < maxDepth, !Task.isCancelled else { continue }
                let ext = url.pathExtension.lowercased()
                if Self.packageExtensions.contains(ext) { continue }
                let isPackage = try url.resourceValues(forKeys: [.isPackageKey]).isPackage
                guard isPackage != true, !Task.isCancelled else { continue }
                watchedDirs[url.path] = FileStamp.read(path: url.path)
                if let children = fm.enumerator(at: url, includingPropertiesForKeys: prefetchKeys,
                                                options: [.skipsSubdirectoryDescendants],
                                                errorHandler: { failedURL, error in
                                                    result.issues.append(.access(error, at: failedURL))
                                                    return !Task.isCancelled
                                                }) {
                    work.append(.children(children, depth: depth + 1))
                }
            } catch {
                // Optional roots may not exist yet. Other failures must reach the caller.
                let ns = error as NSError
                if !(isRoot && ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError) {
                    result.issues.append(.access(error, at: url))
                } else if isRoot {
                    watchedDirs[url.path] = nil
                }
            }
        }
        if !Task.isCancelled {
            cached = result
            lastRefresh = Date()
            scannedDirs = watchedDirs
            bundleCache = nextBundleCache
        }
        return result
    }

    private func directoriesUnchanged() -> Bool {
        guard !scannedDirs.isEmpty else { return false }
        for (path, stamp) in scannedDirs {
            if FileStamp.read(path: path) != stamp { return false }
        }
        return true
    }

    private func loadApp(at url: URL, nextCache: inout [String: (stamp: AppStamp, app: IndexedLaunchaApp)]) -> IndexedLaunchaApp {
        let path = url.path
        let stamp = AppStamp(bundle: FileStamp.read(path: path),
                             infoPlist: FileStamp.read(path: path + "/Contents/Info.plist"))
        if let hit = bundleCache[path], hit.stamp == stamp {
            nextCache[path] = hit
            return hit.app
        }
        let bundle = Bundle(url: url)
        let localized = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
            .map { ($0 as NSString).deletingPathExtension }
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? localized
            ?? url.deletingPathExtension().lastPathComponent
        var candidate: LaunchaCandidate
        if let id = bundle?.bundleIdentifier, !id.isEmpty { candidate = .app(bundleID: id, name: name) }
        else { candidate = LaunchaCandidate(id: "app-path:" + path, name: name, target: .url(url.absoluteString)) }
        let bundleName = url.deletingPathExtension().lastPathComponent
        if bundleName != name { candidate.searchNames.append(bundleName) }
        let app = IndexedLaunchaApp(candidate: candidate, url: url)
        nextCache[path] = (stamp, app)
        return app
    }

    func search(_ query: String, history: LaunchHistory, now: Date = Date()) -> [LaunchaMatch] {
        LaunchaSearch.results(for: query, in: cached.apps.map(\.candidate), history: history, now: now)
    }
}

/// NSCache bounds icon memory. Loading runs on a private queue, not on the UI thread.
final class LaunchaIconCache: @unchecked Sendable {
    private let cache = NSCache<NSURL, NSImage>()
    private let queue = DispatchQueue(label: "io.bobuk.ting.launcha-icons", qos: .userInitiated)
    init() { cache.countLimit = 256 }
    func icon(for url: URL) async -> NSImage {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let image = cache.object(forKey: url as NSURL) { continuation.resume(returning: image); return }
                let image = NSWorkspace.shared.icon(forFile: url.path)
                cache.setObject(image, forKey: url as NSURL)
                continuation.resume(returning: image)
            }
        }
    }
    func invalidate() { cache.removeAllObjects() }
}
