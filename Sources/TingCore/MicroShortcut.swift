import Foundation

/// A direct global shortcut that starts a micro-app, without the leader.
/// JSON: `{ "micro": "<micro-app id>", "hotkey": "<hotkey>" }`.
public struct MicroShortcut: Equatable, Sendable, Codable {
    /// The micro-app id, as a `micro` binding names it. An id that is not loaded shows its error at start.
    public var micro: String
    public var hotkey: Hotkey

    public init(micro: String, hotkey: Hotkey) {
        self.micro = micro
        self.hotkey = hotkey
    }

    public var hasTarget: Bool {
        !micro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
