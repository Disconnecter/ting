// The micro-app approvals: by id, the SHA-256 of the approved file content.
// Kept apart from the micro-apps folder and the config file, so a copied folder or a shared
// config never approves a command.
import Foundation
import TingCore

@MainActor
final class MicroAppApprovalStore {
    let url: URL
    private(set) var approvals = MicroAppApprovals()

    init(url: URL = MicroAppApprovalStore.defaultURL()) {
        self.url = url
        load()
    }

    /// With `$TING_CONFIG` the file sits next to that file with its name in front
    /// (`/tmp/ting-test.json.micro-approvals.json`). Otherwise
    /// `~/Library/Application Support/Ting/micro-approvals.json`.
    nonisolated static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        AppPaths.ting(environment: environment, home: home).dataFile("micro-approvals.json")
    }

    /// Reads the file again. A missing or unreadable file approves nothing.
    func load() {
        approvals = (try? Data(contentsOf: url)).map(MicroAppApprovals.decode) ?? MicroAppApprovals()
    }

    func isApproved(id: String, hash: String) -> Bool {
        approvals.isApproved(id: id, hash: hash)
    }

    /// Saves the approval. Throws when the file cannot be written; the approval then holds for this run only.
    func approve(id: String, hash: String) throws {
        approvals.approve(id: id, hash: hash)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try approvals.encoded().write(to: url, options: .atomic)
    }
}
