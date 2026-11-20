import AppKit
import SwiftUI
import XCTest
import TingCore
import BobukUI
@testable import Ting

@MainActor
final class SettingsBobukKitTests: XCTestCase {
    func testPermanentShellFillsChromeWindowWithoutSplitViewOrSidebarToolbar() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")))
        for width in [900.0, 1040.0, 1280.0] {
            for query in ["", "history", "no-matching-parameter"] {
                let hosting = ChromeWindow.hosting(SettingsRoot(page: .clipbawd, query: query).environment(model))
                let window = SettingsWindow.make(contentSize: NSSize(width: width, height: 720))
                window.isReleasedWhenClosed = false
                window.setContent(hosting)
                window.setContentSize(ChromeMetrics.windowSize(forBody: NSSize(width: width, height: 720)))
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
                let views = descendants(hosting)
                XCTAssertTrue(window.body.subviews.first === hosting, "the content fills the ChromeWindow body")
                XCTAssertFalse(views.contains { $0 is PickerSurfaceView }, "the window draws the chrome, not a panel inside it")
                XCTAssertFalse(views.contains { $0 is NSSplitView }, "No split controller can collapse the column.")
                let toolbar = window.toolbar?.items.map { $0.itemIdentifier.rawValue.lowercased() } ?? []
                XCTAssertFalse(toolbar.contains { $0.contains("sidebar") || $0.contains("splitview") })
                XCTAssertEqual(hosting.bounds.width, width, accuracy: 0.5)
                XCTAssertFalse(window.isVisible)
                window.close()
            }
        }
        XCTAssertEqual(SettingsSidebar.width, 216)
    }

    func testSidebarKeepsItsWidthWithLongSearchAndEverySelection() {
        for page in SettingsPage.allCases {
            let sidebar = SettingsSidebar(page: page, query: .constant(String(repeating: "search ", count: 100)), onChoose: { _ in })
            let hosting = NSHostingView(rootView: sidebar.frame(width: SettingsSidebar.width, height: 560))
            XCTAssertEqual(hosting.fittingSize.width, SettingsSidebar.width, accuracy: 0.5)
            XCTAssertEqual(hosting.fittingSize.height, 560, accuracy: 0.5)
        }
    }

    func testSharedSearchUpdatesSidebarBindingAndCanBeCleared() async throws {
        var query = ""
        let sidebar = SettingsSidebar(page: .clipbawd, query: Binding(get: { query }, set: { query = $0 }), onChoose: { _ in })
        let hosting = ChromeWindow.hosting(sidebar.frame(width: SettingsSidebar.width, height: 560))
        let window = SettingsWindow.make()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContent(hosting)
        hosting.layoutSubtreeIfNeeded()
        let search = try XCTUnwrap(descendants(hosting).first { $0 is NSSearchField } as? NSSearchField)
        search.stringValue = "days"
        search.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: search))
        XCTAssertEqual(query, "days")
        search.stringValue = ""
        XCTAssertTrue(search.sendAction(try XCTUnwrap(search.action), to: search.target))
        XCTAssertEqual(query, "")
        XCTAssertFalse(window.isKeyWindow)

        if let marker = ProcessInfo.processInfo.environment["TING_SETTINGS_SEARCH_REVIEW"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(atPath: marker) }
            let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")))
            window.appearance = NSAppearance(named: .aqua)
            window.title = "Ting Settings Review"
            window.setContent(ChromeWindow.hosting(SettingsRoot(page: .clipbawd, query: "days")
                .environment(model).environment(\.colorScheme, .light)))
            window.setContentSize(ChromeMetrics.windowSize(forBody: NSSize(width: 1040, height: 720)))
            window.contentView?.layoutSubtreeIfNeeded()
            window.orderBack(nil)
            XCTAssertTrue(window.closeButton.isEnabled)
            try JSONSerialization.data(withJSONObject: ["window": window.windowNumber]).write(to: URL(fileURLWithPath: marker))
            let deadline = Date().addingTimeInterval(120)
            while window.isVisible, FileManager.default.fileExists(atPath: marker), Date() < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
