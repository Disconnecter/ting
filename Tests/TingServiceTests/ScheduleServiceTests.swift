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
        let hosting = NSHostingView(rootView: ScheduleView(model: model, onRefresh: {}, onRequestAccess: {},
                                                           onOpenPrivacy: {}, onOpenSettings: {}))
        let size = NSSize(width: SchedulePanel.width, height: 620)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertLessThanOrEqual(hosting.fittingSize.width, size.width)
        XCTAssertLessThanOrEqual(hosting.fittingSize.height, size.height)
        if let path = ProcessInfo.processInfo.environment["TING_SCHEDULE_PREVIEW_DIR"] {
            let output = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("schedule.png"))
        }
    }
}
