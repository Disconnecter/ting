import BobukCore
import Foundation

/// Operating mode of the Chatta window.
public enum ChattaMode: String, Equatable, Sendable, CaseIterable, Identifiable {
    /// Text-only conversation without file access.
    case chat
    /// Workspace session opened in Ting's config folder with setup instructions injected on the first turn.
    case configure

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chat: "Chat"
        case .configure: "Configure Ting"
        }
    }
}

/// Pure rules for Chatta prompt composition and agent selection.
public enum ChattaPrompt {
    /// Builds the outgoing prompt for a Chatta window turn.
    /// In `.configure` mode, injects Ting's setup instructions on the first message of the session so
    /// the agent reads `CONFIGURING.md` / `FORMAT.md` and checks edits with `ting-micro`.
    public static func prepare(userMessage: String, mode: ChattaMode, isFirstMessage: Bool,
                               setupPrompt: () -> String) -> String {
        switch mode {
        case .chat:
            return userMessage
        case .configure:
            guard isFirstMessage else { return userMessage }
            let prefix = setupPrompt()
            if prefix.hasSuffix(" ") || prefix.hasSuffix("\n") {
                return prefix + userMessage
            }
            return prefix + "\n\n" + userMessage
        }
    }

    /// Combines an optional `system` instruction with the user prompt for a headless `chatta:` micro-app step.
    public static func composeStepPrompt(system: String?, prompt: String) -> String {
        guard let system = system?.trimmingCharacters(in: .whitespacesAndNewlines), !system.isEmpty else {
            return prompt
        }
        return system + "\n\n" + prompt
    }

    /// Picks the active ACP preset: an explicit known id if configured, otherwise the first installed
    /// agent in `installed`, otherwise `fallback`.
    public static func resolveAgent(configuredID: String?, installed: [ACPAgentPreset],
                                    fallback: ACPAgentPreset = .antigravity) -> ACPAgentPreset {
        if let id = configuredID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty,
           let preset = ACPAgentPreset.named(id) {
            return preset
        }
        return installed.first ?? fallback
    }

    /// Additional workspace roots for `.configure` mode: the micro-apps folder (important when `TING_CONFIG`
    /// places it outside the config directory) and the app resources folder holding `CONFIGURING.md` / `FORMAT.md`.
    public static func configureAdditionalRoots(configDirectory: URL, microAppsFolder: URL,
                                                resourcesDirectory: URL?) -> [URL] {
        let base = configDirectory.standardizedFileURL.path
        var roots: [URL] = []
        var seen: Set<String> = [base]
        for candidate in [microAppsFolder, resourcesDirectory].compactMap({ $0 }) {
            let path = candidate.standardizedFileURL.path
            guard path != base, !path.hasPrefix(base + "/"), seen.insert(path).inserted else { continue }
            roots.append(candidate)
        }
        return roots
    }
}
