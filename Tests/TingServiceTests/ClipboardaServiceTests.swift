import AppKit
import XCTest
import TingCore
@testable import Ting

@MainActor
private final class FakePrivacy: ClipPrivacyChecking {
    /// Answers in the order the checks run; false when none is left.
    var answers: [Bool] = []
    var asked: [String] = []
    func isPrivate(_ check: ClipPrivateWindow.Check, pid: pid_t, bundleID: String) async -> Bool {
        asked.append(bundleID)
        return answers.isEmpty ? false : answers.removeFirst()
    }
}

@MainActor
final class ClipboardaServiceTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var secure = false
    private static let editor = ClipboardMonitor.FrontApp(pid: 1, bundleID: "com.example.editor", name: "Editor")
    private var front: ClipboardMonitor.FrontApp? = editor
    private let privacy = FakePrivacy()

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.bobuk.ting.tests." + UUID().uuidString))
        secure = false
        front = Self.editor
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private func makeHistory() -> ClipboardaHistory {
        let monitor = ClipboardMonitor(pasteboard: pasteboard, frontmost: { [unowned self] in front },
                                       secureInput: { [unowned self] in secure }, privacy: privacy)
        let history = ClipboardaHistory(monitor: monitor, pasteboard: pasteboard)
        history.configure(ClipboardaSettings())
        return history
    }

    private func copy(_ text: String, extra: [String: Data] = [:]) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for (type, data) in extra { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
        pasteboard.writeObjects([item])
    }

    func testRecordsStacksAndSkipsOwnWrites() throws {
        let history = makeHistory()
        defer { history.monitor.stop() }
        copy("first")
        history.monitor.poll()
        copy("second")
        history.monitor.poll()
        copy("first")
        history.monitor.poll()
        XCTAssertEqual(history.entries.map(\.title), ["first", "second"])
        XCTAssertEqual(history.entries[0].copyCount, 2)
        XCTAssertEqual(history.entries[0].source, ClipSource(bundleID: "com.example.editor", name: "Editor"))

        // Copy from the history: on the clipboard, moved up, not counted again.
        let second = try XCTUnwrap(history.entries.last?.id)
        XCTAssertTrue(history.copy(id: second))
        history.monitor.poll()
        XCTAssertEqual(pasteboard.string(forType: .string), "second")
        XCTAssertEqual(history.entries.map(\.title), ["second", "first"])
        XCTAssertEqual(history.entries[0].copyCount, 1)
    }

    func testPrivateContextsAreNotKept() async throws {
        let history = makeHistory()
        defer { history.monitor.stop() }
        copy("password", extra: [ClipboardTypes.concealed: Data()])
        history.monitor.poll()
        secure = true
        copy("typed in a password field")
        history.monitor.poll()
        XCTAssertTrue(history.entries.isEmpty)

        ClipboardQuiet.begin()
        secure = false
        copy("selection read by a micro-app")
        history.monitor.poll()
        ClipboardQuiet.end()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testRichTextAndRoundTrip() throws {
        let history = makeHistory()
        defer { history.monitor.stop() }
        let rtf = Data(#"{\rtf1\ansi Bold}"#.utf8)
        copy("Bold", extra: [ClipboardTypes.rtf: rtf])
        history.monitor.poll()
        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertEqual(entry.content, .text("Bold", rich: true))
        pasteboard.clearContents()
        ClipboardWriter.write(entry, to: pasteboard)
        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
        XCTAssertEqual(pasteboard.string(forType: .string), "Bold")
    }

    func testBrowserPrivateWindowIsAskedAndSkipped() async throws {
        let history = makeHistory()
        defer { history.monitor.stop() }
        front = ClipboardMonitor.FrontApp(pid: 2, bundleID: "org.mozilla.firefox", name: "Firefox")
        privacy.answers = [true, false]
        copy("private tab")
        history.monitor.poll()
        copy("normal tab")
        history.monitor.poll()
        for _ in 0..<50 where privacy.asked.count < 2 || history.entries.isEmpty { await Task.yield() }
        XCTAssertEqual(privacy.asked, ["org.mozilla.firefox", "org.mozilla.firefox"])
        XCTAssertEqual(history.entries.map(\.title), ["normal tab"])
    }

    func testFilesAndImages() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ting-clip-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: a)

        // Reading file URLs from a pasteboard makes macOS log a sandbox line in tests, so the
        // strings are given directly.
        let (files, representations) = ClipboardMonitor.files([a.absoluteString, "https://example.org", folder.absoluteString])
        XCTAssertEqual(files.map(\.name), ["a.txt", folder.lastPathComponent])
        XCTAssertEqual(files.map(\.byteCount), [5, nil])
        XCTAssertEqual(representations.count, 2)

        let image = NSImage(size: NSSize(width: 3, height: 2), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
            .representation(using: .png, properties: [:]))
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        let info = try XCTUnwrap(ClipboardMonitor.read(pasteboard).image)
        XCTAssertEqual(info.format, "PNG")
        XCTAssertEqual(info.byteCount, png.count)
        XCTAssertGreaterThan(info.width, 0)
    }

    func testDisablingForgetsAndExcludingRemoves() {
        let history = makeHistory()
        defer { history.monitor.stop() }
        copy("kept")
        history.monitor.poll()
        var settings = ClipboardaSettings()
        settings.exclude(app: "com.example.editor")
        history.configure(settings)
        XCTAssertTrue(history.entries.isEmpty)
        copy("from an excluded app")
        history.monitor.poll()
        XCTAssertTrue(history.entries.isEmpty)
        settings = ClipboardaSettings()
        history.configure(settings)
        copy("again")
        history.monitor.poll()
        XCTAssertEqual(history.entries.count, 1)
        settings.enabled = false
        history.configure(settings)
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertFalse(history.monitor.isRunning)
    }
}

@MainActor
final class ClipboardaPanelTests: XCTestCase {
    func testKeyRoutes() {
        XCTAssertEqual(ClipboardaPanel.route(keyCode: 36, latin: nil, flags: .command), .copy)
        XCTAssertEqual(ClipboardaPanel.route(keyCode: 76, latin: nil, flags: .command), .copy)
        XCTAssertEqual(ClipboardaPanel.route(keyCode: 51, latin: nil, flags: [.command, .shift]), .delete)
        XCTAssertEqual(ClipboardaPanel.route(keyCode: 51, latin: nil, flags: .command), .editor)
        XCTAssertEqual(ClipboardaPanel.route(keyCode: 51, latin: nil, flags: .option), .editor)
        XCTAssertEqual(ClipboardaPanel.route(keyCode: 9, latin: "v", flags: .command), .action(#selector(NSText.paste(_:))))
        XCTAssertEqual(ClipboardaPanel.route(keyCode: 40, latin: "k", flags: [.command, .shift]), .swallow)
        XCTAssertEqual(ClipboardaPanel.route(keyCode: 12, latin: "q", flags: .command), .swallow)
        XCTAssertEqual(ClipboardaPanel.route(keyCode: 0, latin: "a", flags: []), .editor)
    }

    private func controller() -> (ClipboardaController, ClipboardaHistory, NSPasteboard) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.bobuk.ting.tests." + UUID().uuidString))
        addTeardownBlock { pasteboard.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, frontmost: { nil }, secureInput: { false })
        let history = ClipboardaHistory(monitor: monitor, pasteboard: pasteboard)
        history.configure(ClipboardaSettings())
        addTeardownBlock { history.monitor.stop() }
        for text in ["alpha", "beta", "gamma"] {
            history.record(ClipCapture(types: [ClipboardTypes.plainText], text: text,
                                       representations: [ClipRepresentation(type: ClipboardTypes.plainText, data: Data(text.utf8))]))
        }
        return (ClipboardaController(history: history, presentsWindow: false), history, pasteboard)
    }

    func testSelectionSearchAndRemove() {
        let (controller, _, _) = controller()
        let state = controller.state
        controller.open()
        XCTAssertEqual(state.selected?.title, "gamma")
        state.move(by: 1)
        XCTAssertEqual(state.selected?.title, "beta")
        state.move(by: 8)
        XCTAssertEqual(state.selected?.title, "alpha")
        controller.removeSelected()
        XCTAssertEqual(state.results.map(\.title), ["gamma", "beta"])
        XCTAssertEqual(state.selected?.title, "beta")
        state.query = "gam"
        XCTAssertEqual(state.selected?.title, "gamma")
        controller.close()
        controller.open()
        XCTAssertEqual(state.query, "")
    }

    func testCopyPutsTheItemBackAndCloses() {
        let (controller, history, pasteboard) = controller()
        var toasts: [String] = []
        controller.onToast = { toasts.append($0) }
        controller.open()
        controller.state.move(by: 2)
        controller.choose(paste: false)
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(pasteboard.string(forType: .string), "alpha")
        XCTAssertEqual(history.entries.map(\.title), ["alpha", "gamma", "beta"])
        XCTAssertEqual(toasts, ["Copied alpha"])
        history.monitor.poll()
        XCTAssertEqual(history.entries.first?.copyCount, 1)
    }
}

@MainActor
final class ClipboardaHotkeyTests: XCTestCase {
    private func model() throws -> (AppModel, HotkeyService) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-clipboarda-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let service = HotkeyService(register: { _, _ in .active })
        let model = AppModel(presentsWindows: false, store: ConfigStore(url: directory.appendingPathComponent("config.json")),
                             hotkeys: service)
        addTeardownBlock { model.clipboarda.monitor.stop() }
        return (model, service)
    }

    func testSlotIDs() {
        XCTAssertEqual(HotkeyService.Slot(rawValue: HotkeyService.Slot.clipboarda.rawValue), .clipboarda)
        XCTAssertEqual(HotkeyService.Slot(rawValue: 3), .application(0))
    }

    func testHotkeyRegistersAndToggles() throws {
        let (model, service) = try model()
        model.update { $0.leader = Hotkey(string: "f13") }
        model.setClipboardaHotkey(Hotkey(string: "cmd+shift+v"))
        XCTAssertEqual(service.hotkey(.clipboarda), Hotkey(string: "cmd+shift+v"))
        XCTAssertEqual(model.clipboardaHotkeyStatus, .active)
        XCTAssertNil(model.clipboardaHotkeyProblem)

        model.hotkeyPressed(.clipboarda, at: 1)
        XCTAssertTrue(model.clipboardaPanel.isOpen)
        // A held key repeats: never toggles twice.
        model.hotkeyPressed(.clipboarda, at: 1.05)
        XCTAssertTrue(model.clipboardaPanel.isOpen)
        model.hotkeyReleased(.clipboarda)
        model.hotkeyPressed(.clipboarda, at: 2)
        XCTAssertFalse(model.clipboardaPanel.isOpen)

        // The same key as the leader: reported, never registered.
        model.setClipboardaHotkey(Hotkey(string: "f13"))
        XCTAssertNil(service.hotkey(.clipboarda))
        XCTAssertNotNil(model.clipboardaHotkeyProblem)
        model.setClipboardaHotkey(nil)
        XCTAssertNil(model.clipboardaHotkeyProblem)
    }

    func testTurnedOffFreesEverything() throws {
        let (model, service) = try model()
        model.setClipboardaHotkey(Hotkey(string: "cmd+shift+v"))
        XCTAssertTrue(model.clipboarda.monitor.isRunning)
        model.openClipboarda()
        XCTAssertTrue(model.clipboardaPanel.isOpen)

        model.update { $0.clipboarda.enabled = false }
        XCTAssertFalse(model.clipboardaPanel.isOpen)
        XCTAssertFalse(model.clipboarda.monitor.isRunning)
        XCTAssertNil(service.hotkey(.clipboarda))
        model.openClipboarda()
        XCTAssertFalse(model.clipboardaPanel.isOpen)
        model.hotkeyPressed(.clipboarda, at: 1)
        XCTAssertFalse(model.clipboardaPanel.isOpen)

        model.update { $0.clipboarda.enabled = true }
        XCTAssertEqual(service.hotkey(.clipboarda), Hotkey(string: "cmd+shift+v"))
        XCTAssertTrue(model.clipboarda.monitor.isRunning)
    }

    func testPausedHotkeyDoesNotOpen() throws {
        let (model, service) = try model()
        model.setClipboardaHotkey(Hotkey(string: "cmd+shift+v"))
        model.isPaused = true
        XCTAssertNil(service.hotkey(.clipboarda))
        model.openClipboarda()
        XCTAssertFalse(model.clipboardaPanel.isOpen)
    }
}
