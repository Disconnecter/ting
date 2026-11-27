import Foundation

/// A person who contributed to Ting on GitHub, shown in About Ting.
public struct Contributor: Equatable, Sendable {
    /// The name on their GitHub profile.
    public var name: String
    public var login: String
    public var contributions: String

    public init(name: String, login: String, contributions: String) {
        self.name = name
        self.login = login
        self.contributions = contributions
    }

    public var profileURL: URL { URL(string: "https://github.com/\(login)")! }
}

/// The contributors in `CONTRIBUTORS.md`, in the same order; a test keeps the two in step.
public enum Contributors {
    public static let all: [Contributor] = [
        Contributor(name: "Grigory Bakunov", login: "bobuk", contributions: "Author and maintainer"),
        Contributor(name: "Pavel Alay", login: "pavel-alay",
                    contributions: "launcha files beside apps, folder access, iCloud Drive, micro-app hotkeys, AI effort"),
        Contributor(name: "Андрей", login: "lost-illusion",
                    contributions: "Clipboard history (Clipbawd), the launcha converter, links in micro-app results"),
        Contributor(name: "Serhiy Zabolotnyy", login: "Disconnecter", contributions: "Window management, My Schedule"),
        Contributor(name: "Aleksei Gurianov", login: "Guria", contributions: "Reopening windows of running apps"),
        Contributor(name: "Igor Kozlov", login: "i-kozlov", contributions: "Clipbawd image file previews"),
        Contributor(name: "Taras Martyniuk", login: "taras-mrtn", contributions: "⌘, opens Settings from the launchers"),
    ]
}
