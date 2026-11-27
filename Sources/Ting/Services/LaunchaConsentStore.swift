// The user's choices to let launcha search Desktop, Documents and Downloads, and iCloud Drive.
// Kept apart from the config file, so a shared or synced config never grants it.
import Foundation
import TingCore

@MainActor
final class LaunchaConsentStore {
    private struct Stored: Codable {
        var protectedFolders: Bool
        /// Missing in files from before the iCloud Drive choice: off.
        var iCloudDrive: Bool?
    }

    let url: URL
    private(set) var policy: ProtectedFolderPolicy
    /// A separate opt-in, off by default: allowing the protected folders does not include it.
    private(set) var iCloudDrive = false
    /// Why the choice could not be read or saved.
    private(set) var error: String?

    init(url: URL = LaunchaConsentStore.defaultURL()) {
        self.url = url
        policy = .needsConsent
        load()
    }

    /// With `$TING_CONFIG` the choice sits next to that file, so manual checks never read or
    /// change the real one. Otherwise `~/Library/Application Support/Ting/launcha-consent.json`.
    nonisolated static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        AppPaths.ting(environment: environment, home: home).dataFile("launcha-consent.json")
    }

    private func load() {
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: url))
            policy = stored.protectedFolders ? .allowed : .needsConsent
            iCloudDrive = stored.iCloudDrive ?? false
        } catch {
            // No file is the normal first state. Anything else fails closed.
            let ns = error as NSError
            if !(ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError) {
                self.error = "Cannot read the launcha folder choice: \(error.localizedDescription)"
            }
            policy = .needsConsent
            iCloudDrive = false
        }
    }

    /// Saves the choice. The policy changes only when the file was written.
    @discardableResult
    func set(_ policy: ProtectedFolderPolicy) -> Bool {
        save(policy: policy, iCloudDrive: iCloudDrive)
    }

    /// Saves the iCloud Drive choice. It changes only when the file was written.
    @discardableResult
    func setICloudDrive(_ allowed: Bool) -> Bool {
        save(policy: policy, iCloudDrive: allowed)
    }

    private func save(policy: ProtectedFolderPolicy, iCloudDrive: Bool) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Stored(protectedFolders: policy == .allowed, iCloudDrive: iCloudDrive)).write(to: url, options: .atomic)
            self.policy = policy
            self.iCloudDrive = iCloudDrive
            error = nil
            return true
        } catch {
            self.error = "Cannot save the launcha folder choice: \(error.localizedDescription)"
            return false
        }
    }
}
