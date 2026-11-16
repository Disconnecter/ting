// The micro-app panels in the launcha style: graphite card, amber top rule, mono footer.
// The result text is drawn by `MicroAppOutputRenderer` in the style of `output.as`.
import AppKit
import SwiftUI
import TingCore

struct MicroAppFlowView: View {
    let session: MicroAppFlowSession
    let onApprove: () -> Void
    let onCopyAll: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // A click beside the card works like Esc.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            switch session.state {
            case .closed:
                EmptyView()
            case .approval(let app, let file):
                Card(title: app.shownName, showHeader: session.showHeader, footer: ["⌘↩ approve and run", "esc cancel"]) {
                    ApprovalBody(app: app, file: file, onApprove: onApprove)
                }
                .padding(.top, 8)
            case .form:
                if let model = session.form {
                Card(title: model.app.shownName, showHeader: session.showHeader, footer: formFooter(model.form)) {
                    MicroAppFormBody(model: model, maxHeight: session.formMaxHeight)
                }
                .padding(.top, 8)
                }
            case .working(let app):
                Card(title: app.shownName, showHeader: session.showHeader, footer: ["esc stop"]) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Running \(app.shownName)…").font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
                .padding(.top, 8)
            case .result(let content):
                Card(title: content.title, showHeader: session.showHeader,
                     footer: ["↩ copy all and close", "⌘C copy", "esc close"]) {
                    ResultBody(content: content)
                }
                .padding(.top, 8)
            }
        }
    }
}

private func formFooter(_ form: MicroAppForm) -> [String] {
    if form.isSingleChoiceList { return ["↑↓ choose", "↩ run", "esc cancel"] }
    var footer = ["↩ run"]
    if form.visibleIndexes.count > 1 || form.hasOptionalToggle { footer.append("tab next") }
    if form.hasOptionalToggle { footer.append("⌘O options") }
    footer.append("esc cancel")
    return footer
}

private struct Card<Content: View>: View {
    let title: String
    let showHeader: Bool
    let footer: [String]
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if showHeader { TingMark(size: 14) }
                MonoLabel(showHeader ? "Ting  ·  \(title)" : title, size: 10, tracking: 2).foregroundStyle(Color.tingAmber)
                    .lineLimit(1)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content.padding(.top, 12)
            Rectangle().fill(Color.tingAmber.opacity(0.3)).frame(height: 1).padding(.top, 10)
            HStack(spacing: 14) {
                ForEach(footer, id: \.self) { MonoLabel($0, size: 9, weight: .regular, tracking: 1) }
                Spacer()
            }
            .foregroundStyle(Color.tingMuted)
            .padding(.top, 10)
            .accessibilityHidden(true)
        }
        .foregroundStyle(Color.tingInk)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 580)
        .background(Color.soundPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.tingAmber).frame(height: 3)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.tingStroke.opacity(0.6), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("micro-app \(title)")
    }
}

private struct ApprovalBody: View {
    let app: MicroApp
    let file: String
    let onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run this micro-app?").font(.system(size: 15, weight: .semibold))
            Text("This file is new or changed. Ting runs its command with your full rights. Approve it only if you trust every line.")
                .font(.system(size: 12)).foregroundStyle(Color.tingMuted)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    MonoLabel("name", size: 9, weight: .regular).foregroundStyle(Color.tingMuted)
                    Text(app.shownName).font(.system(size: 12, weight: .medium))
                }
                GridRow {
                    MonoLabel("file", size: 9, weight: .regular).foregroundStyle(Color.tingMuted)
                    Text(file).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
                if !app.tools.isEmpty {
                    GridRow {
                        MonoLabel("tools", size: 9, weight: .regular).foregroundStyle(Color.tingMuted)
                        Text(app.tools.joined(separator: ", ")).font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            MonoLabel("command", size: 9, weight: .regular).foregroundStyle(Color.tingMuted).padding(.top, 4)
            SelectableText(text: app.command, monospaced: true, takesFocus: false)
                .frame(height: commandHeight)
                .background(Color.tingInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Approve and Run", action: onApprove)
                    .keyboardShortcut(.return, modifiers: .command)
                    .controlSize(.small)
            }
        }
    }

    /// Grows with the command, then scrolls.
    private var commandHeight: CGFloat {
        let lines = app.command.split(separator: "\n", omittingEmptySubsequences: false).count
        return min(300, max(44, CGFloat(lines) * 16 + 16))
    }
}

private struct ResultBody: View {
    let content: MicroAppPanelContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if content.isError || !content.notes.isEmpty {
                HStack(spacing: 8) {
                    if content.isError {
                        Image(systemName: "xmark.octagon.fill").foregroundStyle(Color.red)
                            .accessibilityLabel("Error")
                    }
                    ForEach(content.notes, id: \.self) { note in
                        MonoLabel(note, size: 9, tracking: 1).foregroundStyle(Color.tingAmber)
                    }
                    Spacer()
                }
            }
            if !content.text.isEmpty {
                let rendered = MicroAppOutputRenderer.render(content)
                SelectableText(text: rendered, plainText: content.plainText, takesFocus: true)
                    .frame(height: height(rendered))
                    .background(Color.tingInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// Grows with the text, then scrolls.
    private func height(_ rendered: NSAttributedString) -> CGFloat {
        let measured: CGFloat
        if rendered.length <= 20_000 {
            measured = ceil(rendered.boundingRect(with: NSSize(width: SelectableText.textWidth, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        } else {
            measured = CGFloat(content.text.split(separator: "\n", omittingEmptySubsequences: false).count) * 17
        }
        return min(440, max(44, measured + 20))
    }
}

/// Read-only, selectable, scrolling text: ⌘C copies the selection as plain text (the whole plain
/// text when nothing is selected), ⌘A selects all.
private struct SelectableText: NSViewRepresentable {
    let text: NSAttributedString
    let plainText: String
    /// The text view becomes the first responder, so ⌘C and the arrow keys reach it at once.
    let takesFocus: Bool

    /// The width the text gets inside the card: the card minus its padding, the inset and the line padding.
    static let textWidth: CGFloat = 580 - 40 - 12 - 10

    init(text: NSAttributedString, plainText: String, takesFocus: Bool) {
        self.text = text
        self.plainText = plainText
        self.takesFocus = takesFocus
    }

    init(text: String, monospaced: Bool, takesFocus: Bool) {
        self.init(text: MicroAppOutputRenderer.render(text, style: monospaced ? .code : .text), plainText: text,
                  takesFocus: takesFocus)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let view = PlainCopyTextView(frame: NSRect(x: 0, y: 0, width: SelectableText.textWidth, height: 0))
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 6, height: 8)
        view.isAutomaticLinkDetectionEnabled = false
        scroll.documentView = view
        update(scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        update(scroll)
    }

    private func update(_ scroll: NSScrollView) {
        guard let view = scroll.documentView as? PlainCopyTextView else { return }
        view.plainText = plainText
        if let storage = view.textStorage, !storage.isEqual(to: text) {
            storage.setAttributedString(text)
            view.scrollToBeginningOfDocument(nil)
        }
        if takesFocus {
            DispatchQueue.main.async {
                if let window = view.window, window.firstResponder !== view { window.makeFirstResponder(view) }
            }
        }
    }
}

/// Copies plain text only, never the styling: the selection as shown, or `plainText` without a selection.
private final class PlainCopyTextView: NSTextView {
    var plainText = ""

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        let text = range.length == 0 ? plainText : (string as NSString).substring(with: range)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
