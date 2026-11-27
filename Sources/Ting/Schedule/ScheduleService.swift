import AppKit
import EventKit
import Foundation
import Observation
import TingCore

protocol ScheduleServing: Sendable {
    func load(from start: Date, to end: Date, calendarIDs: [String]?) async throws -> ScheduleData
    func requestAccess() async throws -> ScheduleAccess
}

actor EventKitScheduleService: ScheduleServing {
    private let store = EKEventStore()

    func requestAccess() async throws -> ScheduleAccess {
        _ = try await store.requestFullAccessToEvents()
        return Self.access()
    }

    func load(from start: Date, to end: Date, calendarIDs: [String]?) async throws -> ScheduleData {
        let access = Self.access()
        guard access.canRead else { return ScheduleData(access: access) }
        let eventCalendars = store.calendars(for: .event)
        let calendars = eventCalendars.map(Self.calendarInfo).sorted {
            if $0.source != $1.source { return $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        let selected: [EKCalendar]
        if let calendarIDs {
            let ids = Set(calendarIDs)
            selected = eventCalendars.filter { ids.contains($0.calendarIdentifier) }
        } else {
            selected = eventCalendars
        }
        guard !selected.isEmpty else { return ScheduleData(access: access, calendars: calendars) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        let events = store.events(matching: predicate).filter { $0.status != .canceled }.map(Self.event)
        return ScheduleData(access: access, calendars: calendars, events: events)
    }

    private static func access() -> ScheduleAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .denied
        }
    }

    private static func calendarInfo(_ calendar: EKCalendar) -> ScheduleCalendarInfo {
        ScheduleCalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                             source: calendar.source.title, colorHex: colorHex(calendar.cgColor))
    }

    private static func event(_ event: EKEvent) -> ScheduleEvent {
        let calendar = event.calendar
        let baseID = event.eventIdentifier ?? event.calendarItemIdentifier
        let occurrence = Int(event.startDate.timeIntervalSinceReferenceDate)
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let meeting = ScheduleMeetingDetector.find(eventURL: event.url, location: location, notes: event.notes)
        return ScheduleEvent(
            id: "\(baseID)-\(occurrence)", calendarID: calendar?.calendarIdentifier ?? "",
            calendarTitle: calendar?.title ?? "Calendar",
            calendarColorHex: calendar.map { colorHex($0.cgColor) } ?? "888888",
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled event",
            location: location?.nilIfEmpty, meeting: meeting, start: event.startDate, end: event.endDate,
            isAllDay: event.isAllDay, isBusy: event.availability != .free)
    }

    private static func colorHex(_ cgColor: CGColor) -> String {
        guard let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return "888888" }
        return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Tests and offscreen previews never touch the person's Calendar database.
struct ScheduleUnavailableService: ScheduleServing {
    func load(from start: Date, to end: Date, calendarIDs: [String]?) async throws -> ScheduleData {
        ScheduleData(access: .notDetermined)
    }

    func requestAccess() async throws -> ScheduleAccess { .denied }
}

@MainActor
@Observable
final class ScheduleModel {
    private(set) var access: ScheduleAccess = .notDetermined
    private(set) var calendars: [ScheduleCalendarInfo] = []
    private(set) var events: [ScheduleEvent] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var now = Date()
    private(set) var isOpen = false
    private(set) var selectedEventID: String?
    private(set) var message: String?
    var showHeader = true
    var selectedCalendarIDs: [String]?

    @ObservationIgnored private let service: any ScheduleServing
    @ObservationIgnored private var refreshSerial = 0

    init(service: any ScheduleServing) {
        self.service = service
    }

    var plan: SchedulePlan { SchedulePlanner.plan(events: events, now: now) }

    var navigableEvents: [ScheduleEvent] {
        var seen: Set<String> = []
        return plan.days.flatMap(\.events).filter { seen.insert($0.id).inserted }
    }

    var selectedEvent: ScheduleEvent? {
        guard let selectedEventID else { return nil }
        return navigableEvents.first { $0.id == selectedEventID }
    }

    func configure(_ config: Config) {
        showHeader = config.showPanelHeader
        selectedCalendarIDs = config.schedule.calendars
    }

    func setOpen(_ open: Bool) {
        isOpen = open
        if open {
            message = nil
            reconcileSelection()
        }
    }

    func select(_ id: String) {
        guard navigableEvents.contains(where: { $0.id == id }) else { return }
        selectedEventID = id
        message = nil
    }

    func moveSelection(by delta: Int) {
        let events = navigableEvents
        guard !events.isEmpty else { return }
        let current = events.firstIndex { $0.id == selectedEventID } ?? 0
        selectedEventID = events[min(max(current + delta, 0), events.count - 1)].id
        message = nil
    }

    func showMessage(_ text: String) { message = text }

    func refresh(at date: Date = Date()) async {
        refreshSerial += 1
        let serial = refreshSerial
        now = date
        isLoading = true
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: SchedulePlanner.defaultDayCount, to: start)
            ?? start.addingTimeInterval(Double(SchedulePlanner.defaultDayCount) * 86_400)
        do {
            let data = try await service.load(from: start, to: end, calendarIDs: selectedCalendarIDs)
            guard serial == refreshSerial else { return }
            access = data.access
            calendars = data.calendars
            events = data.events
            reconcileSelection()
            message = nil
            error = nil
        } catch {
            guard serial == refreshSerial else { return }
            self.error = error.localizedDescription
        }
        if serial == refreshSerial { isLoading = false }
    }

    func requestAccess() async {
        isLoading = true
        do {
            access = try await service.requestAccess()
            error = nil
            await refresh()
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func calendarIsSelected(_ id: String) -> Bool {
        selectedCalendarIDs.map { Set($0).contains(id) } ?? true
    }

    private func reconcileSelection() {
        let events = navigableEvents
        guard !events.isEmpty else {
            selectedEventID = nil
            return
        }
        if let selectedEventID, events.contains(where: { $0.id == selectedEventID }) { return }
        selectedEventID = events.first(where: { $0.end > now })?.id ?? events.first?.id
    }
}
