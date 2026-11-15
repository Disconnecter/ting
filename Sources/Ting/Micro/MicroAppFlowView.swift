// The micro-app panels in the launcha style: graphite card, amber top rule, mono footer.
// In this version every output style is shown as plain text: `code` and `console` (and every
// error) monospaced, `text` and `markdown` in the system font.
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
                SelectableText(text: content.text, monospaced: monospaced, takesFocus: true)
                    .frame(height: height)
                    .background(Color.tingInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var monospaced: Bool {
        content.isError || content.style == .code || content.style == .console
    }

    private var height: CGFloat {
        let lines = content.text.split(separator: "\n", omittingEmptySubsequences: false).count
        return min(440, max(44, CGFloat(lines) * 17 + 16))
    }
}

/// Read-only, selectable, scrolling text: ⌘C copies the selection, ⌘A selects all.
private struct SelectableText: NSViewRepresentable {
    let text: String
    let monospaced: Bool
    /// The text view becomes the first responder, so ⌘C and the arrow keys reach it at once.
    let takesFocus: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.textContainerInset = NSSize(width: 6, height: 8)
            view.isAutomaticLinkDetectionEnabled = false
        }
        update(scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        update(scroll)
    }

    private func update(_ scroll: NSScrollView) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let font = monospaced ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : NSFont.systemFont(ofSize: 13)
        if view.string != text || view.font != font {
            view.string = text
            view.font = font
            view.textColor = NSColor.theme(light: 0x222A2E, dark: 0xEEF1EC)
            view.scrollToBeginningOfDocument(nil)
        }
        if takesFocus {
            DispatchQueue.main.async {
                if let window = view.window, window.firstResponder !== view { window.makeFirstResponder(view) }
            }
        }
    }
}
