// Whether the user has read the warning shown on the first click on a link of a micro-app result.
// Kept apart from the config file, so a shared or synced config never skips the warning.
import Foundation

@MainActor
final class MicroAppLinkNoticeStore {
    private struct Stored: Codable {
        var seen: Bool
    }

    let url: URL
    private(set) var seen = false
    /// Why the choice could not be read or saved.
    private(set) var error: String?

    init(url: URL = MicroAppLinkNoticeStore.defaultURL()) {
        self.url = url
        load()
    }

    /// With `$TING_CONFIG` the file sits next to that file, so manual checks never read or change
    /// the real one. Otherwise `~/Library/Application Support/Ting/micro-link-notice.json`.
    nonisolated static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let config = environment["TING_CONFIG"], !config.isEmpty {
            return URL(fileURLWithPath: (config as NSString).expandingTildeInPath).appendingPathExtension("micro-link-notice.json")
        }
        return home.appendingPathComponent("Library/Application Support/Ting/micro-link-notice.json")
    }

    private func load() {
        do {
            seen = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: url)).seen
        } catch {
            // No file is the normal first state. Anything else fails closed: the warning shows again.
            let ns = error as NSError
            if !(ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError) {
                self.error = "Cannot read the link warning choice: \(error.localizedDescription)"
            }
            seen = false
        }
    }

    /// Remembers that the warning was read. `seen` changes only when the file was written.
    @discardableResult
    func markSeen() -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Stored(seen: true)).write(to: url, options: .atomic)
            seen = true
            self.error = nil
            return true
        } catch {
            self.error = "Cannot save the link warning choice: \(error.localizedDescription)"
            return false
        }
    }
}
