// SwiftUI body of the Chatta ChromeWindow: mode bar + BobukKit's AgentChatView + shortcut footer.
import BobukCore
import BobukUI
import SwiftUI
import TingCore

struct ChattaView: View {
    @Bindable var controller: ChattaController
    let theme: ThemeStore
    var onSettings: () -> Void

    private var emptyTitle: String {
        switch controller.mode {
        case .chat: "Chatta"
        case .configure: "Configure Ting"
        }
    }

    private var intro: String {
        switch controller.mode {
        case .chat:
            "Quick text-only conversation with your local ACP agent."
        case .configure:
            "Ask Chatta to edit bindings, adjust settings, or write and check micro-apps in your Ting folder."
        }
    }

    private var starters: [String] {
        switch controller.mode {
        case .chat:
            [
                "Explain a tricky error or log snippet",
                "Draft a short, clear message",
                "Compare two approaches briefly",
            ]
        case .configure:
            [
                "Write a new micro-app that summarizes the clipboard",
                "Add a key binding to open a website or app",
                "Review my config.json and micro-apps for issues",
            ]
        }
    }

    var body: some View {
        let tokens = theme.tokens
        VStack(spacing: 0) {
            modeBar(tokens: tokens)
            Divider()
            AgentChatView(
                session: controller.session,
                agent: controller.selectedAgent.name,
                intro: intro,
                emptyTitle: emptyTitle,
                placeholder: controller.mode == .configure ? "Describe a Ting change or micro-app…" : "Message…",
                starters: starters,
                sandboxed: $controller.sandboxed,
                agents: ACPAgentPreset.all,
                selectedAgent: $controller.selectedAgent,
                workingDirectory: controller.mode == .configure ? controller.configDirectory : nil,
                tokens: tokens
            )
            Divider()
            ShortcutFooter(
                [.init("⌘↩", "send"), .init("esc", "stop"), .init("⌘N", "new chat")],
                palette: tokens.pickerPalette(),
                settingsHelp: "Settings · ⌘,",
                onSettings: onSettings
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(tokens.panelColor)
        .themedSurface(theme)
        .onChange(of: controller.selectedAgent) { _, _ in
            controller.agentSelectionChanged()
        }
        .background {
            Button("") { controller.newChat() }
                .keyboardShortcut("n", modifiers: .command)
                .hidden()
        }
    }

    private func modeBar(tokens: ThemeTokens) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(ChattaMode.allCases) { item in
                    let active = controller.mode == item
                    Button {
                        controller.setMode(item)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item == .chat ? "bubble.left" : "wrench.and.screwdriver")
                                .font(.system(size: 10.5))
                            Text(item.title)
                                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .foregroundStyle(active ? tokens.inkColor : tokens.mutedColor)
                        .background(
                            active ? tokens.elevatedColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay {
                            if active {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(tokens.lineColor, lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(2)
            .background(tokens.fieldColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tokens.lineColor, lineWidth: 1)
            }

            Spacer(minLength: 8)

            Text(controller.mode == .configure ? "Config workspace" : "Text only")
                .font(.system(size: 11))
                .foregroundStyle(tokens.mutedColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
