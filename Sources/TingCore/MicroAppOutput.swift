import Foundation

// The output styles of the result panel as a neutral model: the Ting target only draws it.
// `console` text becomes styled runs (ANSI colour and style codes); `markdown` text becomes blocks.

// MARK: - Console (ANSI)

/// A terminal colour from an ANSI SGR code. The Ting target maps it to the Theme colours.
public enum ConsoleColor: Equatable, Sendable {
    /// One of the 16 basic colours: 0–7 normal (black, red, green, yellow, blue, magenta, cyan, white), 8–15 bright.
    case basic(Int)
    /// A colour of the 256-colour palette above the basic 16: 16–231 the 6×6×6 cube, 232–255 the grey ramp.
    case palette(Int)
    case rgb(UInt8, UInt8, UInt8)
}

public struct ConsoleStyle: Equatable, Sendable {
    public var foreground: ConsoleColor?
    public var background: ConsoleColor?
    public var bold = false
    public var dim = false
    public var italic = false
    public var underline = false
    public var inverse = false
    public var strikethrough = false

    public init(foreground: ConsoleColor? = nil, background: ConsoleColor? = nil, bold: Bool = false, dim: Bool = false,
                italic: Bool = false, underline: Bool = false, inverse: Bool = false, strikethrough: Bool = false) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.inverse = inverse
        self.strikethrough = strikethrough
    }

    public static let plain = ConsoleStyle()
}

/// A piece of console text in one style.
public struct ConsoleRun: Equatable, Sendable {
    public var text: String
    public var style: ConsoleStyle

    public init(_ text: String, _ style: ConsoleStyle = .plain) {
        self.text = text
        self.style = style
    }
}

public enum ConsoleText {
    private static let escape: Unicode.Scalar = "\u{1B}"
    private static let bell: Unicode.Scalar = "\u{07}"

    /// The text without any escape or control code (only line breaks and tabs stay):
    /// what Enter, ⌘C and the clipboard target get.
    public static func plain(_ text: String) -> String {
        parse(text).map(\.text).joined()
    }

    /// Splits `text` into styled runs. SGR codes (`ESC[…m`) set the colour and style; every other
    /// escape sequence (cursor moves, erase, OSC titles and links, charset switches) and every other
    /// control character is dropped. Adjacent runs of one style are merged; empty runs are left out.
    public static func parse(_ text: String) -> [ConsoleRun] {
        var runs: [ConsoleRun] = []
        var style = ConsoleStyle.plain
        var current = String.UnicodeScalarView()
        func flush() {
            guard !current.isEmpty else { return }
            let piece = String(current)
            current = String.UnicodeScalarView()
            if let last = runs.last, last.style == style {
                runs[runs.count - 1].text += piece
            } else {
                runs.append(ConsoleRun(piece, style))
            }
        }

        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if scalar == escape || scalar.value == 0x9B {
                // 0x9B is the one-byte CSI.
                var j = i + 1
                let isCSI: Bool
                if scalar.value == 0x9B {
                    isCSI = true
                } else if j < scalars.count, scalars[j] == "[" {
                    isCSI = true
                    j += 1
                } else {
                    isCSI = false
                }
                if isCSI {
                    // Parameter bytes 0x30–0x3F, intermediate bytes 0x20–0x2F, one final byte 0x40–0x7E.
                    let start = j
                    while j < scalars.count, (0x30...0x3F).contains(scalars[j].value) { j += 1 }
                    let parameters = String(String.UnicodeScalarView(scalars[start..<j]))
                    while j < scalars.count, (0x20...0x2F).contains(scalars[j].value) { j += 1 }
                    if j < scalars.count, (0x40...0x7E).contains(scalars[j].value) {
                        if scalars[j] == "m" {
                            flush()
                            applySGR(parameters, to: &style)
                        }
                        j += 1
                    }
                    i = j
                    continue
                }
                guard j < scalars.count else { i = j; continue }
                let next = scalars[j].value
                if next == 0x5D || next == 0x50 || next == 0x5F || next == 0x5E || next == 0x58 {
                    // OSC, DCS, APC, PM, SOS: a string up to BEL or ESC \.
                    j += 1
                    while j < scalars.count {
                        if scalars[j] == bell { j += 1; break }
                        if scalars[j] == escape, j + 1 < scalars.count, scalars[j + 1] == "\\" { j += 2; break }
                        j += 1
                    }
                    i = j
                    continue
                }
                // ESC, intermediate bytes, one final byte (such as `ESC ( B` or `ESC 7`).
                while j < scalars.count, (0x20...0x2F).contains(scalars[j].value) { j += 1 }
                if j < scalars.count { j += 1 }
                i = j
                continue
            }
            if scalar == "\n" || scalar == "\t" {
                current.append(scalar)
            } else if scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value) {
                // Other control characters (carriage return, backspace, bell) are dropped.
            } else {
                current.append(scalar)
            }
            i += 1
        }
        flush()
        return runs
    }

    private static func applySGR(_ parameters: String, to style: inout ConsoleStyle) {
        // A private sequence (`ESC[?…m`, `ESC[>…m`) is not a style.
        if let first = parameters.unicodeScalars.first, (0x3C...0x3F).contains(first.value) { return }
        let codes = parameters.split(separator: ";", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ":", omittingEmptySubsequences: false) }
            .map { Int($0) ?? 0 }
        var k = 0
        func extended() -> ConsoleColor? {
            guard k + 1 < codes.count else { k = codes.count; return nil }
            switch codes[k + 1] {
            case 5:
                guard k + 2 < codes.count else { k = codes.count; return nil }
                let n = codes[k + 2]
                k += 2
                guard (0...255).contains(n) else { return nil }
                return n < 16 ? .basic(n) : .palette(n)
            case 2:
                guard k + 4 < codes.count else { k = codes.count; return nil }
                let parts = codes[(k + 2)...(k + 4)].map { UInt8(clamping: $0) }
                k += 4
                return .rgb(parts[0], parts[1], parts[2])
            default:
                k += 1
                return nil
            }
        }
        while k < codes.count {
            let code = codes[k]
            switch code {
            case 0: style = .plain
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 9: style.strikethrough = true
            case 21: style.underline = true
            case 22: style.bold = false; style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 29: style.strikethrough = false
            case 30...37: style.foreground = .basic(code - 30)
            case 38: if let color = extended() { style.foreground = color }
            case 39: style.foreground = nil
            case 40...47: style.background = .basic(code - 40)
            case 48: if let color = extended() { style.background = color }
            case 49: style.background = nil
            case 90...97: style.foreground = .basic(code - 90 + 8)
            case 100...107: style.background = .basic(code - 100 + 8)
            default: break
            }
            k += 1
        }
    }
}

// MARK: - Markdown

/// A piece of inline markdown text in one style.
public struct MarkdownSpan: Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var code: Bool

    public init(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.code = code
    }
}

public struct MarkdownListItem: Equatable, Sendable {
    public enum Marker: Equatable, Sendable {
        case bullet
        case number(Int)
    }

    /// 0 for a top item, 1 for an item under it, and so on.
    public var depth: Int
    public var marker: Marker
    public var spans: [MarkdownSpan]

    public init(depth: Int = 0, marker: Marker, spans: [MarkdownSpan]) {
        self.depth = depth
        self.marker = marker
        self.spans = spans
    }
}

public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable { case left, center, right }

    /// One entry per column.
    public var alignments: [Alignment]
    /// The header cells; every cell empty means a table without a shown header.
    public var header: [[MarkdownSpan]]
    /// Every row has exactly one cell per column.
    public var rows: [[[MarkdownSpan]]]

    public init(alignments: [Alignment], header: [[MarkdownSpan]], rows: [[[MarkdownSpan]]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }

    public var hasHeader: Bool {
        header.contains { cell in cell.contains { !$0.text.isEmpty } }
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, spans: [MarkdownSpan])
    /// The line breaks inside a paragraph stay: command output is line based.
    case paragraph([MarkdownSpan])
    case list([MarkdownListItem])
    case code(language: String, text: String)
    case quote([MarkdownSpan])
    case table(MarkdownTable)
    case rule
}

/// A small markdown reader for the result panel: ATX and setext headings, paragraphs, bullet and
/// numbered lists (nested by indent), fenced code blocks, block quotes, rules, GitHub tables, and inline
/// bold, italic, bold italic, code and backslash escapes. Everything else stays literal text.
public enum MarkdownText {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var items: [MarkdownListItem] = []
        var quote: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraph.joined(separator: "\n"))))
            paragraph = []
        }
        func flushList() {
            guard !items.isEmpty else { return }
            blocks.append(.list(items))
            items = []
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(inline(quote.joined(separator: "\n"))))
            quote = []
        }
        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushAll()
                i += 1
                continue
            }
            if let fence = fence(trimmed) {
                flushAll()
                var body: [String] = []
                let indent = leadingSpaces(line)
                i += 1
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(String(repeating: fence.char, count: fence.count)),
                       candidate.allSatisfy({ $0 == fence.char }) { i += 1; break }
                    body.append(String(lines[i].dropFirst(min(indent, leadingSpaces(lines[i])))))
                    i += 1
                }
                blocks.append(.code(language: fence.info, text: body.joined(separator: "\n")))
                continue
            }
            if let heading = atxHeading(trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.level, spans: inline(heading.text)))
                i += 1
                continue
            }
            // A setext underline turns the paragraph above into a heading.
            if !paragraph.isEmpty, quote.isEmpty, items.isEmpty,
               let level = setextLevel(trimmed) {
                let title = paragraph.joined(separator: "\n")
                paragraph = []
                blocks.append(.heading(level: level, spans: inline(title)))
                i += 1
                continue
            }
            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                i += 1
                continue
            }
            if i + 1 < lines.count, trimmed.contains("|"),
               let alignments = delimiterRow(lines[i + 1]),
               splitRow(trimmed).count == alignments.count {
                flushAll()
                let columns = alignments.count
                let header = splitRow(trimmed).map(inline)
                var rows: [[[MarkdownSpan]]] = []
                i += 2
                while i < lines.count {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !row.isEmpty, row.contains("|") else { break }
                    var cells = splitRow(row).map(inline)
                    if cells.count > columns { cells = Array(cells.prefix(columns)) }
                    while cells.count < columns { cells.append([]) }
                    rows.append(cells)
                    i += 1
                }
                blocks.append(.table(MarkdownTable(alignments: alignments, header: header, rows: rows)))
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                var body = trimmed.dropFirst()
                if body.first == " " { body = body.dropFirst() }
                quote.append(String(body))
                i += 1
                continue
            }
            if let item = listItem(line) {
                flushParagraph()
                flushQuote()
                items.append(item)
                i += 1
                continue
            }
            if !items.isEmpty, leadingSpaces(line) >= 2 {
                // An indented line under a list item continues it.
                let last = items.count - 1
                items[last].spans += [MarkdownSpan("\n")] + inline(trimmed)
                i += 1
                continue
            }
            if !quote.isEmpty {
                quote.append(trimmed)
                i += 1
                continue
            }
            flushList()
            paragraph.append(trimmed)
            i += 1
        }
        flushAll()
        return blocks
    }

    // MARK: Blocks

    private static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for char in line {
            if char == " " { count += 1 } else if char == "\t" { count += 4 } else { break }
        }
        return count
    }

    private static func fence(_ trimmed: String) -> (char: Character, count: Int, info: String)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        let info = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        return (first, count, info)
    }

    private static func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // A closing run of # after a space is not part of the title.
        let closing = text.reversed().prefix { $0 == "#" }.count
        if closing > 0 {
            let head = text.dropLast(closing)
            if head.isEmpty || head.last == " " { text = head.trimmingCharacters(in: .whitespaces) }
        }
        return (level, text)
    }

    private static func setextLevel(_ trimmed: String) -> Int? {
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let chars = trimmed.filter { $0 != " " && $0 != "\t" }
        guard let first = chars.first, "-*_".contains(first), chars.count >= 3 else { return false }
        return chars.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> MarkdownListItem? {
        let depth = leadingSpaces(line) / 2
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        if let first = trimmed.first, "-*+".contains(first) {
            let rest = trimmed.dropFirst()
            guard rest.first == " " || rest.first == "\t" else { return nil }
            return MarkdownListItem(depth: depth, marker: .bullet,
                                    spans: inline(rest.trimmingCharacters(in: .whitespaces)))
        }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard (1...9).contains(digits.count), let number = Int(digits) else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")" else { return nil }
        let body = rest.dropFirst()
        guard body.first == " " || body.first == "\t" else { return nil }
        return MarkdownListItem(depth: depth, marker: .number(number),
                                spans: inline(body.trimmingCharacters(in: .whitespaces)))
    }

    /// The cells of a table row: the outer pipes are dropped, `\|` is a pipe inside a cell.
    private static func splitRow(_ trimmed: String) -> [String] {
        var row = Substring(trimmed)
        if row.hasPrefix("|") { row = row.dropFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") { row = row.dropLast() }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for char in row {
            if escaped {
                cell.append(char == "|" ? "|" : "\\\(char)")
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(char)
            }
        }
        if escaped { cell.append("\\") }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func delimiterRow(_ line: String) -> [MarkdownTable.Alignment]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return nil }
        var alignments: [MarkdownTable.Alignment] = []
        for cell in splitRow(trimmed) {
            guard !cell.isEmpty else { return nil }
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            let dashes = cell.dropFirst(left ? 1 : 0).dropLast(right && cell.count > 1 ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(left && right ? .center : right ? .right : .left)
        }
        return alignments
    }

    // MARK: Inline

    /// Inline markdown: `code`, **bold**, *italic*, ***both***, the same with underscores (not inside a
    /// word), and backslash escapes. A delimiter without its closing pair stays literal.
    public static func inline(_ text: String) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        parseInline(Array(text), bold: false, italic: false, into: &spans)
        return spans
    }

    private static func append(_ text: String, bold: Bool, italic: Bool, code: Bool, to spans: inout [MarkdownSpan]) {
        guard !text.isEmpty else { return }
        if let last = spans.last, last.bold == bold, last.italic == italic, last.code == code {
            spans[spans.count - 1].text += text
        } else {
            spans.append(MarkdownSpan(text, bold: bold, italic: italic, code: code))
        }
    }

    private static func parseInline(_ chars: [Character], bold: Bool, italic: Bool, into spans: inout [MarkdownSpan]) {
        var literal = ""
        func flush() {
            append(literal, bold: bold, italic: italic, code: false, to: &spans)
            literal = ""
        }
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\\", i + 1 < chars.count, chars[i + 1].isASCII, chars[i + 1].isPunctuation || chars[i + 1].isSymbol {
                literal.append(chars[i + 1])
                i += 2
                continue
            }
            if char == "`" {
                let count = run(of: "`", in: chars, at: i)
                if let close = closingTicks(count, in: chars, from: i + count) {
                    flush()
                    var body = String(chars[(i + count)..<close])
                    if body.count >= 2, body.first == " ", body.last == " ", body.contains(where: { $0 != " " }) {
                        body = String(body.dropFirst().dropLast())
                    }
                    append(body, bold: bold, italic: italic, code: true, to: &spans)
                    i = close + count
                } else {
                    literal += String(repeating: "`", count: count)
                    i += count
                }
                continue
            }
            if char == "*" || char == "_" {
                let count = run(of: char, in: chars, at: i)
                let opener = min(count, 3)
                let before: Character? = i > 0 ? chars[i - 1] : nil
                let after: Character? = i + count < chars.count ? chars[i + count] : nil
                let opens = (after.map { !$0.isWhitespace } ?? false)
                    && (char == "*" || !(before.map(isWordChar) ?? false))
                if count <= 3, opens, let close = closingDelimiter(char, count: opener, in: chars, from: i + count) {
                    flush()
                    let inner = Array(chars[(i + count)..<close])
                    parseInline(inner, bold: bold || opener >= 2, italic: italic || opener != 2, into: &spans)
                    i = close + opener
                } else {
                    literal += String(repeating: String(char), count: count)
                    i += count
                }
                continue
            }
            literal.append(char)
            i += 1
        }
        flush()
    }

    private static func isWordChar(_ char: Character) -> Bool { char.isLetter || char.isNumber }

    private static func run(of char: Character, in chars: [Character], at index: Int) -> Int {
        var j = index
        while j < chars.count, chars[j] == char { j += 1 }
        return j - index
    }

    private static func closingTicks(_ count: Int, in chars: [Character], from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "`" {
                let length = run(of: "`", in: chars, at: j)
                if length == count { return j }
                j += length
            } else {
                j += 1
            }
        }
        return nil
    }

    /// The start of a closing run of exactly `count` delimiters, after a non-space, skipping code spans.
    private static func closingDelimiter(_ char: Character, count: Int, in chars: [Character], from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "`" {
                let ticks = run(of: "`", in: chars, at: j)
                if let close = closingTicks(ticks, in: chars, from: j + ticks) { j = close + ticks } else { j += ticks }
                continue
            }
            if chars[j] == char {
                let length = run(of: char, in: chars, at: j)
                let before = chars[j - 1]
                let after: Character? = j + length < chars.count ? chars[j + length] : nil
                if length == count, j > start, !before.isWhitespace,
                   char == "*" || !(after.map(isWordChar) ?? false) {
                    return j
                }
                j += length
                continue
            }
            j += 1
        }
        return nil
    }
}

extension MicroAppPanelContent {
    /// The text that Enter and ⌘C (with nothing selected) copy: the result without escape codes.
    /// Console text (and so every error) loses its ANSI codes; the other styles copy the output as it is.
    public var plainText: String {
        style == .console ? ConsoleText.plain(text) : text
    }
}
