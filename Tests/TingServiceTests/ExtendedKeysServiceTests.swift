import AppKit
import BobukSystem
import XCTest
import TingCore
@testable import Ting

/// Stands in for `HIDKeyMonitor`: tests never read the keyboards or ask for Input Monitoring.
@MainActor
final class FakeExtendedKeys: ExtendedKeySource {
    var problem: String? { didSet { onProblemChange?() } }
    var onKey: ((ExtendedKeyEvent) -> Void)?
    var onProblemChange: (() -> Void)?

    func tap(_ name: String, _ modifiers: ModifierSet = []) {
        let code = KeyCodes.extended[name]!
        onKey?(ExtendedKeyEvent(keyCode: code, pressed: true, modifiers: modifiers))
        onKey?(ExtendedKeyEvent(keyCode: code, pressed: false, modifiers: modifiers))
    }
}

@MainActor
final class ExtendedKeysServiceTests: XCTestCase {
    private var made = 0

    private func model(_ source: FakeExtendedKeys) throws -> (AppModel, HotkeyService) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-extended-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        let service = HotkeyService(register: { _, _ in .active })
        let model = AppModel(presentsWindows: false, store: store, hotkeys: service,
                             extendedKeys: { [unowned self] in self.made += 1; return source })
        service.onPress = { [weak model] in model?.hotkeyPressed($0, at: $1) }
        service.onRelease = { [weak model] in model?.hotkeyReleased($0) }
        service.onUnclaimedExtendedKey = { [weak model] in model?.extendedKeyUnclaimed($0) }
        return (model, service)
    }

    func testTheOptionOwnsTheReader() throws {
        let source = FakeExtendedKeys()
        let (model, service) = try model(source)
        model.update { $0.leader = Hotkey(string: "stop") }
        XCTAssertEqual(made, 0)
        XCTAssertEqual(service.status(.leader), .failed(GlobalHotkeyCenter.extendedKeysOff("Stop")))
        model.update { $0.extendedKeys = true }
        XCTAssertEqual(made, 1)
        XCTAssertEqual(service.status(.leader), .active)
        source.problem = HIDKeyMonitor.deniedProblem
        XCTAssertEqual(service.status(.leader), .failed(HIDKeyMonitor.deniedProblem))
        source.problem = nil
        model.update { $0.extendedKeys = false }
        XCTAssertNil(source.onKey)
        XCTAssertEqual(service.status(.leader), .failed(GlobalHotkeyCenter.extendedKeysOff("Stop")))
        model.update { $0.extendedKeys = true }
        XCTAssertEqual(made, 2)
    }

    func testExtendedLeaderAndMenuKeys() throws {
        let source = FakeExtendedKeys()
        let (model, _) = try model(source)
        model.update {
            $0.extendedKeys = true
            $0.leader = Hotkey(string: "stop")
            $0.items = [.group("again", "Again", [.group("copy", "Copy", [.url("[", "Bracket", "https://example.com")])])]
        }
        XCTAssertFalse(model.leader.isOpen)
        // A key in the menu is ignored while the menu is closed.
        source.tap("again")
        XCTAssertFalse(model.leader.isOpen)
        source.tap("stop")
        XCTAssertTrue(model.leader.isOpen)
        source.tap("again")
        XCTAssertEqual(model.leader.session.path, ["again"])
        // ⌘ and ⌃ combinations are not menu keys.
        source.tap("copy", .command)
        XCTAssertEqual(model.leader.session.path, ["again"])
        source.tap("copy", .shift)
        XCTAssertEqual(model.leader.session.path, ["again", "copy"])
        // The leader closes the menu again.
        source.tap("stop")
        XCTAssertFalse(model.leader.isOpen)
    }

    func testARecorderTakesUnclaimedKeysFirst() throws {
        let source = FakeExtendedKeys()
        let (model, _) = try model(source)
        model.update {
            $0.extendedKeys = true
            $0.leader = Hotkey(string: "cmd+stop")
            $0.items = [.group("again", "Again", [])]
        }
        let owner = NSObject()
        var recorded: [Hotkey] = []
        model.listenForExtendedKeys(owner) { if $0.pressed { recorded.append($0.hotkey) } }
        source.tap("again", .shift)
        // A hotkey still wins over the recorder.
        source.tap("stop", .command)
        XCTAssertEqual(recorded, [Hotkey(string: "shift+again")])
        XCTAssertTrue(model.leader.isOpen)
        // Another owner cannot stop the listener.
        model.stopListeningForExtendedKeys(NSObject())
        source.tap("again")
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(model.leader.session.path, [])
        model.stopListeningForExtendedKeys(owner)
        source.tap("again")
        XCTAssertEqual(model.leader.session.path, ["again"])
    }
}
