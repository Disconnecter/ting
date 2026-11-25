import AppKit
import XCTest
import SwiftUI
import TingCore
@testable import Ting

@MainActor
final class AppShortcutServiceTests: XCTestCase {
    private func row(_ name: String = "Editor") -> LaunchaRow {
        .init(id: "app:" + name, kind: .app(URL(fileURLWithPath: "/Applications/\(name).app")), name: name, detail: "")
    }

    private func model(register: @escaping (Hotkey, HotkeyService.Slot) -> HotkeyService.Status = { _, _ in .active }) throws -> (AppModel, HotkeyService, ConfigStore) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-shortcuts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        let service = HotkeyService(register: register)
        let model = AppModel(presentsWindows: false, store: store, hotkeys: service)
        return (model, service, store)
    }

    private func key(_ name: String) -> Hotkey { Hotkey(string: name)! }
    private func event(_ name: String, flags: NSEvent.ModifierFlags = [.command], repeatKey: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                     isARepeat: repeatKey, keyCode: KeyCodes.code(for: name)!))
    }

    func testSaveReplacementRemovalAndProtectedKeysAreAtomic() throws {
        let (model, service, store) = try model()
        model.update { $0.leader = key("home"); $0.launcha.hotkey = key("cmd+space") }
        try model.setAppShortcut(for: row(), hotkey: key("cmd+f12"))
        try model.setAppShortcut(for: row("Other"), hotkey: key("cmd+f13"))
        try model.setAppShortcut(for: row(), hotkey: key("cmd+f13"))
        XCTAssertEqual(model.config.appHotkeys.map(\.id), [row().id])
        XCTAssertEqual(service.hotkey(.application(0)), key("cmd+f13"))
        let saved = try Data(contentsOf: store.url)
        for protected in [key("home"), key("cmd+space")] {
            XCTAssertThrowsError(try model.setAppShortcut(for: row(), hotkey: protected))
            XCTAssertEqual(try Data(contentsOf: store.url), saved)
        }
        XCTAssertEqual(service.status(.leader), .active)
        XCTAssertEqual(service.status(.launcha), .active)
        try model.setAppShortcut(for: row(), hotkey: nil)
        XCTAssertEqual(try store.load().get().appHotkeys, [])
        XCTAssertEqual(service.status(.application(0)), .inactive)
    }

    func testBothLeadersShareTheMenuAndMoveBetweenRegistrations() throws {
        let (model, service, _) = try model()
        model.update {
            $0.leader = key("home")
            $0.alternateLeader = key("cmd+f13")
        }
        service.onPress = { [weak model] in model?.hotkeyPressed($0, at: $1) }
        service.onRelease = { [weak model] in model?.hotkeyReleased($0) }
        model.leader.onDoubleTap = { [weak model] in model?.launcha.open() }
        XCTAssertEqual(HotkeyService.Slot(rawValue: HotkeyService.Slot.alternateLeader.rawValue), .alternateLeader)
        for slot in [HotkeyService.Slot.leader, .alternateLeader] {
            service.receive(slot, pressed: true, at: 1)
            XCTAssertTrue(model.leader.isOpen)
            service.receive(slot, pressed: false)
            service.receive(slot, pressed: true, at: 1.1)
            XCTAssertTrue(model.launcha.isOpen)
            XCTAssertFalse(model.leader.isOpen)
            service.receive(slot, pressed: false)
            model.launcha.close()
        }

        // A second physical key held down cannot turn repeats into a second tap.
        service.receive(.leader, pressed: true, at: 3)
        service.receive(.alternateLeader, pressed: true, at: 3.05)
        service.receive(.leader, pressed: false)
        service.receive(.alternateLeader, pressed: true, at: 3.1)
        XCTAssertTrue(model.leader.isOpen)
        service.receive(.alternateLeader, pressed: false)
        service.receive(.alternateLeader, pressed: true, at: 3.2)
        XCTAssertTrue(model.launcha.isOpen)
        service.receive(.alternateLeader, pressed: false)
        model.launcha.close()

        model.update { config in
            config.leader = key("cmd+f13")
            config.alternateLeader = key("home")
        }
        XCTAssertEqual(service.hotkey(.leader), key("cmd+f13"))
        XCTAssertEqual(service.status(.alternateLeader), .active)
        model.isPaused = true
        XCTAssertEqual(service.status(.leader), .inactive)
        XCTAssertEqual(service.status(.alternateLeader), .inactive)
        model.isPaused = false
        XCTAssertEqual(service.status(.alternateLeader), .active)
        model.update { $0.alternateLeader = nil }
        XCTAssertEqual(service.status(.alternateLeader), .inactive)
        XCTAssertEqual(service.status(.leader), .active)
    }

    func testChangingLeaderDisablesConflictingAppAndNeverStealsLeader() throws {
        let (model, service, _) = try model()
        try model.setAppShortcut(for: row(), hotkey: key("cmd+f12"))
        model.update { $0.leader = key("cmd+f12") }
        XCTAssertEqual(service.status(.leader), .active)
        XCTAssertEqual(service.status(.application(0)), .inactive)
        XCTAssertTrue(model.issues.contains { $0.kind == .appHotkey })
    }

    func testMicroHotkeysRegisterBeforeAppsAndReportOSRefusals() throws {
        let (model, service, _) = try model { hotkey, _ in
            hotkey == self.key("cmd+f14") ? .failed("Already used by another app.") : .active
        }
        XCTAssertEqual(HotkeyService.Slot(rawValue: HotkeyService.Slot.micro(2).rawValue), .micro(2))
        XCTAssertEqual(HotkeyService.Slot(rawValue: HotkeyService.Slot.application(2).rawValue), .application(2))
        try model.setAppShortcut(for: row(), hotkey: key("cmd+f12"))
        model.update {
            $0.leader = key("home")
            $0.microHotkeys = [MicroShortcut(micro: "sort", hotkey: key("cmd+f12")),
                               MicroShortcut(micro: "upper", hotkey: key("cmd+f14"))]
        }
        XCTAssertEqual(service.hotkey(.micro(0)), key("cmd+f12"))
        XCTAssertEqual(service.status(.micro(0)), .active)
        XCTAssertEqual(service.status(.application(0)), .inactive)
        XCTAssertTrue(model.issues.contains { $0.kind == .appHotkey })
        XCTAssertEqual(model.microHotkeyProblems, ["upper: Already used by another app."])
        XCTAssertTrue(model.needsAttention)
        model.isPaused = true
        XCTAssertEqual(service.status(.micro(0)), .inactive)
        model.isPaused = false
        XCTAssertEqual(service.status(.micro(0)), .active)
        model.update { $0.microHotkeys = [] }
        XCTAssertEqual(service.status(.micro(0)), .inactive)
        XCTAssertEqual(service.status(.application(0)), .active)
        XCTAssertEqual(model.microHotkeyProblems, [])
    }

    func testRecordingKeepsLaunchaOpenAndRejectsOSConflictWithoutSaving() throws {
        let (model, service, store) = try model { hotkey, _ in
            hotkey == self.key("cmd+f13") ? .failed("Already used by another app.") : .active
        }
        try model.setAppShortcut(for: row(), hotkey: key("cmd+f12"))
        let saved = try Data(contentsOf: store.url)
        model.launcha.open()
        model.launcha.editShortcut(for: row())
        let editor = try XCTUnwrap(model.launcha.chrome.shortcutEditor)
        XCTAssertTrue(model.isRecordingHotkey)
        XCTAssertTrue(model.launcha.isOpen)
        XCTAssertEqual(service.status(.application(0)), .inactive)
        editor.capture(try event("f13"))
        editor.save()
        XCTAssertNotNil(editor.warning)
        XCTAssertEqual(try Data(contentsOf: store.url), saved)
        model.launcha.close()
        XCTAssertFalse(model.isRecordingHotkey)
        XCTAssertEqual(service.status(.application(0)), .active)
    }

    func testRecorderCapturesReservedKeysAndEscapeRestoresOldBinding() throws {
        let (model, _, _) = try model()
        model.update { $0.leader = key("home"); $0.launcha.hotkey = key("cmd+space") }
        model.launcha.open()
        model.launcha.editShortcut(for: row())
        let editor = try XCTUnwrap(model.launcha.chrome.shortcutEditor)
        editor.capture(try event("home", flags: []))
        XCTAssertNotNil(editor.warning)
        editor.save()
        XCTAssertEqual(model.config.appHotkeys, [])
        editor.capture(try event("space"))
        XCTAssertNotNil(editor.warning)
        editor.capture(try event("f12"))
        XCTAssertNil(editor.warning)
        editor.save()
        XCTAssertFalse(model.isRecordingHotkey)
        XCTAssertEqual(model.config.appHotkeys.first?.hotkey, key("cmd+f12"))
        XCTAssertTrue(model.launcha.isOpen)
        model.launcha.editShortcut(for: row())
        let next = try XCTUnwrap(model.launcha.chrome.shortcutEditor)
        next.capture(try event("f13"))
        next.capture(try event("escape", flags: []))
        XCTAssertNil(model.launcha.chrome.shortcutEditor)
        XCTAssertEqual(model.config.appHotkeys.first?.hotkey, key("cmd+f12"))
        model.launcha.close()
    }

    func testFailedWriteKeepsOldAssignmentAndRecorderOpen() throws {
        let (model, _, store) = try model()
        try model.setAppShortcut(for: row(), hotkey: key("cmd+f12"))
        let saved = model.config
        try FileManager.default.removeItem(at: store.url)
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: true)
        model.launcha.open()
        model.launcha.editShortcut(for: row())
        let editor = try XCTUnwrap(model.launcha.chrome.shortcutEditor)
        editor.capture(try event("f13"))
        editor.save()
        XCTAssertNotNil(editor.warning)
        XCTAssertEqual(model.config, saved)
        XCTAssertNotNil(model.launcha.chrome.shortcutEditor)
        model.launcha.close()
    }

    func testCarbonSlotsAndHeldPresses() {
        let service = HotkeyService(register: { _, _ in .active })
        XCTAssertEqual(HotkeyService.Slot(rawValue: 3), .application(0))
        service.activate(key("cmd+f12"), for: .application(0))
        var presses = 0
        service.onPress = { _, _ in presses += 1 }
        service.receive(.application(0), pressed: true)
        service.receive(.application(0), pressed: true)
        XCTAssertEqual(presses, 1)
        service.receive(.application(0), pressed: false)
        service.receive(.application(0), pressed: true)
        XCTAssertEqual(presses, 2)
        service.apply(nil)
        service.receive(.application(0), pressed: true)
        XCTAssertEqual(presses, 2)
    }

    /// Ting's layer over BobukKit's hotkey center: role messages, status reports and releases.
    func testRoleMessagesStatusesAndReleaseOnDeactivate() {
        var reports: [(HotkeyService.Slot, HotkeyService.Status)] = []
        var registered: [HotkeyService.Slot] = []
        var released: [HotkeyService.Slot] = []
        let service = HotkeyService(register: { _, slot in registered.append(slot); return .active })
        service.onStatusChange = { reports.append(($0, $1)) }
        service.onRelease = { released.append($0) }
        XCTAssertEqual(HotkeyService.signature, 0x5449_4E47)
        service.activate(key("cmd+f12"), for: .launcha)
        XCTAssertEqual(service.status(.launcha), .active)
        service.activate(key("cmd+f12"), for: .application(0))
        XCTAssertEqual(service.status(.application(0)), .failed("\(key("cmd+f12").display) is already used for launcha."))
        XCTAssertEqual(service.hotkey(.application(0)), key("cmd+f12"))
        service.activate(key("left-cmd"), for: .leader)
        XCTAssertEqual(service.status(.leader), .failed("\(key("left-cmd").display) cannot be a leader. Choose a key that is not a modifier."))
        XCTAssertEqual(registered, [.launcha], "Ting's own refusals never reach the backend")
        XCTAssertEqual(reports.last?.0, .leader)
        service.activate(nil, for: .launcha)
        XCTAssertEqual(service.status(.launcha), .inactive)
        XCTAssertEqual(released, [.launcha], "a slot that goes off reports a release")
        service.apply(nil)
        XCTAssertEqual(service.status(.leader), .inactive)
        XCTAssertEqual(service.status(.application(0)), .inactive)
        XCTAssertNil(service.checkAvailable(key("cmd+f13")))
    }

    func testKeyboardCaptureThenReturnSavesAndTabCanReachButtons() throws {
        let editor = LaunchaShortcutEditor(row: row(), original: nil)
        var saved: Hotkey?
        editor.persist = { saved = $0 }
        XCTAssertTrue(editor.handlePanelEvent(try event("return")))
        XCTAssertEqual(editor.candidate, key("cmd+return"), "the first key can itself be Command-Return")
        XCTAssertFalse(editor.isListening)
        XCTAssertFalse(editor.handlePanelEvent(try event("tab", flags: [])))
        editor.capture(try event("return", flags: []))
        XCTAssertEqual(saved, key("cmd+return"))
        XCTAssertTrue(editor.isFinished)
    }

    func testReplacementNoticeAndRecordAgainDoNotChangeConfigUntilSave() throws {
        let (model, _, _) = try model()
        try model.setAppShortcut(for: row("Other"), hotkey: key("cmd+f12"))
        model.launcha.open()
        model.launcha.editShortcut(for: row())
        let editor = try XCTUnwrap(model.launcha.chrome.shortcutEditor)
        editor.capture(try event("f12"))
        XCTAssertEqual(editor.replacement, "Other")
        XCTAssertEqual(model.config.appHotkeys.first?.id, row("Other").id)
        editor.recordAgain()
        XCTAssertNil(editor.candidate)
        XCTAssertTrue(editor.isListening)
        editor.capture(try event("f13", repeatKey: true))
        XCTAssertNil(editor.candidate)
        model.launcha.close()
    }

    func testChangingProtectedKeysDuringRecordingIsRevalidatedOnSave() throws {
        let (model, _, _) = try model()
        model.launcha.open()
        model.launcha.editShortcut(for: row())
        let editor = try XCTUnwrap(model.launcha.chrome.shortcutEditor)
        editor.capture(try event("f12"))
        model.update { $0.launcha.hotkey = key("cmd+f12") }
        editor.save()
        XCTAssertNotNil(editor.warning)
        XCTAssertEqual(model.config.appHotkeys, [])
        model.launcha.close()
    }

    func testInlineEditorRendersWithoutAWindow() throws {
        let editor = LaunchaShortcutEditor(row: row(), original: nil)
        editor.capture(try event("f12"))
        let view = NSHostingView(rootView: LaunchaShortcutEditorView(editor: editor)
            .padding(20).frame(width: 460).foregroundStyle(Color.tingInk).background(Color.tingPanel)
            .environment(\.colorScheme, .dark))
        let size = view.fittingSize
        XCTAssertEqual(size.width, 460, accuracy: 1)
        XCTAssertGreaterThan(size.height, 160)
        XCTAssertLessThan(size.height, 360)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/ting-app-shortcut-editor.png"))
    }

    func testInjectedConfigKeepsLaunchaDataInTheTemporaryFolder() async throws {
        let (model, _, store) = try model()
        let historyURL = await model.launcha.model.historyStore.url
        XCTAssertEqual(historyURL, store.url.appendingPathExtension("launcha-history.json"))
        model.setProtectedFoldersAllowed(true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.appendingPathExtension("launcha-consent.json").path))
    }

    func testPanelRecorderConsumesCommandsWithoutRevealingOrLaunching() throws {
        _ = NSApplication.shared
        let panel = LaunchaPanel()
        let editor = LaunchaShortcutEditor(row: row(), original: nil)
        var saves = 0
        var reveals = 0
        var moves = 0
        editor.persist = { _ in saves += 1 }
        panel.onRecordShortcut = { editor.handlePanelEvent($0) }
        panel.onReveal = { reveals += 1 }
        panel.onMove = { moves += $0 }
        XCTAssertTrue(panel.performKeyEquivalent(with: try event("q")))
        XCTAssertEqual(editor.candidate, key("cmd+q"))
        panel.sendEvent(try event("down", flags: []))
        XCTAssertEqual(moves, 0)
        panel.sendEvent(try event("return", flags: []))
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(reveals, 0)
        XCTAssertFalse(panel.isVisible)
    }
}
