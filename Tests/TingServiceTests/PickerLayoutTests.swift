import AppKit
import SwiftUI
import XCTest
import TingCore
import BobukUI
@testable import Ting

@MainActor final class PickerLayoutTests: XCTestCase {
    private func render<V: View>(_ view: V, name: String, width: CGFloat) throws {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        XCTAssertEqual(size.width, width, accuracy: 0.5)
        XCTAssertGreaterThan(size.height, 100)
        XCTAssertLessThan(size.height, 640)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        hosting.setFrameSize(size)
        hosting.layoutSubtreeIfNeeded()
        func surfaces(_ view: NSView) -> [PickerSurfaceView] {
            if let surface = view as? PickerSurfaceView { return [surface] }
            return view.subviews.flatMap { surfaces($0) }
        }
        XCTAssertEqual(surfaces(hosting).count, 1)
        if let folder = ProcessInfo.processInfo.environment["BOBUKKIT_PREVIEW_DIR"] {
            let output = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("\(name).png"))
        }
        XCTAssertFalse(window.isVisible)
    }

    func testSelectaAndLaunchaUseSharedFrameAndFitTheirContent() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LeaderSession()
        session.leader = "f13"
        session.items = [.url("h", "Home Control", "https://example.com/home"),
                         .url("n", "Project Notes", "https://example.com/notes")]
        let sites = try LowkeySite.decode(Data(#"{"sites":[{"alias":"home","title":"Home Control","startURL":"https://home.example.test"},{"alias":"notes","title":"Project Notes","startURL":"https://notes.example.test"}]}"#.utf8))
        let model = LaunchaModel(opener: ActionRunner(locateLowkey: { nil }),
            historyStore: LaunchaHistoryStore(url: root.appendingPathComponent("history.json")),
            consent: LaunchaConsentStore(url: root.appendingPathComponent("consent.json")),
            home: root, lowkeySites: { sites }, makeServices: { policy in
                .init(index: LaunchaAppIndex(home: root, protectedFolders: policy, roots: []),
                      spotlight: LaunchaSpotlight(home: root, protectedFolders: policy, debounce: .zero) { _ in [] })
            })
        model.open()
        defer { model.close() }
        let chrome = LaunchaChrome()
        chrome.leader = "f13"
        let previous = NSApp.appearance
        defer { NSApp.appearance = previous }
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let theme = dark ? "dark" : "light"
            try render(LeaderMenuView(session: session, onSelect: { _ in XCTFail("Unexpected action") }, onDismiss: {}),
                       name: "ting-selecta-\(theme)", width: 340)
            try render(LaunchaView(model: model, chrome: chrome, onActivate: { _ in XCTFail("Unexpected action") }, onDismiss: {}),
                       name: "ting-launcha-\(theme)", width: 460)
        }
    }
}
