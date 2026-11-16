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
        #expect(AgentPrompt.formatLink(version: nil)
            == "https://raw.githubusercontent.com/bobuk-io/ting/main/docs/micro-apps/FORMAT.md")
    }

    @Test func handlesOnlyTheOptionFirst() {
        #expect(AgentPrompt.handles(["--agent-prompt"]))
        #expect(!AgentPrompt.handles([]))
        #expect(!AgentPrompt.handles(["--check", "--agent-prompt"]))
    }

    @Test func withTheBundledDocumentThePartsComeInOrder() throws {
        let text = AgentPrompt.text(formatDocument: document, link: link, microAppsFolder: folder, executable: executable)
        let parts = [
            "format document at `\(document)`",
            "use \(link) instead",
            "one file named `<id>.yaml`",
            "temporary folder",
            "`'\(executable)' --check <file>`",
            "no problem",
            "micro-apps folder `\(folder)`",
            "mv <file> '\(folder)'/",
            "Do not change config.json",
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
        #expect(lines(text).last == "The micro-app I want: ")
        #expect(!text.hasSuffix("\n"))
    }

    @Test func withoutTheBundledDocumentOnlyTheLinkIsNamed() {
        let text = AgentPrompt.text(formatDocument: nil, link: link, microAppsFolder: folder, executable: executable)
        #expect(text.contains("format document at \(link)."))
        #expect(!text.contains("FORMAT.md`"))
        #expect(!text.contains("Resources"))
        #expect(!text.contains("cannot be read"))
        #expect(text.contains("'\(executable)' --check <file>"))
        #expect(text.contains("Do not change config.json"))
        #expect(lines(text).last == "The micro-app I want: ")
    }

    @Test func pathsWithSpacesAreQuotedInCommands() {
        let spaced = "/Users/some one/Apps/My Ting.app/Contents/MacOS/Ting"
        let spacedFolder = "/private/tmp/ting spec.json.micro"
        let spacedDocument = "/Users/some one/Apps/My Ting.app/Contents/Resources/FORMAT.md"
        let text = AgentPrompt.text(formatDocument: spacedDocument, link: link,
                                    microAppsFolder: spacedFolder, executable: spaced)
        #expect(text.contains("`\(spacedDocument)`"))
        #expect(text.contains("`'\(spaced)' --check <file>`"))
        #expect(text.contains("`mkdir -p '\(spacedFolder)' && mv <file> '\(spacedFolder)'/`"))
    }

    @Test func shellQuotingKeepsSingleQuotes() {
        #expect(AgentPrompt.shellQuoted("/a b/c") == "'/a b/c'")
        #expect(AgentPrompt.shellQuoted("/it's/here") == "'/it'\\''s/here'")
    }
}
