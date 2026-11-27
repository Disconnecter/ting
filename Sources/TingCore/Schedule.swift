import Foundation

/// Ting's read access to macOS Calendar, mapped from EventKit without exposing EventKit to TingCore.
public enum ScheduleAccess: String, Equatable, Sendable {
    case notDetermined, restricted, denied, writeOnly, fullAccess

    public var canRead: Bool { self == .fullAccess }
}

/// One EventKit calendar available for schedule filtering.
public struct ScheduleCalendarInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var source: String
    /// Six-digit sRGB hex, without `#`.
    public var colorHex: String

    public init(id: String, title: String, source: String = "", colorHex: String = "888888") {
        self.id = id
        self.title = title
        self.source = source
        self.colorHex = colorHex
    }
}

/// A privacy-minimized value copy of an EventKit event. Notes never cross the service boundary;
/// only a recognized meeting link detected from EventKit fields may be retained in memory.
public struct ScheduleEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var calendarID: String
    public var calendarTitle: String
    public var calendarColorHex: String
    public var title: String
    public var location: String?
    public var meeting: ScheduleMeetingLink?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// False for events whose EventKit availability is `free`.
    public var isBusy: Bool

    public init(id: String, calendarID: String, calendarTitle: String, calendarColorHex: String = "888888",
                title: String, location: String? = nil, meeting: ScheduleMeetingLink? = nil,
                start: Date, end: Date, isAllDay: Bool = false, isBusy: Bool = true) {
        self.id = id
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.calendarColorHex = calendarColorHex
        self.title = title
        self.location = location
        self.meeting = meeting
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isBusy = isBusy
    }
}

/// One read from the calendar service.
public struct ScheduleData: Equatable, Sendable {
    public var access: ScheduleAccess
    public var calendars: [ScheduleCalendarInfo]
    public var events: [ScheduleEvent]

    public init(access: ScheduleAccess, calendars: [ScheduleCalendarInfo] = [], events: [ScheduleEvent] = []) {
        self.access = access
        self.calendars = calendars
        self.events = events
    }
}

public struct ScheduleFreeSlot: Identifiable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var id: String { "\(start.timeIntervalSinceReferenceDate)-\(end.timeIntervalSinceReferenceDate)" }

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public struct ScheduleDay: Identifiable, Equatable, Sendable {
    public var date: Date
    public var events: [ScheduleEvent]
    /// Useful gaps before the next busy event. The open-ended rest of a day is represented by current availability.
    public var freeSlots: [ScheduleFreeSlot]
    public var id: Date { date }

    public init(date: Date, events: [ScheduleEvent], freeSlots: [ScheduleFreeSlot]) {
        self.date = date
        self.events = events
        self.freeSlots = freeSlots
    }
}

public enum ScheduleAvailability: Equatable, Sendable {
    case busy(ScheduleEvent)
    /// `until == nil` means free for the rest of today.
    case free(until: Date?)
}

public struct SchedulePlan: Equatable, Sendable {
    public var availability: ScheduleAvailability
    public var days: [ScheduleDay]

    public init(availability: ScheduleAvailability, days: [ScheduleDay]) {
        self.availability = availability
        self.days = days
    }
}

/// Pure schedule grouping and free/busy calculation.
public enum SchedulePlanner {
    public static let defaultDayCount = 7
    public static let minimumFreeSlot: TimeInterval = 15 * 60

    public static func plan(events: [ScheduleEvent], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent,
                            dayCount: Int = defaultDayCount) -> SchedulePlan {
        let count = max(1, dayCount)
        let today = calendar.startOfDay(for: now)
        let rangeEnd = calendar.date(byAdding: .day, value: count, to: today) ?? today.addingTimeInterval(Double(count) * 86_400)
        let relevant = events.filter { $0.end > $0.start && $0.end > today && $0.start < rangeEnd }
            .sorted(by: eventOrder)
        let availability = currentAvailability(in: relevant, now: now, calendar: calendar)
        var days: [ScheduleDay] = []
        days.reserveCapacity(count)
        for offset in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let dayEvents = relevant.filter { $0.end > day && $0.start < next }
            let freeSlots = freeSlots(events: dayEvents, day: day, nextDay: next,
                                      cursor: offset == 0 ? max(now, day) : nil)
            days.append(ScheduleDay(date: day, events: dayEvents, freeSlots: freeSlots))
        }
        return SchedulePlan(availability: availability, days: days)
    }

    private static func currentAvailability(in events: [ScheduleEvent], now: Date, calendar: Calendar) -> ScheduleAvailability {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let busy = events.filter { $0.isBusy && $0.end > now && $0.start < tomorrow }
        if let current = busy.filter({ ($0.isAllDay || $0.start <= now) && $0.end > now })
            .sorted(by: { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay }
                if lhs.end != rhs.end { return lhs.end < rhs.end }
                return eventOrder(lhs, rhs)
            }).first {
            return .busy(current)
        }
        let next = busy.filter { !$0.isAllDay && $0.start > now }.min(by: eventOrder)
        return .free(until: next?.start)
    }

    private struct Interval {
        var start: Date
        var end: Date
    }

    private static func freeSlots(events: [ScheduleEvent], day: Date, nextDay: Date, cursor: Date?) -> [ScheduleFreeSlot] {
        // A busy all-day event makes the day unavailable. Free all-day events remain visible but do not block it.
        if events.contains(where: { $0.isBusy && $0.isAllDay }) { return [] }
        let intervals = merge(events.filter { $0.isBusy && !$0.isAllDay }.map {
            Interval(start: max($0.start, day), end: min($0.end, nextDay))
        }.filter { $0.end > $0.start })
        guard !intervals.isEmpty else { return [] }
        var result: [ScheduleFreeSlot] = []
        if var point = cursor {
            for interval in intervals where interval.end > point {
                if interval.start.timeIntervalSince(point) >= minimumFreeSlot {
                    result.append(ScheduleFreeSlot(start: point, end: interval.start))
                }
                point = max(point, interval.end)
            }
            return result
        }
        for pair in zip(intervals, intervals.dropFirst()) where pair.1.start.timeIntervalSince(pair.0.end) >= minimumFreeSlot {
            result.append(ScheduleFreeSlot(start: pair.0.end, end: pair.1.start))
        }
        return result
    }

    private static func merge(_ intervals: [Interval]) -> [Interval] {
        let sorted = intervals.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var result: [Interval] = []
        for interval in sorted {
            guard var last = result.last else {
                result.append(interval)
                continue
            }
            if interval.start <= last.end {
                last.end = max(last.end, interval.end)
                result[result.count - 1] = last
            } else {
                result.append(interval)
            }
        }
        return result
    }

    private static func eventOrder(_ lhs: ScheduleEvent, _ rhs: ScheduleEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        if lhs.title != rhs.title { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
        return lhs.id < rhs.id
    }
}
