import Foundation
import Testing
@testable import TingCore

@Suite struct AgentPromptTests {
    private let link = AgentPrompt.formatLink(version: "0.4.0")
    private let document = "/Applications/Ting.app/Contents/Resources/FORMAT.md"
    private let folder = "/Users/someone/.config/ting/micro"
    private let executable = "/Applications/Ting.app/Contents/MacOS/Ting"

    private func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    @Test func linkPointsToTheTagOfTheVersion() {
        #expect(link == "https://raw.githubusercontent.com/bobuk-io/ting/v0.4.0/docs/micro-apps/FORMAT.md")
        #expect(AgentPrompt.formatLink(version: TingVersion.marketing)
            == "https://raw.githubusercontent.com/bobuk-io/ting/v\(TingVersion.marketing)/docs/micro-apps/FORMAT.md")
    }

    /// The version of runs without a bundle is the one that `version.env` gives the packaged app.
    @Test func sourceVersionMatchesVersionEnv() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let env = try String(contentsOf: root.appendingPathComponent("version.env"), encoding: .utf8)
        let line = try #require(env.split(separator: "\n").first { $0.hasPrefix("MARKETING_VERSION=") })
        let value = line.dropFirst("MARKETING_VERSION=".count).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        #expect(TingVersion.marketing == value)
        #expect(!AgentPrompt.formatLink(version: TingVersion.marketing).contains("/main/"))
    }

    @Test func handlesOnlyTheOptionFirst() {
        #expect(AgentPrompt.handles(["--agent-prompt"]))
        #expect(!AgentPrompt.handles([]))
        #expect(!AgentPrompt.handles(["--check", "--agent-prompt"]))
    }

    @Test func withTheBundledDocumentThePartsComeInOrder() throws {
        let text = AgentPrompt.text(formatDocument: document, link: link, microAppsFolder: folder, executable: executable)
        let micro = (executable as NSString).deletingLastPathComponent + "/ting-micro"
        let parts = [
            "guide `\(AgentPrompt.guide(forFormat: document))`",
            "use \(AgentPrompt.guideLink(forFormatLink: link)) instead",
            "format document `\(document)`",
            "one file named `<id>.yaml`",
            "temporary folder",
            "`'\(micro)' check --libs '\(folder)/libs' <file>`",
            "no problem",
            "micro-apps folder `\(folder)`",
            "mv <file> '\(folder)'/",
            "Change config.json only for the bindings and settings I ask for",
            "`'\(micro)' check-config`",
            "Never put API keys into files",
        ]
        var position = text.startIndex
        for part in parts {
            let range = try #require(text.range(of: part, range: position..<text.endIndex), "\(part) out of order")
            position = range.upperBound
        }
        // The document inside the app comes before the link.
        let documentAt = try #require(text.range(of: document)).lowerBound
        let linkAt = try #require(text.range(of: link)).lowerBound
        #expect(documentAt < linkAt)
        // The last line is open for the person's task.
        #expect(lines(text).last == "My task: ")
        #expect(!text.hasSuffix("\n"))
        #expect(AgentPrompt.guideLink(forFormatLink: link) == "https://raw.githubusercontent.com/bobuk-io/ting/v0.4.0/docs/CONFIGURING.md")
    }

    @Test func withoutTheBundledDocumentOnlyTheLinkIsNamed() {
        let text = AgentPrompt.text(formatDocument: nil, link: link, microAppsFolder: folder, executable: executable)
        #expect(text.contains("format document \(link)."))
        #expect(text.contains("guide \(AgentPrompt.guideLink(forFormatLink: link)) and follow it"))
        #expect(!text.contains("FORMAT.md`"))
        #expect(!text.contains("Resources"))
        #expect(!text.contains("cannot be read"))
        #expect(text.contains("check-config"))
        #expect(lines(text).last == "My task: ")
    }

    @Test func pathsWithSpacesAreQuotedInCommands() {
        let spaced = "/Users/some one/Apps/My Ting.app/Contents/MacOS/Ting"
        let spacedFolder = "/private/tmp/ting spec.json.micro"
        let spacedDocument = "/Users/some one/Apps/My Ting.app/Contents/Resources/FORMAT.md"
        let text = AgentPrompt.text(formatDocument: spacedDocument, link: link,
                                    microAppsFolder: spacedFolder, executable: spaced)
        #expect(text.contains("`\(spacedDocument)`"))
        #expect(text.contains("`'/Users/some one/Apps/My Ting.app/Contents/MacOS/ting-micro' check --libs '\(spacedFolder)/libs' <file>`"))
        #expect(text.contains("`mkdir -p '\(spacedFolder)' && mv <file> '\(spacedFolder)'/`"))
    }

    @Test func shellQuotingKeepsSingleQuotes() {
        #expect(AgentPrompt.shellQuoted("/a b/c") == "'/a b/c'")
        #expect(AgentPrompt.shellQuoted("/it's/here") == "'/it'\\''s/here'")
    }
}
