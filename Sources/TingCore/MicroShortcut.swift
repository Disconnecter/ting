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

/// The Settings editor: one hotkey per micro-app.
public enum MicroShortcutRules {
    /// Why `hotkey` cannot start `micro`: invalid, reserved, or held by a window command, an app or another micro-app.
    public static func problem(for hotkey: Hotkey, micro: String, in config: Config) -> String? {
        if !hotkey.isValid { return AppShortcutRules.Problem.invalidKey.description }
        if let owner = LauncherHotkey.owner(of: hotkey, in: config) { return owner.conflict(for: hotkey) }
        if let other = config.microHotkeys.first(where: { $0.hotkey == hotkey && $0.micro != micro }) {
            return "\(hotkey.display) already starts \(other.micro)."
        }
        if let window = config.windowManagement.shortcuts.first(where: { $0.hotkey == hotkey }) {
            return "\(hotkey.display) already runs \(window.command.title)."
        }
        if let app = config.appHotkeys.first(where: { $0.hotkey == hotkey }) {
            return "\(hotkey.display) already opens \(app.name)."
        }
        return nil
    }

    /// Sets the one hotkey of `micro`, in place of its first entry; nil removes every entry of `micro`.
    public static func assign(_ hotkey: Hotkey?, to micro: String, in config: inout Config) {
        let index = config.microHotkeys.firstIndex { $0.micro == micro }
        config.microHotkeys.removeAll { $0.micro == micro }
        guard let hotkey else { return }
        config.microHotkeys.insert(MicroShortcut(micro: micro, hotkey: hotkey), at: min(index ?? .max, config.microHotkeys.count))
    }
}
