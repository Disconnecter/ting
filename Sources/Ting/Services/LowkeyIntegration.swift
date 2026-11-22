import AppKit
import Darwin
import Observation
import TingCore

/// Read-only discovery. Only the saved-site metadata in config.json is read.
@MainActor @Observable final class LowkeyIntegration {
    static let bundleID = "io.bobuk.lowkey"
    private(set) var isInstalled = false
    private(set) var sites: [LowkeySite] = []
    private(set) var problem: String?
    @ObservationIgnored private let locate: () -> URL?
    @ObservationIgnored private let read: () throws -> Data
    @ObservationIgnored private let usesDefaultDisk: Bool
    @ObservationIgnored private var cachedAppURL: URL?
    @ObservationIgnored private var lastNotInstalledCheck: Date?
    @ObservationIgnored private var cachedConfigStamp: ConfigStamp?

    private struct ConfigStamp: Equatable {
        var inode: UInt64
        var size: Int64
        var mtimeSec: Int
        var mtimeNsec: Int

        static func read(path: String) -> ConfigStamp? {
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            return ConfigStamp(inode: info.st_ino, size: info.st_size,
                               mtimeSec: info.st_mtimespec.tv_sec, mtimeNsec: info.st_mtimespec.tv_nsec)
        }
    }

    private static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/lowkey/config.json")
    }

    init(locate: (() -> URL?)? = nil, read: (() throws -> Data)? = nil) {
        self.usesDefaultDisk = (locate == nil && read == nil)
        self.locate = locate ?? { LowkeyIntegration.applicationURL() }
        self.read = read ?? {
            let url = Self.defaultConfigURL
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= LowkeySite.maximumConfigSize else { throw LowkeySite.ReadError.tooLarge }
            return try Data(contentsOf: url)
        }
    }

    func refresh() {
        if usesDefaultDisk {
            refreshFromDisk()
            return
        }
        isInstalled = locate() != nil
        guard isInstalled else { sites = []; problem = nil; return }
        decodeConfig()
    }

    private func refreshFromDisk() {
        let installed: Bool
        if let cached = cachedAppURL,
           FileManager.default.isExecutableFile(atPath: cached.appendingPathComponent("Contents/MacOS/Lowkey").path) {
            installed = true
        } else if let last = lastNotInstalledCheck, Date().timeIntervalSince(last) < 10 {
            installed = false
        } else {
            cachedAppURL = Self.applicationURL()
            installed = cachedAppURL != nil
            lastNotInstalledCheck = installed ? nil : Date()
        }
        if isInstalled != installed { isInstalled = installed }
        guard installed else {
            cachedConfigStamp = nil
            if !sites.isEmpty { sites = [] }
            if problem != nil { problem = nil }
            return
        }
        let stamp = ConfigStamp.read(path: Self.defaultConfigURL.path)
        if let cachedConfigStamp, cachedConfigStamp == stamp { return }
        cachedConfigStamp = stamp
        decodeConfig()
    }

    private func decodeConfig() {
        do {
            let decoded = try LowkeySite.decode(read())
            if sites != decoded { sites = decoded }
            if problem != nil { problem = nil }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            if !sites.isEmpty { sites = [] }
            if problem != nil { problem = nil }
        } catch {
            // Do not retain deleted aliases or echo private settings into a toast/log.
            if !sites.isEmpty { sites = [] }
            problem = "Cannot read lowkey’s saved sites. Check its config.json."
        }
    }

    static func applicationURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let standard = [URL(fileURLWithPath: "/Applications/lowkey.app"),
                        home.appendingPathComponent("Applications/lowkey.app"),
                        URL(fileURLWithPath: "/Applications/Lowkey.app"),
                        home.appendingPathComponent("Applications/Lowkey.app")]
        if let found = standard.first(where: isValidLowkeyBundle) { return found }
        if let launched = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           isValidLowkeyBundle(launched) { return launched }
        return nil
    }

    private static func isValidLowkeyBundle(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/Lowkey").path)
            && Bundle(url: url)?.bundleIdentifier == bundleID
    }
}
