import BobukCore
import BobukUI
import SwiftUI

/// Syntax coloring only: source stays visible, links/images are never loaded or rendered.
@MainActor enum ClipMarkdown {
    private static let regexes: [NSRegularExpression] = [
        #"(?m)^ {0,3}#{1,6}\s+.*$"#,
        #"(?m)^\s*(?:>|[-+*]\s|\d+\.\s).*?$"#,
        #"`[^`\n]+`|\*\*[^*\n]+\*\*|__[^_\n]+__"#,
        #"!?\[[^\]\n]*\]\([^\)\n]*\)"#,
        #"(?s)```.*?(?:```|$)"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static var lastInput: (text: String, accent: RGB, output: AttributedString)?

    static func highlight(_ text: String) -> AttributedString {
        let accent = ThemeStore.ting.tokens.accent
        if let last = lastInput, last.text == text, last.accent == accent { return last.output }
        var result = AttributedString(text)
        let color = Color(accent)
        let fullRange = NSRange(text.startIndex..., in: text)
        for regex in regexes {
            for match in regex.matches(in: text, range: fullRange) {
                guard let range = Range(match.range, in: text),
                      let start = AttributedString.Index(range.lowerBound, within: result),
                      let end = AttributedString.Index(range.upperBound, within: result) else { continue }
                result[start..<end].foregroundColor = color
            }
        }
        lastInput = (text, accent, result)
        return result
    }
}
