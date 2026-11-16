import Foundation
import Testing
import TingCore

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let documentURL = root.appendingPathComponent("docs/micro-apps/FORMAT.md")
private let examplesURL = root.appendingPathComponent("docs/micro-apps/examples", isDirectory: true)

/// The text of every fenced `yaml` block of a markdown document, in order, with its final line break.
private func yamlBlocks(of markdown: String) -> [String] {
    var blocks: [String] = []
    var current: [Substring]?
    for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
        if var lines = current {
            if line == "```" {
                blocks.append(lines.map { $0 + "\n" }.joined())
                current = nil
            } else {
                lines.append(line)
                current = lines
            }
        } else if line == "```yaml" {
            current = []
        }
    }
    return blocks
}

/// A complete micro-app block: a `yaml` block whose first line, after an optional `---`, is the `format` key.
private func isCompleteMicroApp(_ block: String) -> Bool {
    var lines = block.split(separator: "\n", omittingEmptySubsequences: false)[...]
    if lines.first == "---" { lines = lines.dropFirst() }
    return lines.first?.hasPrefix("format:") == true
}

/// `docs/micro-apps/FORMAT.md` is self-contained: it holds every example file word for word,
/// and every complete micro-app in it is a good file.
@Suite struct FormatDocumentTests {
    private func document() throws -> String {
        try String(contentsOf: documentURL, encoding: .utf8)
    }

    private func examples() throws -> [(name: String, text: String)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: examplesURL.path)
            .filter { $0.hasSuffix(".yaml") }.sorted()
        return try names.map { ($0, try String(contentsOf: examplesURL.appendingPathComponent($0), encoding: .utf8)) }
    }

    @Test func holdsEveryExampleWordForWord() throws {
        let examples = try examples()
        #expect(examples.map(\.name) == ["change-case.yaml", "count-text.yaml", "dns-lookup.yaml",
                                         "encode-decode.yaml", "format-json.yaml"])
        let text = try document()
        let blocks = yamlBlocks(of: text)
        for example in examples {
            let copied = blocks.contains(example.text)
            #expect(copied, "FORMAT.md has no yaml block equal to \(example.name)")
            let named = text.contains("`\(example.name)`")
            #expect(named, "FORMAT.md does not name \(example.name)")
        }
    }

    @Test func everyCompleteMicroAppBlockPassesTheChecker() throws {
        let examples = try examples()
        let complete = yamlBlocks(of: try document()).filter(isCompleteMicroApp)
        #expect(complete.count >= examples.count + 1)
        for (index, block) in complete.enumerated() {
            // An example is checked under its own file name; another block under a neutral one.
            let fileName = examples.first { $0.text == block }?.name ?? "format-block-\(index + 1).yaml"
            let result = MicroAppChecker.check(block, fileName: fileName)
            if case .failure(let failure) = result {
                Issue.record("block \(index + 1) of FORMAT.md (\(fileName)) is not a good file: \(failure.issues)")
            }
        }
    }

    @Test func blockDetectionFindsChangesAndBrokenFiles() {
        let good = "format: ting.microapp/2\ndescription: Say hi.\ninput: none\ncommand: echo hi\noutput:\n  to: [panel]\n"
        let markdown = "# T\n\n```yaml\n\(good)```\n\n```yaml\nparams:\n  - name: x\n```\n\n   ```yaml\nindented\n   ```\n"
        let blocks = yamlBlocks(of: markdown)
        #expect(blocks == [good, "params:\n  - name: x\n"])
        #expect(blocks.filter(isCompleteMicroApp) == [good])
        // A changed copy is no longer the example, and a broken complete block fails the checker.
        #expect(!yamlBlocks(of: markdown.replacingOccurrences(of: "echo hi", with: "echo bye")).contains(good))
        let broken = good.replacingOccurrences(of: "[panel]", with: "[clip]")
        #expect(isCompleteMicroApp(broken))
        guard case .failure = MicroAppChecker.check(broken, fileName: "x.yaml") else {
            Issue.record("a broken block must fail the checker")
            return
        }
    }

    @Test func hasNoLocalPaths() throws {
        let text = try document()
        for path in ["/Users/", "/home/", "/var/folders/"] {
            #expect(!text.contains(path), "FORMAT.md contains \(path)")
        }
    }
}
