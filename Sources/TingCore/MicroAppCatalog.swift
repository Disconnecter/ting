import Foundation

/// One file of the micro-apps folder after the checks: a working micro-app or a broken file.
public struct MicroAppEntry: Equatable, Sendable {
    /// The file name, such as `dns-lookup.yaml`.
    public var file: String
    /// `nil` when the file is broken.
    public var app: MicroApp?
    /// Empty for a working micro-app; sorted by line otherwise.
    public var issues: [MicroAppIssue]

    public init(file: String, app: MicroApp?, issues: [MicroAppIssue]) {
        self.file = file
        self.app = app
        self.issues = issues
    }

    public var isBroken: Bool { app == nil }
}

/// All files of the micro-apps folder, checked, with the id rules applied.
public struct MicroAppCatalog: Equatable, Sendable {
    /// Sorted by file name.
    public private(set) var entries: [MicroAppEntry]

    public init(entries: [MicroAppEntry] = []) {
        self.entries = entries
    }

    /// The working micro-apps, in file-name order.
    public var apps: [MicroApp] { entries.compactMap(\.app) }
    /// Every problem, by file name, then by line.
    public var issues: [MicroAppIssue] { entries.flatMap(\.issues) }
    public var brokenFiles: [String] { entries.filter(\.isBroken).map(\.file) }

    /// Checks every file and applies the id rules: when two working files have the same id, the
    /// first by file name works and the later ones are broken with a "duplicate id" issue.
    public static func load(_ files: [(name: String, text: String)]) -> MicroAppCatalog {
        build(files.map { file in
            let name = (file.name as NSString).lastPathComponent
            return (name, MicroAppChecker.check(file.text, fileName: name))
        })
    }

    /// Like `load`, for files that are already checked (or could not be read).
    public static func build(_ checked: [(file: String, result: Result<MicroApp, MicroAppFailure>)]) -> MicroAppCatalog {
        var owners: [String: String] = [:]
        var entries: [MicroAppEntry] = []
        for (file, result) in checked.sorted(by: { $0.file < $1.file }) {
            switch result {
            case .failure(let failure):
                entries.append(MicroAppEntry(file: file, app: nil, issues: failure.issues))
            case .success(let app):
                if let owner = owners[app.id] {
                    let issue = MicroAppIssue(file: file, line: 1,
                                              message: "duplicate id `\(app.id)`: `\(owner)` already uses it; rename one of the files")
                    entries.append(MicroAppEntry(file: file, app: nil, issues: [issue]))
                } else {
                    owners[app.id] = file
                    entries.append(MicroAppEntry(file: file, app: app, issues: []))
                }
            }
        }
        return MicroAppCatalog(entries: entries)
    }

    /// The text of `micro-errors.log`: one `file:line: message` line per problem; empty when all is good.
    public var logText: String {
        issues.map { issue in
            let message = issue.message.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            return "\(issue.file):\(issue.line): \(message)\n"
        }.joined()
    }

    /// The files that are broken now and were not broken the same way in `previous`: files that
    /// became broken, broken files that changed, and new broken files.
    public func newlyBroken(since previous: MicroAppCatalog) -> [MicroAppEntry] {
        let before = Dictionary(previous.entries.map { ($0.file, $0.issues) }, uniquingKeysWith: { first, _ in first })
        return entries.filter { $0.isBroken && before[$0.file] != $0.issues }
    }

    /// The toast for a live change that brought broken files; `nil` when it brought none.
    public func toastMessage(since previous: MicroAppCatalog) -> String? {
        let broken = newlyBroken(since: previous)
        guard let first = broken.first, let issue = first.issues.first else { return nil }
        if broken.count == 1 { return "Micro-app \(issue.file), line \(issue.line): \(issue.message)" }
        return "\(broken.count) micro-app files have errors, first \(issue.file), line \(issue.line)"
    }
}
