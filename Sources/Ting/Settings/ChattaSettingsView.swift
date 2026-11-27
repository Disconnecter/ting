// Settings › Chatta: hotkey, default ACP agent/model/effort and idle subprocess timeout.
import BobukCore
import BobukUI
import SwiftUI
import TingCore

struct ChattaSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var statuses: [ACPAgentStatus] = []

    private var resolvedStatuses: [ACPAgentStatus] {
        statuses.isEmpty ? ACPAgentPreset.detectAll() : statuses
    }

    var body: some View {
        let settings = model.config.chatta
        let allStatuses = resolvedStatuses
        let byID = Dictionary(uniqueKeysWithValues: allStatuses.map { ($0.id, $0) })
        let missingAdapters = allStatuses.filter(\.needsACPAdapter)
        Form {
            Section {
                LabeledContent("Hotkey") { ChattaHotkeyField() }
                LabeledContent("Default agent") {
                    Picker("", selection: Binding(
                        get: { settings.agent ?? "" },
                        set: { value in model.update { $0.chatta.agent = value.isEmpty ? nil : value } }
                    )) {
                        Text("Auto (first installed)").tag("")
                        Divider()
                        ForEach(ACPAgentPreset.all) { preset in
                            let label: String = switch byID[preset.id]?.availability {
                            case .ready: preset.name
                            case .needsACPAdapter: "\(preset.name) (needs ACP adapter)"
                            case .notInstalled, nil: "\(preset.name) (not installed)"
                            }
                            Text(label).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }
                ForEach(missingAdapters) { status in
                    ACPAdapterInstallRow(preset: status.preset) {
                        statuses = ACPAgentPreset.detectAll()
                    }
                }
                LabeledContent("Default model") {
                    TextField("Agent default", text: Binding(
                        get: { settings.model ?? "" },
                        set: { value in
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            model.update { $0.chatta.model = trimmed.isEmpty ? nil : trimmed }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                }
                LabeledContent("Reasoning effort") {
                    Picker("", selection: Binding(
                        get: { settings.effort ?? "" },
                        set: { value in model.update { $0.chatta.effort = value.isEmpty ? nil : value } }
                    )) {
                        Text("Agent default").tag("")
                        ForEach(ChattaSettings.effortChoices, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Text("Used by the Chatta window and by `chatta:` steps in micro-apps when a step does not specify its own agent, model or effort.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { SettingsSectionTitle("Agent") }
            .id("chatta")

            Section {
                Toggle("Allow agent tools in Chat mode", isOn: model.binding(\.chatta.allowTools))
                Text("Off by default. Allows built-in tools such as web search in Chat mode inside the sandbox, without giving access to personal folders. On the first tool call while off, Chatta asks whether to allow always, for the session, or decline.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Close idle agent after") {
                    Stepper(value: model.binding(\.chatta.idleTimeoutMinutes),
                            in: ChattaSettings.idleTimeoutMinutesRange, step: 5) {
                        Text(settings.idleTimeoutMinutes == 0 ? "Never" : "\(settings.idleTimeoutMinutes) min")
                            .monospacedDigit()
                    }
                }
                Text("Closing the Chatta window hides it and keeps the session ready. After this many minutes without activity, Ting stops the agent process while keeping the visible transcript.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Text size") {
                    HStack(spacing: 8) {
                        Stepper(value: Binding(
                            get: { settings.textScale },
                            set: { value in model.update { $0.chatta.textScale = ChatTextScale.clamped(value) } }
                        ), in: ChatTextScale.range, step: ChatTextScale.step) {
                            Text(ChatTextScale.percent(settings.textScale)).monospacedDigit()
                        }
                        Button("Reset") { model.update { $0.chatta.textScale = ChatTextScale.standard } }
                            .disabled(settings.textScale == ChatTextScale.standard)
                    }
                }
                Text("The chat text, its headings and code, and the message field. In the Chatta window, ⌘+ and ⌘− change it and ⌘0 returns to 100%.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Send with", selection: model.binding(\.chatta.sendKey)) {
                    Text("⌘↩ — ↩ adds a line").tag(ChatSendKey.commandReturn)
                    Text("↩ — ⇧↩ adds a line").tag(ChatSendKey.return)
                }
                HStack(spacing: 10) {
                    Button("Open Chatta") { model.openChatta() }
                    Button("Configure Ting with Chatta") { model.openChatta(mode: .configure) }
                }
            } header: { SettingsSectionTitle("Session") }
        }
        .tingSettingsForm()
        .onAppear {
            statuses = ACPAgentPreset.detectAll()
        }
    }
}
