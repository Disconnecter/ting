// The Credits of About Ting: the contributors from CONTRIBUTORS.md, each linked to GitHub.
import AppKit
import TingCore

enum AboutCredits {
    static func text(_ contributors: [Contributor] = Contributors.all) -> NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = 4
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let text = NSMutableAttributedString(string: "Contributors\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centered,
        ])
        for (index, person) in contributors.enumerated() {
            text.append(NSAttributedString(string: person.name, attributes: [
                .font: body, .link: person.profileURL, .paragraphStyle: centered,
            ]))
            text.append(NSAttributedString(string: " — \(person.contributions)", attributes: [
                .font: body, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centered,
            ]))
            if index < contributors.count - 1 {
                text.append(NSAttributedString(string: "\n", attributes: [.font: body, .paragraphStyle: centered]))
            }
        }
        return text
    }
}
