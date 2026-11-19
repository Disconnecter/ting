import Foundation

/// Local, versioned binary history. Call on a serial worker queue, never the UI thread.
/// File references remain references; only image/video clipboard payloads are archived.
public struct ClipHistoryDisk: Sendable {
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("history.plist") }

    public init(directory: URL) { self.directory = directory }

    public static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let config = environment["TING_CONFIG"], !config.isEmpty {
            return URL(fileURLWithPath: (config as NSString).expandingTildeInPath).appendingPathExtension("clipbawd")
        }
        return home.appendingPathComponent("Library/Application Support/Ting/Clipbawd")
    }

    private struct Archive: Codable {
        var version: Int
        var history: Data
    }

    public func load() throws -> ClipHistory {
        guard FileManager.default.fileExists(atPath: file.path) else { return ClipHistory() }
        let archive = try PropertyListDecoder().decode(Archive.self, from: Data(contentsOf: file))
        guard archive.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return try ClipHistory.decode(archive.history)
    }

    @discardableResult
    public func save(_ history: ClipHistory) throws -> (history: ClipHistory, bytes: Int) {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var location = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try location.setResourceValues(values)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        var retained = history
        var data = try encoder.encode(Archive(version: 1, history: retained.encoded()))
        // The on-disk bound includes serialization and metadata, not just media payloads.
        while data.count > retained.byteLimit, !retained.entries.isEmpty {
            var toDrop = data.count - retained.byteLimit
            repeat {
                guard let oldest = retained.entries.reversed().min(by: { $0.lastCopied < $1.lastCopied }) else { break }
                toDrop -= max(1, oldest.byteCount)
                retained.remove(id: oldest.id)
            } while toDrop > 0 && !retained.entries.isEmpty
            data = try encoder.encode(Archive(version: 1, history: retained.encoded()))
        }
        guard data.count <= retained.byteLimit else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return (retained, data.count)
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
