import Foundation

/// One file of the micro-apps folder after the checks: a working micro-app or a broken file.
public struct MicroAppEntry: Equatable, Sendable {
    /// The file name, such as `dns-lookup.yaml`.
    public var file: String
    /// `nil` when the file is broken.
    public var app: MicroApp?
    /// Empty for a working micro-app; sorted by line otherwise.
    public var issues: [MicroAppIssue]
    /// `MicroAppApprovals.hash` of the file content that was checked; empty when the file could not be read.
    public var contentHash: String
    /// For a broken file: the kebab-case `id` the checker could read from it; `nil` otherwise.
    public var explicitID: String?

    public init(file: String, app: MicroApp?, issues: [MicroAppIssue], contentHash: String = "", explicitID: String? = nil) {
        self.file = file
        self.app = app
        self.issues = issues
        self.contentHash = contentHash
        self.explicitID = explicitID
    }

    /// The file name without `.yaml`: the id a binding uses when the file has no `id` key.
    public var fileID: String { (file as NSString).deletingPathExtension }

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
        build(hashed: files.map { file in
            let name = (file.name as NSString).lastPathComponent
            return (name, MicroAppChecker.check(file.text, fileName: name), MicroAppApprovals.hash(Data(file.text.utf8)))
        })
    }

    /// Like `load`, for files that are already checked (or could not be read).
    public static func build(_ checked: [(file: String, result: Result<MicroApp, MicroAppFailure>)]) -> MicroAppCatalog {
        build(hashed: checked.map { ($0.file, $0.result, "") })
    }

    /// Like `build`, with the `MicroAppApprovals.hash` of each file's content.
    public static func build(hashed checked: [(file: String, result: Result<MicroApp, MicroAppFailure>, hash: String)]) -> MicroAppCatalog {
        var owners: [String: String] = [:]
        var entries: [MicroAppEntry] = []
        for (file, result, hash) in checked.sorted(by: { $0.file < $1.file }) {
            switch result {
            case .failure(let failure):
                entries.append(MicroAppEntry(file: file, app: nil, issues: failure.issues, contentHash: hash, explicitID: failure.id))
            case .success(let app):
                if let owner = owners[app.id] {
                    let issue = MicroAppIssue(file: file, line: 1,
                                              message: "duplicate id `\(app.id)`: `\(owner)` already uses it; rename one of the files")
                    entries.append(MicroAppEntry(file: file, app: nil, issues: [issue], contentHash: hash))
                } else {
                    owners[app.id] = file
                    entries.append(MicroAppEntry(file: file, app: app, issues: [], contentHash: hash))
                }
            }
        }
        return MicroAppCatalog(entries: entries)
    }

    /// What a binding to `id` finds, in this order: the working micro-app with that id; a broken
    /// file whose kept explicit `id` is `id`; a broken file whose name without `.yaml` is `id`;
    /// else nothing. A broken file never owns an id, so a working micro-app always wins.
    public func resolve(_ id: String) -> MicroAppResolution {
        if let entry = entries.first(where: { $0.app?.id == id }), let app = entry.app { return .working(app, entry) }
        if let entry = entries.first(where: { $0.isBroken && $0.explicitID == id }) { return .broken(entry) }
        if let entry = entries.first(where: { $0.isBroken && $0.fileID == id }) { return .broken(entry) }
        return .missing
    }

    /// The name a binding shows: its label, else the micro-app's `name`, else the id.
    public func bindingName(label: String, id: String) -> String {
        if !label.isEmpty { return label }
        if case .working(let app, _) = resolve(id) { return app.shownName }
        return id
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

/// What a micro-app binding points to.
public enum MicroAppResolution: Equatable, Sendable {
    case working(MicroApp, MicroAppEntry)
    case broken(MicroAppEntry)
    case missing

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    /// Why a binding does not work, in one line; `nil` for a working micro-app.
    /// `folder` is the micro-apps folder as shown to the user.
    public func problem(id: String, folder: String) -> String? {
        switch self {
        case .working:
            return nil
        case .broken(let entry):
            guard let issue = entry.issues.first else { return "Micro-app \(entry.file) has errors" }
            let more = entry.issues.count > 1 ? " (+\(entry.issues.count - 1) more)" : ""
            return "Micro-app \(issue.file), line \(issue.line): \(issue.message)\(more)"
        case .missing:
            return "Micro-app `\(id)` not found in \(folder)"
        }
    }
}

/// One entry of the micro-app picker of the bindings editor.
public struct MicroAppChoice: Equatable, Sendable, Identifiable {
    public enum State: Equatable, Sendable {
        /// A loaded micro-app.
        case working
        /// The binding's current id, which only a broken file has.
        case broken
        /// The binding's current id, which no file has.
        case missing
    }

    public var id: String
    /// The shown name: the micro-app's `name`, else its id.
    public var name: String
    public var state: State

    public init(id: String, name: String, state: State) {
        self.id = id
        self.name = name
        self.state = state
    }

    /// `name · id`, or the id with its state when it does not work.
    public var title: String {
        switch state {
        case .working: name == id ? id : "\(name) · \(id)"
        case .broken: "\(id) (broken)"
        case .missing: "\(id) (missing)"
        }
    }
}

extension MicroAppCatalog {
    /// The picker of a micro-app binding: every working micro-app in file-name order; when
    /// `current` is not one of them (a broken file or no file), it comes first, marked, so the
    /// editor can show it and the person can pick another one. An empty `current` adds nothing.
    public func bindingChoices(current: String? = nil) -> [MicroAppChoice] {
        let working = apps.map { MicroAppChoice(id: $0.id, name: $0.shownName, state: .working) }
        guard let current, !current.isEmpty, !working.contains(where: { $0.id == current }) else { return working }
        let state: MicroAppChoice.State = if case .broken = resolve(current) { .broken } else { .missing }
        return [MicroAppChoice(id: current, name: current, state: state)] + working
    }
}
