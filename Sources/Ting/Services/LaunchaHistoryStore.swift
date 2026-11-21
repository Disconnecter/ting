import Foundation
import TingCore

/// All disk IO and mutations run on this actor, never the main actor.
actor LaunchaHistoryStore {
    struct Snapshot: Sendable {
        var history: LaunchHistory
        var issues: [LaunchaServiceIssue]
        var preservedOriginal: URL?
    }
    let url: URL
    private var snapshot: Snapshot?
    private var mayWrite = true
    /// After `clear()` no use is recorded until `reopen()`: a late record never recreates the file.
    private var closed = false

    init(url: URL = LaunchaHistoryStore.defaultURL()) { self.url = url }

    nonisolated static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                      home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        AppPaths.ting(environment: environment, home: home).dataFile("launcha-history.json")
    }

    /// Apps brought to the front outside launcha, kept only while the option is on.
    nonisolated static func usageURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                    home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        AppPaths.ting(environment: environment, home: home).dataFile("app-usage.json")
    }

    func load() -> Snapshot {
        if let snapshot { return snapshot }
        var result = Snapshot(history: LaunchHistory(), issues: [], preservedOriginal: nil)
        do {
            let data = try Data(contentsOf: url)
            do { result.history = try LaunchHistory.decode(data) }
            catch {
                result.issues.append(.access(error, at: url))
                let backup = url.appendingPathExtension("corrupt-" + UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: url, to: backup)
                    result.preservedOriginal = backup
                } catch {
                    mayWrite = false
                    result.issues.append(.access(error, at: url))
                }
            }
        } catch {
            let ns = error as NSError
            if ns.domain != NSCocoaErrorDomain || ns.code != NSFileReadNoSuchFileError {
                result.issues.append(.access(error, at: url))
                mayWrite = false
            }
        }
        snapshot = result
        return result
    }

    /// Only successful opens/activations count. No system observation or launch wiring.
    @discardableResult
    func record(_ outcome: LaunchOutcome, id: String, at time: Date = Date()) -> Snapshot {
        var result = load()
        guard result.history.record(outcome, id: id, at: time) else { return result }
        return save(result)
    }

    /// An app came to the front outside launcha; at most once per app per 30 minutes.
    @discardableResult
    func recordUse(id: String, at time: Date = Date()) -> Snapshot {
        var result = load()
        guard !closed, result.history.recordUse(id: id, at: time) else { return result }
        return save(result)
    }

    /// Forgets the history and deletes its file.
    @discardableResult
    func clear() -> Snapshot {
        var result = Snapshot(history: LaunchHistory(), issues: [], preservedOriginal: nil)
        do { try FileManager.default.removeItem(at: url) } catch {
            let ns = error as NSError
            if ns.domain != NSCocoaErrorDomain || ns.code != NSFileNoSuchFileError { result.issues.append(.access(error, at: url)) }
        }
        mayWrite = true
        closed = true
        snapshot = result
        return result
    }

    /// Records use again after `clear()`.
    func reopen() { closed = false }

    private func save(_ result: Snapshot) -> Snapshot {
        var result = result
        if mayWrite {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try result.history.encoded().write(to: url, options: .atomic)
            } catch { result.issues.append(.access(error, at: url)) }
        }
        snapshot = result
        return result
    }
}
