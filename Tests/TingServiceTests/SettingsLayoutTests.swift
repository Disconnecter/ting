import AppKit
import SwiftUI
import XCTest
import TingCore
import BobukUI
@testable import Ting

@MainActor
final class SettingsLayoutTests: XCTestCase {
    func testSettingsPagesRenderWithoutShowingWindows() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")))
        let cases: [(String, SettingsRoot)] = SettingsPage.allCases.map { ($0.rawValue, SettingsRoot(page: $0)) }
            + [("search", SettingsRoot(query: "days")), ("empty-search", SettingsRoot(query: "not-a-setting"))]
        for (name, root) in cases {
            let hosting = ChromeWindow.hosting(root.environment(model))
            let size = NSSize(width: 1040, height: 720)
            let window = SettingsWindow.make(contentSize: size)
            window.isReleasedWhenClosed = false
            window.setContent(hosting)
            hosting.setFrameSize(size)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertLessThanOrEqual(hosting.fittingSize.width, size.width)
            XCTAssertLessThanOrEqual(hosting.fittingSize.height, size.height)
            XCTAssertFalse(window.isVisible)
            if let path = ProcessInfo.processInfo.environment["TING_SETTINGS_PREVIEW_DIR"] {
                let output = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("\(name).png"))
            }
            window.close()
        }
    }

    func testExpandedRetentionAndPrivacyFitMinimumWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")))
        for target in ["storage", "privacy"] {
            let hosting = ChromeWindow.hosting(SettingsRoot(page: .clipbawd, target: target).environment(model))
            let size = NSSize(width: 900, height: 600)
            let window = SettingsWindow.make(contentSize: size)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.setContent(hosting)
            window.setContentSize(ChromeMetrics.windowSize(forBody: size))
            hosting.setFrameSize(size)
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            window.orderBack(nil) // Render the actual Settings window without taking focus.
            try await Task.sleep(for: .milliseconds(200))
            hosting.layoutSubtreeIfNeeded()
            XCTAssertFalse(window.isKeyWindow)
            XCTAssertEqual(hosting.bounds.width, size.width, accuracy: 0.5)
            if let path = ProcessInfo.processInfo.environment["TING_SETTINGS_PREVIEW_DIR"], let full = window.contentView?.superview {
                let bitmap = try XCTUnwrap(full.bitmapImageRepForCachingDisplay(in: full.bounds))
                full.cacheDisplay(in: full.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appendingPathComponent("expanded-\(target).png"))
            }
        }
    }

    func testMenuGroupsSecondaryActionsAndKeepsPrimaryActions() {
        let model = AppModel(presentsWindows: false)
        let controller = StatusItemController(model: model, makesStatusItem: false, openSettings: {}, openWelcome: {})
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        XCTAssertNotNil(menu.items.first { $0.title == "Settings…" })
        XCTAssertNotNil(menu.items.first { $0.title == "Open launcha" })
        XCTAssertNotNil(menu.items.first { $0.title == "Open Chatta" })
        XCTAssertNotNil(menu.items.first { $0.title == "Pause Ting" })
        XCTAssertNil(menu.items.first { $0.title == "Open Config File" })
        XCTAssertEqual(menu.items.first { $0.title == "Tools" }?.submenu?.items.map(\.title),
                       ["Open Config File", "Configure Ting with Chatta", "Copy Agent Prompt", "Reload Config and Micro-apps"])
        XCTAssertNotNil(menu.items.first { $0.title == "Ting" }?.submenu?.items.first { $0.title == "About Ting" })
    }
}
