import Foundation
import Testing
@testable import TingCore

@Suite struct SchedulePlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false, busy: Bool = true) -> ScheduleEvent {
        ScheduleEvent(id: id, calendarID: "work", calendarTitle: "Work", title: id,
                      start: start, end: end, isAllDay: allDay, isBusy: busy)
    }

    @Test func groupsEventsAndMergesBusyTimeIntoFreeSlots() {
        let now = date(8)
        let events = [
            event("All day", date(0), date(0, day: 2), allDay: true, busy: false),
            event("Standup", date(9), date(10)),
            event("Overlap", date(9, 30), date(11)),
            event("Optional", date(11, 30), date(12), busy: false),
            event("Review", date(13), date(14)),
        ]
        let plan = SchedulePlanner.plan(events: events, now: now, calendar: calendar, dayCount: 2)
        #expect(plan.days.count == 2)
        #expect(plan.days[0].events.map(\.id) == ["All day", "Standup", "Overlap", "Optional", "Review"])
        #expect(plan.days[0].freeSlots == [
            ScheduleFreeSlot(start: date(8), end: date(9)),
            ScheduleFreeSlot(start: date(11), end: date(13)),
        ])
        #expect(plan.availability == .free(until: date(9)))
    }

    @Test func currentTimedEventWinsOverBusyAllDayEvent() {
        let allDay = event("Conference", date(0), date(0, day: 2), allDay: true)
        let meeting = event("Meeting", date(10), date(11))
        let plan = SchedulePlanner.plan(events: [allDay, meeting], now: date(10, 30), calendar: calendar)
        #expect(plan.availability == .busy(meeting))
        #expect(plan.days[0].freeSlots.isEmpty)
    }

    @Test func futureDaysShowOnlyGapsBetweenBusyEvents() {
        let events = [event("Morning", date(9, day: 2), date(10, day: 2)),
                      event("Afternoon", date(14, day: 2), date(15, day: 2))]
        let plan = SchedulePlanner.plan(events: events, now: date(8), calendar: calendar, dayCount: 2)
        #expect(plan.days[0].freeSlots.isEmpty)
        #expect(plan.days[1].freeSlots == [ScheduleFreeSlot(start: date(10, day: 2), end: date(14, day: 2))])
        #expect(plan.availability == .free(until: nil))
    }
}
