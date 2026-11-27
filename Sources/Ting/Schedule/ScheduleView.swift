import BobukUI
import SwiftUI
import TingCore

struct ScheduleView: View {
    let model: ScheduleModel
    let onRefresh: () -> Void
    let onRequestAccess: () -> Void
    let onOpenPrivacy: () -> Void
    let onSelect: (String) -> Void
    let onJoin: (String) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ScheduleCard(model: model, onRefresh: onRefresh, onRequestAccess: onRequestAccess,
                     onOpenPrivacy: onOpenPrivacy, onSelect: onSelect, onJoin: onJoin,
                     onOpenSettings: onOpenSettings)
            .padding(.top, 8)
    }
}

private struct ScheduleCard: View {
    @Bindable var model: ScheduleModel
    let onRefresh: () -> Void
    let onRequestAccess: () -> Void
    let onOpenPrivacy: () -> Void
    let onSelect: (String) -> Void
    let onJoin: (String) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.showHeader {
                HStack(spacing: 8) {
                    TingMark(size: 14)
                    MonoLabel("Ting  ·  My Schedule", size: 10, tracking: 2).foregroundStyle(Color.tingAmber)
                    Spacer(minLength: 0)
                    if model.isLoading { ProgressView().controlSize(.small) }
                    GlyphButton(.reload, label: "Refresh", help: "Refresh · ⌘R", palette: TingPickerStyle.palette,
                                width: 22, height: 22, glyphSize: 13, action: onRefresh)
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 14)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Color.tingAmber.opacity(0.3)).frame(height: 1).padding(.top, 12)
            HStack(spacing: 10) {
                ShortcutFooter([.init("↑↓", "navigate"), .init("↩", "join"),
                                .init("⌘R", "refresh"), .init("esc", "close")],
                               palette: TingPickerStyle.palette)
                Spacer(minLength: 0)
                GlyphButton(.settings, label: "Schedule settings", help: "Schedule settings · ⌘,",
                            palette: TingPickerStyle.palette, width: 22, height: 22, glyphSize: 13,
                            action: onOpenSettings)
            }
            .padding(.top, 10)
        }
        .foregroundStyle(Color.tingInk)
        .padding(.horizontal, 20)
        .padding(.top, model.showHeader ? 20 : 18)
        .padding(.bottom, 16)
        .frame(width: SchedulePanel.width - 40)
        .pickerPanel(palette: TingPickerStyle.palette)
        .background {
            RoundedRectangle(cornerRadius: PickerMetrics.panelRadius, style: .continuous)
                .fill(Color.tingPanel)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("My Schedule")
    }

    @ViewBuilder private var content: some View {
        if let error = model.error {
            ScheduleMessage(symbol: "exclamationmark.triangle", title: "Calendar could not be loaded", detail: error,
                            button: "Try Again", action: onRefresh)
        } else {
            switch model.access {
            case .notDetermined:
                ScheduleMessage(symbol: "calendar.badge.plus", title: "See your schedule in Ting",
                                detail: "Allow read access to macOS Calendar. Ting does not change events or store their contents.",
                                button: "Allow Calendar Access", action: onRequestAccess)
            case .denied, .restricted, .writeOnly:
                ScheduleMessage(symbol: "calendar.badge.exclamationmark", title: "Calendar access is off",
                                detail: "Give Ting full Calendar access in System Settings to show events and availability.",
                                button: "Open Calendar Privacy", action: onOpenPrivacy)
            case .fullAccess:
                ScheduleContent(plan: model.plan, now: model.now, hasCalendars: !model.calendars.isEmpty,
                                hasSelection: model.selectedCalendarIDs?.isEmpty != true,
                                selectedEventID: model.selectedEventID, message: model.message,
                                onSelect: onSelect, onJoin: onJoin)
            }
        }
    }
}

private struct ScheduleMessage: View {
    let symbol: String
    let title: String
    let detail: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Color.tingAmber)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(Color.tingMuted).multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button(button, action: action).buttonStyle(.tingQuiet(prominent: true))
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .accessibilityElement(children: .contain)
    }
}

private struct ScheduleContent: View {
    let plan: SchedulePlan
    let now: Date
    let hasCalendars: Bool
    let hasSelection: Bool
    let selectedEventID: String?
    let message: String?
    let onSelect: (String) -> Void
    let onJoin: (String) -> Void

    private var shownDays: [ScheduleDay] {
        let nonempty = plan.days.filter { !$0.events.isEmpty || !$0.freeSlots.isEmpty }
        return nonempty.isEmpty ? Array(plan.days.prefix(1)) : nonempty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AvailabilityCard(availability: plan.availability, now: now)
            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11.5)).foregroundStyle(Color.tingAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !hasCalendars {
                Text("No calendars are available in macOS Calendar.")
                    .font(.system(size: 12)).foregroundStyle(Color.tingMuted)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else if !hasSelection {
                Text("No calendars are selected. Choose calendars in Settings › My Schedule.")
                    .font(.system(size: 12)).foregroundStyle(Color.tingMuted)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(shownDays) { day in
                                ScheduleDayView(day: day, now: now, selectedEventID: selectedEventID,
                                                onSelect: onSelect, onJoin: onJoin)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: selectedEventID) {
                        if let selectedEventID { proxy.scrollTo("event-\(selectedEventID)", anchor: .center) }
                    }
                }
                .frame(minHeight: 260, maxHeight: 460)
                .accessibilityLabel("Upcoming calendar events")
            }
        }
    }
}

private struct AvailabilityCard: View {
    let availability: ScheduleAvailability
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(isBusy ? Color.tingAmber : Color.green.opacity(0.8)).frame(width: 9, height: 9)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Color.tingMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.tingInk.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.tingStroke.opacity(0.55), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }

    private var isBusy: Bool {
        if case .busy = availability { return true }
        return false
    }

    private var title: String {
        switch availability {
        case .busy(let event): "Busy · \(event.title)"
        case .free: "Available"
        }
    }

    private var detail: String {
        switch availability {
        case .busy(let event):
            return event.isAllDay ? "Busy all day" : "Until \(ScheduleFormat.time(event.end))"
        case .free(let until):
            guard let until else { return "Free for the rest of today" }
            return "Free for \(ScheduleFormat.duration(from: now, to: until)) · until \(ScheduleFormat.time(until))"
        }
    }
}

private struct ScheduleDayView: View {
    let day: ScheduleDay
    let now: Date
    let selectedEventID: String?
    let onSelect: (String) -> Void
    let onJoin: (String) -> Void

    private enum Row: Identifiable {
        case event(ScheduleEvent)
        case free(ScheduleFreeSlot)

        var id: String {
            switch self {
            case .event(let event): "event-\(event.id)"
            case .free(let slot): "free-\(slot.id)"
            }
        }

        var date: Date {
            switch self {
            case .event(let event): event.isAllDay ? .distantPast : event.start
            case .free(let slot): slot.start
            }
        }
    }

    private var rows: [Row] {
        (day.events.map(Row.event) + day.freeSlots.map(Row.free)).sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(ScheduleFormat.day(day.date, now: now)).font(.system(size: 12, weight: .semibold))
                Rectangle().fill(Color.tingStroke.opacity(0.45)).frame(height: 0.75)
            }
            if rows.isEmpty {
                Text("No events").font(.system(size: 11)).foregroundStyle(Color.tingMuted).padding(.leading, 94)
            } else {
                ForEach(rows) { row in
                    switch row {
                    case .event(let event):
                        ScheduleEventRow(event: event, now: now, selected: event.id == selectedEventID,
                                         onSelect: onSelect, onJoin: onJoin)
                            .id("event-\(event.id)")
                    case .free(let slot): ScheduleFreeRow(slot: slot)
                    }
                }
            }
        }
    }
}

private struct ScheduleEventRow: View {
    let event: ScheduleEvent
    let now: Date
    let selected: Bool
    let onSelect: (String) -> Void
    let onJoin: (String) -> Void

    var body: some View {
        Button { onSelect(event.id) } label: {
            PickerRow(selected: selected, palette: TingPickerStyle.palette) {
                HStack(alignment: .top, spacing: 10) {
                    Text(event.isAllDay ? "all day" : ScheduleFormat.range(event.start, event.end))
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.tingMuted)
                        .frame(width: 84, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 2).fill(ScheduleFormat.color(event.calendarColorHex))
                        .frame(width: 4, height: 30).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(event.title).font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium)).lineLimit(2)
                            if !event.isBusy {
                                Text("free").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.tingMuted)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.tingInk.opacity(0.06)))
                            }
                        }
                        Text([event.calendarTitle, event.location].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10.5)).foregroundStyle(Color.tingMuted).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let meeting = event.meeting {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill").accessibilityHidden(true)
                            Text(meeting.platform.title)
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.tingAmber)
                        .lineLimit(1)
                    }
                    if selected {
                        Image(systemName: event.meeting == nil ? "checkmark" : "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.tingAmber)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onJoin(event.id) })
        .help(event.meeting.map { "Join \($0.platform.title)" } ?? "No meeting link")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(event.meeting == nil ? "Selects the event. Return reports that no meeting link was found."
                           : "Return or double-click joins the meeting.")
    }

    private var isCurrent: Bool { event.start <= now && event.end > now }

    private var accessibilityLabel: String {
        let time = event.isAllDay ? "All day" : ScheduleFormat.range(event.start, event.end)
        return [time, event.title, event.calendarTitle, event.location, event.meeting?.platform.title]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

private struct ScheduleFreeRow: View {
    let slot: ScheduleFreeSlot

    var body: some View {
        HStack(spacing: 10) {
            Text(ScheduleFormat.range(slot.start, slot.end))
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.tingMuted)
                .frame(width: 84, alignment: .trailing)
            Image(systemName: "circle.dotted").font(.system(size: 11)).foregroundStyle(Color.green.opacity(0.8))
                .frame(width: 4).accessibilityHidden(true)
            Text("Free · \(ScheduleFormat.duration(from: slot.start, to: slot.end))")
                .font(.system(size: 11.5)).foregroundStyle(Color.tingMuted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private enum ScheduleFormat {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func range(_ start: Date, _ end: Date) -> String { "\(time(start))–\(time(end))" }

    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDate(date, inSameDayAs: now) { return "Today · \(weekdayFormatter.string(from: date))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow · \(weekdayFormatter.string(from: date))" }
        return weekdayFormatter.string(from: date)
    }

    static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    static func color(_ hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return Color.tingMuted }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
