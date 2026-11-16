// The real values of the agent prompt on this Mac: the format document inside Ting.app, the
// link of the running version, the micro-apps folder of the config and the Ting executable.
import AppKit
import TingCore

enum AgentPromptSource {
    /// The prompt of the running app. Reads nothing but the bundle and the environment.
    static func text(bundle: Bundle = .main,
                     environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let configURL = ConfigStore.defaultURL(environment: environment)
        let folder = MicroAppStore.folderURL(configURL: configURL, environment: environment)
        return AgentPrompt.text(formatDocument: formatDocument(bundle: bundle),
                                link: AgentPrompt.formatLink(version: version(bundle: bundle)),
                                microAppsFolder: folder.standardizedFileURL.path,
                                executable: executable(bundle: bundle))
    }

    /// `Contents/Resources/FORMAT.md` when it is there and readable; nil for `swift run` and tests.
    static func formatDocument(bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "FORMAT", withExtension: "md") else { return nil }
        let path = url.resolvingSymlinksInPath().path
        return FileManager.default.isReadableFile(atPath: path) ? path : nil
    }

    /// The marketing version of the bundle; nil without a bundle.
    static func version(bundle: Bundle) -> String? {
        guard let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.isEmpty else { return nil }
        return version
    }

    /// The absolute path of the running Ting executable.
    static func executable(bundle: Bundle) -> String {
        let url = bundle.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Puts the text on `pasteboard`. Tests pass a private pasteboard, never the person's clipboard.
    static func copy(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
