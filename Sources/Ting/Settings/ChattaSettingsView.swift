// Settings › Chatta: hotkey, default ACP agent/model/effort and idle subprocess timeout.
import BobukCore
import SwiftUI
import TingCore

struct ChattaSettingsView: View {
    @Environment(AppModel.self) private var model

    private var installedIDs: Set<String> {
        Set(ACPAgentPreset.detectInstalled().map(\.id))
    }

    var body: some View {
        let settings = model.config.chatta
        let installed = installedIDs
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
                            let label = installed.contains(preset.id) ? preset.name : "\(preset.name) (not installed)"
                            Text(label).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
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
                LabeledContent("Close idle agent after") {
                    Stepper(value: model.binding(\.chatta.idleTimeoutMinutes),
                            in: ChattaSettings.idleTimeoutMinutesRange, step: 5) {
                        Text(settings.idleTimeoutMinutes == 0 ? "Never" : "\(settings.idleTimeoutMinutes) min")
                            .monospacedDigit()
                    }
                }
                Text("Closing the Chatta window hides it and keeps the session ready. After this many minutes without activity, Ting stops the agent process while keeping the visible transcript.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Open Chatta") { model.openChatta() }
                    Button("Configure Ting with Chatta") { model.openChatta(mode: .configure) }
                }
            } header: { SettingsSectionTitle("Session") }
        }
        .tingSettingsForm()
    }
}
