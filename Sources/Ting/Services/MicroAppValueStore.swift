// The remembered values of the parameter panel: by micro-app id, the values of the last started run,
// as plain text. Kept apart from the micro-apps folder and the config file.
import Foundation
import TingCore

@MainActor
final class MicroAppValueStore {
    let url: URL
    private(set) var remembered = MicroAppRememberedValues()

    init(url: URL = MicroAppValueStore.defaultURL()) {
        self.url = url
        load()
    }

    /// With `$TING_CONFIG` the file sits next to that file with its name in front
    /// (`/tmp/ting-test.json.micro-values.json`). Otherwise
    /// `~/Library/Application Support/Ting/micro-values.json`.
    nonisolated static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let config = environment["TING_CONFIG"], !config.isEmpty {
            return URL(fileURLWithPath: (config as NSString).expandingTildeInPath).appendingPathExtension("micro-values.json")
        }
        return home.appendingPathComponent("Library/Application Support/Ting/micro-values.json")
    }

    /// Reads the file again. A missing or unreadable file gives no values.
    func load() {
        remembered = (try? Data(contentsOf: url)).map(MicroAppRememberedValues.decode) ?? MicroAppRememberedValues()
    }

    /// Saves the shown values of `app` when its run starts. `remember: false` keeps nothing (and
    /// drops what an earlier version of the file left). Throws when the file cannot be written.
    func remember(_ values: [String: String], for app: MicroApp) throws {
        let before = remembered
        remembered.remember(values, for: app)
        guard remembered != before else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try remembered.encoded().write(to: url, options: .atomic)
    }
}
