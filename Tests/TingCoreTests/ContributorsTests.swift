import Foundation
import Testing
@testable import TingCore

@Suite struct ContributorsTests {
    /// About Ting shows `Contributors.all`; CONTRIBUTORS.md must list the same people in the same order.
    @Test func matchesContributorsFile() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CONTRIBUTORS.md")
        let text = try String(contentsOf: file, encoding: .utf8)
        let row = try Regex(#"^\| \[([^\]]+)\]\(https://github\.com/([^)/]+)\) \|"#)
        let listed = text.split(separator: "\n").compactMap { line -> String? in
            guard let match = try? row.firstMatch(in: String(line)),
                  let name = match.output[1].substring, let login = match.output[2].substring else { return nil }
            return "\(name)@\(login)"
        }
        #expect(listed == Contributors.all.map { "\($0.name)@\($0.login)" })
        #expect(Contributors.all.first?.login == "bobuk")
        #expect(Set(Contributors.all.map(\.login)).count == Contributors.all.count)
    }
}
