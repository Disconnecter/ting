import SwiftUI
import TingCore

struct ScheduleSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Calendar access") {
                    Text(accessText).foregroundStyle(accessColor)
                }
                switch model.schedule.model.access {
                case .notDetermined:
                    Button("Allow Calendar Access") { model.schedule.requestAccess() }
                case .denied, .restricted, .writeOnly:
                    Button("Open Calendar Privacy…") { model.schedule.openPrivacySettings() }
                case .fullAccess:
                    Button("Refresh Calendars") { model.schedule.refresh() }
                }
                Text("Ting reads event times, titles, locations and availability. It never changes events or stores their contents.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.schedule.model.error {
                    Text(error).font(.caption).foregroundStyle(Color.tingAmber)
                }
            } header: { SettingsSectionTitle("Access") }
            .id("schedule-access")

            if model.schedule.model.access.canRead {
                Section {
                    HStack {
                        Text(selectionSummary).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("All") { model.selectAllScheduleCalendars() }.controlSize(.small)
                        Button("None") { model.selectNoScheduleCalendars() }.controlSize(.small)
                    }
                    if model.schedule.model.calendars.isEmpty {
                        Text("No calendars are available in macOS Calendar.").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.schedule.model.calendars) { calendar in
                            Toggle(isOn: Binding(
                                get: { model.schedule.model.calendarIsSelected(calendar.id) },
                                set: { model.setScheduleCalendar(calendar.id, included: $0) })) {
                                HStack(spacing: 8) {
                                    Circle().fill(scheduleColor(calendar.colorHex)).frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(calendar.title)
                                        if !calendar.source.isEmpty {
                                            Text(calendar.source).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .accessibilityLabel(calendar.source.isEmpty ? calendar.title : "\(calendar.title), \(calendar.source)")
                        }
                    }
                    Text("With All selected, new calendars appear automatically. An explicit selection stays fixed.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { SettingsSectionTitle("Calendars") }
                .id("schedule-calendars")

                Section {
                    Button("Open My Schedule") { model.openSchedule() }
                } header: { SettingsSectionTitle("Preview") }
            }
        }
        .tingSettingsForm()
        .task { await model.schedule.model.refresh() }
    }

    private var accessText: String {
        switch model.schedule.model.access {
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .writeOnly: "Write only"
        case .fullAccess: "Full access"
        }
    }

    private var accessColor: Color {
        model.schedule.model.access.canRead ? .secondary : .tingAmber
    }

    private var selectionSummary: String {
        guard let selected = model.config.schedule.calendars else { return "All calendars" }
        return selected.isEmpty ? "No calendars" : "\(selected.count) selected"
    }

    private func scheduleColor(_ hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return .secondary }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
