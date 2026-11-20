// Reads, writes and watches the config file (`~/.config/ting/config.json`, or `$TING_CONFIG`).
import BobukSystem
import Foundation
import TingCore

@MainActor
final class ConfigStore {
    enum LoadError: Error {
        case missing
        case unreadable(String)
        case invalid(ConfigError)

        var message: String {
            switch self {
            case .missing: "The config file is missing. Ting keeps the last good settings."
            case .unreadable(let reason): "Cannot read the config file: \(reason)"
            case .invalid(.invalidFormat(let reason)): "Config error: \(reason)"
            case .invalid(.unsupportedVersion(let version)): "Config version \(version) needs a newer Ting."
            }
        }
    }

    let url: URL
    private var watcher: FileWatcher?

    init(url: URL = ConfigStore.defaultURL()) {
        self.url = url
    }

    /// `$TING_CONFIG` when set (handy for manual checks), else `~/.config/ting/config.json`.
    nonisolated static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["TING_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ting/config.json")
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }

    var fileExists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func load() -> Result<Config, LoadError> {
        guard fileExists else { return .failure(.missing) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        do {
            return .success(try ConfigCodec.decode(data))
        } catch let error as ConfigError {
            return .failure(.invalid(error))
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    /// Atomic write; creates the directory when needed.
    func write(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConfigCodec.encode(config).write(to: url, options: .atomic)
        watchFile()
    }

    /// Watches the directory (editors often replace the file) and the file itself (in-place saves),
    /// coalescing the burst of events of one save.
    func watch(onChange: @escaping () -> Void) {
        watcher = FileWatcher(url: url, onChange: onChange)
    }

    /// The atomic write replaced the watched file: watch the new one.
    private func watchFile() {
        watcher?.fileWasReplaced()
    }
}
