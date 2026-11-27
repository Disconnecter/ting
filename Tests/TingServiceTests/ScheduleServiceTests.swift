import AppKit
import Foundation
import SwiftUI
import XCTest
import TingCore
@testable import Ting

private actor FakeScheduleService: ScheduleServing {
    var data: ScheduleData
    var requestedAccess: ScheduleAccess
    var loads: [[String]?] = []
    var requests = 0

    init(data: ScheduleData, requestedAccess: ScheduleAccess = .fullAccess) {
        self.data = data
        self.requestedAccess = requestedAccess
    }

    func load(from start: Date, to end: Date, calendarIDs: [String]?) async throws -> ScheduleData {
        loads.append(calendarIDs)
        return data
    }

    func requestAccess() async throws -> ScheduleAccess {
        requests += 1
        data.access = requestedAccess
        return requestedAccess
    }

    func recordedLoads() -> [[String]?] { loads }
    func requestCount() -> Int { requests }
}

@MainActor
final class ScheduleServiceTests: XCTestCase {
    private let calendar = ScheduleCalendarInfo(id: "work", title: "Work", source: "iCloud", colorHex: "FF8800")

    private func event() -> ScheduleEvent {
        let start = Date().addingTimeInterval(3_600)
        return ScheduleEvent(id: "meeting", calendarID: "work", calendarTitle: "Work", calendarColorHex: "FF8800",
                             title: "Planning", location: "Room 1", start: start,
                             end: start.addingTimeInterval(1_800))
    }

    func testModelLoadsSelectedCalendarsAndBuildsPlan() async {
        let service = FakeScheduleService(data: ScheduleData(access: .fullAccess, calendars: [calendar], events: [event()]))
        let model = ScheduleModel(service: service)
        var config = Config()
        config.schedule.calendars = ["work"]
        model.configure(config)
        await model.refresh()

        let loads = await service.recordedLoads()
        XCTAssertEqual(model.access, .fullAccess)
        XCTAssertEqual(model.calendars, [calendar])
        XCTAssertEqual(model.events.map(\.id), ["meeting"])
        XCTAssertEqual(loads, [["work"]])
        XCTAssertTrue(model.calendarIsSelected("work"))
        XCTAssertFalse(model.calendarIsSelected("home"))
    }

    func testRequestAccessReloadsEvents() async {
        let service = FakeScheduleService(data: ScheduleData(access: .notDetermined, calendars: [calendar], events: [event()]))
        let model = ScheduleModel(service: service)
        await model.requestAccess()

        let requests = await service.requestCount()
        let loadCount = await service.recordedLoads().count
        XCTAssertEqual(model.access, .fullAccess)
        XCTAssertEqual(model.events.map(\.id), ["meeting"])
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(loadCount, 1)
    }

    func testOffscreenControllerOwnsNoWindowAndClosesCleanly() async {
        let service = FakeScheduleService(data: ScheduleData(access: .fullAccess, calendars: [calendar]))
        let controller = ScheduleController(model: ScheduleModel(service: service), presentsWindow: false)
        controller.open()
        XCTAssertTrue(controller.isOpen)
        await Task.yield()
        controller.close()
        XCTAssertFalse(controller.isOpen)
    }

    func testNavigationStartsAtNextEventAndMovesWithinBounds() async {
        let now = Date()
        let events = [
            ScheduleEvent(id: "past", calendarID: "work", calendarTitle: "Work", title: "Past",
                          start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(-1_800)),
            ScheduleEvent(id: "next", calendarID: "work", calendarTitle: "Work", title: "Next",
                          start: now.addingTimeInterval(1_800), end: now.addingTimeInterval(3_600)),
            ScheduleEvent(id: "later", calendarID: "work", calendarTitle: "Work", title: "Later",
                          start: now.addingTimeInterval(7_200), end: now.addingTimeInterval(9_000)),
        ]
        let service = FakeScheduleService(data: ScheduleData(access: .fullAccess, calendars: [calendar], events: events))
        let model = ScheduleModel(service: service)
        await model.refresh(at: now)
        XCTAssertEqual(model.selectedEventID, "next")
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedEventID, "later")
        model.moveSelection(by: 8)
        XCTAssertEqual(model.selectedEventID, "later")
        model.moveSelection(by: -8)
        XCTAssertEqual(model.selectedEventID, "past")
    }

    func testJoinOpensKnownMeetingAndClosesPanel() async throws {
        let url = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        let meeting = ScheduleMeetingLink(url: url, platform: .googleMeet)
        let start = Date().addingTimeInterval(1_800)
        let event = ScheduleEvent(id: "join", calendarID: "work", calendarTitle: "Work", title: "Daily",
                                  meeting: meeting, start: start, end: start.addingTimeInterval(1_800))
        let service = FakeScheduleService(data: ScheduleData(access: .fullAccess, calendars: [calendar], events: [event]))
        let model = ScheduleModel(service: service)
        await model.refresh()
        var opened: [URL] = []
        let controller = ScheduleController(model: model, presentsWindow: false) { opened.append($0); return true }
        model.setOpen(true)
        controller.join()
        XCTAssertEqual(opened, [url])
        XCTAssertFalse(controller.isOpen)
    }

    func testJoinWithoutLinkKeepsPanelOpenAndShowsMessage() async {
        let service = FakeScheduleService(data: ScheduleData(access: .fullAccess, calendars: [calendar], events: [event()]))
        let model = ScheduleModel(service: service)
        await model.refresh()
        let controller = ScheduleController(model: model, presentsWindow: false) { _ in XCTFail("should not open"); return false }
        model.setOpen(true)
        controller.join()
        XCTAssertTrue(controller.isOpen)
        XCTAssertEqual(model.message, "No meeting link found in Planning.")
    }

    func testStatusMenuIncludesSchedule() {
        let model = AppModel(presentsWindows: false)
        let controller = StatusItemController(model: model, makesStatusItem: false, openSettings: {}, openWelcome: {})
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        XCTAssertNotNil(menu.items.first { $0.title == "Open My Schedule" })
    }

    func testScheduleViewRendersOffscreen() async throws {
        _ = NSApplication.shared
        let now = Date()
        let meeting = ScheduleEvent(id: "meeting", calendarID: "work", calendarTitle: "Work",
                                    calendarColorHex: "FF8800", title: "Planning", location: "Room 1",
                                    start: now.addingTimeInterval(1_800), end: now.addingTimeInterval(5_400))
        let service = FakeScheduleService(data: ScheduleData(access: .fullAccess, calendars: [calendar], events: [meeting]))
        let model = ScheduleModel(service: service)
        await model.refresh(at: now)
        let hosting = scheduleHosting(model)
        let size = NSSize(width: SchedulePanel.width, height: 620)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertLessThanOrEqual(hosting.fittingSize.width, size.width)
        XCTAssertLessThanOrEqual(hosting.fittingSize.height, size.height)
        if let path = ProcessInfo.processInfo.environment["TING_SCHEDULE_PREVIEW_DIR"] {
            try save(hosting, at: URL(fileURLWithPath: path).appendingPathComponent("schedule.png"))
        }
    }

    func testJoinableScheduleViewRendersOffscreen() async throws {
        _ = NSApplication.shared
        let now = Date()
        let meetURL = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        let events = [
            ScheduleEvent(id: "standup", calendarID: "work", calendarTitle: "Work",
                          calendarColorHex: "4285F4", title: "Daily standup", location: "Remote",
                          meeting: ScheduleMeetingLink(url: meetURL, platform: .googleMeet),
                          start: now.addingTimeInterval(1_800), end: now.addingTimeInterval(3_600)),
            ScheduleEvent(id: "lunch", calendarID: "work", calendarTitle: "Work",
                          calendarColorHex: "FF8800", title: "Lunch", location: "Cafe",
                          start: now.addingTimeInterval(7_200), end: now.addingTimeInterval(10_800)),
        ]
        let service = FakeScheduleService(data: ScheduleData(access: .fullAccess, calendars: [calendar], events: events))
        let model = ScheduleModel(service: service)
        await model.refresh(at: now)
        let hosting = scheduleHosting(model)
        hosting.frame = NSRect(x: 0, y: 0, width: SchedulePanel.width, height: 620)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.selectedEventID, "standup")
        if let path = ProcessInfo.processInfo.environment["TING_SCHEDULE_NAV_PREVIEW_DIR"] {
            try save(hosting, at: URL(fileURLWithPath: path).appendingPathComponent("schedule-navigation.png"))
        }
    }

    private func scheduleHosting(_ model: ScheduleModel) -> NSHostingView<ScheduleView> {
        NSHostingView(rootView: ScheduleView(model: model, onRefresh: {}, onRequestAccess: {},
                                             onOpenPrivacy: {}, onSelect: { model.select($0) },
                                             onJoin: { _ in }, onOpenSettings: {}))
    }

    private func save(_ hosting: NSHostingView<ScheduleView>, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
