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
            controller.effectiveAllowTools
                ? "Conversation with your local ACP agent (built-in tools enabled) — drop files or paste images."
                : "Quick conversation with your local ACP agent — drop files or paste images."
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
                [.init("⌘↩", "send"), .init("esc", "stop"), .init("↑", "history"), .init("⌘N", "new chat")],
                palette: tokens.pickerPalette(),
                settingsHelp: "Settings · ⌘,",
                onSettings: onSettings
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tokens.elevatedColor.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tokens.panelColor)
        .themedSurface(theme)
        .onChange(of: controller.selectedAgent) { _, _ in
            controller.agentSelectionChanged()
        }
        .onChange(of: controller.session.models?.current) { _, _ in
            controller.recordPreferences()
        }
        .onChange(of: controller.session.efforts?.current) { _, _ in
            controller.recordPreferences()
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

            if controller.mode == .configure {
                Text("Config workspace")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.mutedColor)
            } else {
                chatToolsButton(tokens: tokens)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func chatToolsButton(tokens: ThemeTokens) -> some View {
        let enabled = controller.effectiveAllowTools
        let sessionOnly = controller.toolsOverrideForSession == true && !controller.allowToolsPermanently
        let label = !enabled ? "Tools off" : (sessionOnly ? "Tools · Session" : "Tools on")
        let canToggle = controller.session.phase == .ready || controller.session.phase == .disconnected
        return Button {
            controller.toggleChatTools()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: enabled ? "wrench.fill" : "wrench")
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: enabled ? .medium : .regular))
            }
            .foregroundStyle(enabled ? tokens.accentColor : tokens.mutedColor)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                enabled ? tokens.accentSurfaceColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(enabled ? tokens.accentColor.opacity(0.35) : tokens.lineColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
        .help(enabled
              ? "Built-in agent tools (such as web search) are enabled for this session. Click to turn off."
              : "Built-in agent tools are off. Click to enable for this session, or change the default in Settings › Chatta.")
    }
}
