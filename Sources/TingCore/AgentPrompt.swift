import Foundation

/// The agent prompt: a ready English text for a coding agent (Claude Code, Codex, pi, …) that
/// says how to write one micro-app. The person adds their own task after its last line.
///
/// Pure logic: the menu item, the Settings button and `Ting --agent-prompt` all give these values
/// and get the same text.
public enum AgentPrompt {
    public static let option = "--agent-prompt"
    public static let toast = "Agent prompt copied"

    /// `arguments` are the process arguments without the program name. True when they ask for the prompt.
    public static func handles(_ arguments: [String]) -> Bool {
        arguments.first == option
    }

    /// The raw GitHub file of the format document at the tag of `version`, e.g.
    /// `https://raw.githubusercontent.com/bobuk-io/ting/v0.4.0/docs/micro-apps/FORMAT.md`.
    /// A run without a bundle passes `TingVersion.marketing`, the version of its source tree.
    public static func formatLink(version: String) -> String {
        "https://raw.githubusercontent.com/bobuk-io/ting/v\(version)/docs/micro-apps/FORMAT.md"
    }

    /// The text of the prompt.
    /// - Parameters:
    ///   - formatDocument: the absolute path of FORMAT.md inside Ting.app, or nil when it is not there.
    ///   - link: the fallback link of the format document, see `formatLink(version:)`.
    ///   - microAppsFolder: the absolute path of the micro-apps folder.
    ///   - executable: the absolute path of the Ting executable.
    public static func text(formatDocument: String?, link: String, microAppsFolder: String, executable: String) -> String {
        let read: String
        if let formatDocument {
            read = "1. Read the Ting micro-app format document at `\(formatDocument)`. If that file cannot be read, use \(link) instead."
        } else {
            read = "1. Read the Ting micro-app format document at \(link)."
        }
        let folder = shellQuoted(microAppsFolder)
        return [
            "Write a Ting micro-app for me. Ting is a leader-key launcher for macOS; a micro-app is one YAML file that Ting runs as a small tool.",
            "",
            read,
            "2. Write the micro-app as one file named `<id>.yaml`, where `<id>` is its kebab-case id, in a temporary folder (not in the micro-apps folder).",
            "3. Check it with `\(shellQuoted(executable)) --check <file>` and fix the file until the check reports no problem (`<file>: ok`, exit code 0).",
            "4. Move the good file into the micro-apps folder `\(microAppsFolder)`, for example `mkdir -p \(folder) && mv <file> \(folder)/`.",
            "5. Do not change config.json or any other Ting file. I approve the micro-app at its first start and bind a key to it myself.",
            "",
            "The micro-app I want: ",
        ].joined(separator: "\n")
    }

    /// A path for the shell, in single quotes; a single quote inside becomes `'\''`.
    public static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
