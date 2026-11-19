import AppKit
import SwiftUI
import XCTest
import TingCore
@testable import Ting

@MainActor
final class SettingsVisualDesignTests: XCTestCase {
    func testReadablePagesAndDisclosuresAtMinimumSize() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")))
        let variants: [(SettingsPage, String?)] = SettingsPage.allCases.map { ($0, nil) }
            + [(.clipbawd, "storage"), (.clipbawd, "privacy")]
        for dark in [false, true] {
            for (page, target) in variants {
                let hosting = NSHostingView(rootView: SettingsRoot(page: page, target: target)
                    .environment(model).environment(\.colorScheme, dark ? .dark : .light))
                let size = NSSize(width: 900, height: 600)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = hosting
                window.setContentSize(size)
                hosting.setFrameSize(size)
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
                XCTAssertEqual(hosting.bounds.width, size.width, accuracy: 0.5)
                // NavigationSplitView installs native toolbar chrome inside NSHostingView.
                let chrome = window.frame.height - window.contentLayoutRect.height
                XCTAssertGreaterThanOrEqual(hosting.bounds.height, size.height)
                XCTAssertLessThanOrEqual(hosting.bounds.height, size.height + chrome)
                XCTAssertFalse(window.isKeyWindow)
                if let path = ProcessInfo.processInfo.environment["TING_SETTINGS_PREVIEW_DIR"] {
                    let output = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    let name = "redesign-\(page.rawValue)-\(target ?? "main")-\(dark ? "dark" : "light")"
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
                }
                window.close()
            }
        }
        // Opt-in native-window review: Orca can capture system sidebar material that cacheDisplay omits.
        // The test window stays behind the user's windows and never takes keyboard focus.
        if let marker = ProcessInfo.processInfo.environment["TING_SETTINGS_LIVE_REVIEW"] {
            var windows: [NSWindow] = []
            defer {
                for window in windows { window.close() }
                try? FileManager.default.removeItem(atPath: marker)
            }
            var info = ["pid": ProcessInfo.processInfo.processIdentifier]
            for dark in [false, true] {
                let hosting = NSHostingView(rootView: SettingsRoot(page: .clipbawd).environment(model)
                    .environment(\.colorScheme, dark ? .dark : .light))
                let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1040, height: 740), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.title = "Ting Settings Review"
                window.contentView = hosting
                window.orderBack(nil)
                windows.append(window)
                info[dark ? "darkWindow" : "lightWindow"] = Int32(window.windowNumber)
            }
            try JSONSerialization.data(withJSONObject: info).write(to: URL(fileURLWithPath: marker))
            let deadline = Date().addingTimeInterval(120)
            while FileManager.default.fileExists(atPath: marker), Date() < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
            for window in windows { XCTAssertFalse(window.isKeyWindow) }
        }
    }
}
