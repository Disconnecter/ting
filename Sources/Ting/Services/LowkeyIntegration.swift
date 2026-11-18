import AppKit
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

    init(locate: (() -> URL?)? = nil, read: (() throws -> Data)? = nil) {
        self.locate = locate ?? { LowkeyIntegration.applicationURL() }
        self.read = read ?? {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/lowkey/config.json")
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= LowkeySite.maximumConfigSize else { throw LowkeySite.ReadError.tooLarge }
            return try Data(contentsOf: url)
        }
    }

    func refresh() {
        isInstalled = locate() != nil
        guard isInstalled else { sites = []; problem = nil; return }
        do {
            sites = try LowkeySite.decode(read())
            problem = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            sites = []
            problem = nil
        } catch {
            // Do not retain deleted aliases or echo private settings into a toast/log.
            sites = []
            problem = "Cannot read lowkey’s saved sites. Check its config.json."
        }
    }

    static func applicationURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                          URL(fileURLWithPath: "/Applications/lowkey.app"),
                          home.appendingPathComponent("Applications/lowkey.app"),
                          URL(fileURLWithPath: "/Applications/Lowkey.app"),
                          home.appendingPathComponent("Applications/Lowkey.app")]
        return candidates.compactMap { $0 }.first {
            Bundle(url: $0)?.bundleIdentifier == bundleID
                && FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent("Contents/MacOS/Lowkey").path)
        }
    }
}
