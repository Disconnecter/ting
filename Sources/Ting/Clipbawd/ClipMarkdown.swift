import SwiftUI

/// Syntax coloring only: source stays visible, links/images are never loaded or rendered.
enum ClipMarkdown {
    static func highlight(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let patterns = [
            #"(?m)^ {0,3}#{1,6}\s+.*$"#,
            #"(?m)^\s*(?:>|[-+*]\s|\d+\.\s).*?$"#,
            #"`[^`\n]+`|\*\*[^*\n]+\*\*|__[^_\n]+__"#,
            #"!?\[[^\]\n]*\]\([^\)\n]*\)"#,
            #"(?s)```.*?(?:```|$)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text),
                      let start = AttributedString.Index(range.lowerBound, within: result),
                      let end = AttributedString.Index(range.upperBound, within: result) else { continue }
                result[start..<end].foregroundColor = .tingAmber
            }
        }
        return result
    }
}
