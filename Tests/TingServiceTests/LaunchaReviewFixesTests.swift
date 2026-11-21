import AppKit
import XCTest
import TingCore
import BobukSystem
import BobukUI
@testable import Ting

@MainActor
private final class FakeRecorder: HotkeyRecordingOwner {
    let gate: HotkeyRecordingGate
    private(set) var isRecording = false
    private(set) var cancels = 0

    init(gate: HotkeyRecordingGate) { self.gate = gate }

    func start() {
        isRecording = true
        gate.begin(self)
    }

    func cancel() {
        cancels += 1
        guard isRecording else { return }
        isRecording = false
        gate.end(self)
    }
}

@MainActor
final class HotkeyRecordingGateTests: XCTestCase {
    func testSecondRecordingCancelsFirstAndKeepsHotkeysOff() {
        var changes: [Bool] = []
        let gate = HotkeyRecordingGate { changes.append($0) }
        let leader = FakeRecorder(gate: gate)
        let launcha = FakeRecorder(gate: gate)

        leader.start()
        XCTAssertEqual(changes, [true])
        launcha.start()
        // The first recording stopped; the hotkeys never came back on in between.
        XCTAssertFalse(leader.isRecording)
        XCTAssertTrue(gate.isActive)
        XCTAssertEqual(changes, [true])

        // A late cancel of the old recorder does nothing.
        leader.cancel()
        XCTAssertTrue(gate.isActive)
        XCTAssertEqual(changes, [true])

        launcha.cancel()
        XCTAssertFalse(gate.isActive)
        XCTAssertEqual(changes, [true, false])
    }

    func testEndFromNonOwnerIsIgnored() {
        var changes: [Bool] = []
        let gate = HotkeyRecordingGate { changes.append($0) }
        let owner = FakeRecorder(gate: gate)
        let other = FakeRecorder(gate: gate)
        owner.start()
        gate.end(other)
        XCTAssertTrue(gate.isActive)
        gate.end(owner)
        gate.end(owner)
        XCTAssertFalse(gate.isActive)
        XCTAssertEqual(changes, [true, false])
    }

    func testRestartBySameOwnerDoesNotCancelItself() {
        var changes: [Bool] = []
        let gate = HotkeyRecordingGate { changes.append($0) }
        let owner = FakeRecorder(gate: gate)
        owner.start()
        owner.start()
        XCTAssertEqual(owner.cancels, 0)
        XCTAssertEqual(changes, [true])
    }

    func testDeallocatedOwnerDoesNotLeaveHotkeysOffForever() {
        var changes: [Bool] = []
        let gate = HotkeyRecordingGate { changes.append($0) }
        var owner: FakeRecorder? = FakeRecorder(gate: gate)
        owner?.start()
        owner = nil
        let next = FakeRecorder(gate: gate)
        next.start()
        next.cancel()
        XCTAssertFalse(gate.isActive)
        XCTAssertEqual(changes, [true, false])
    }
}

/// launcha's ⌘ keys: BobukPanel's `EditCommand` routing plus launcha's own ⇧⌘K and ⌘↩.
@MainActor
final class LaunchaPanelKeyRouteTests: XCTestCase {
    enum Route: Equatable {
        case notCommand, editor, text(Selector), close, swallow
        case launcha(LaunchaPanel.Command)
    }

    /// What the panel does with a key: launcha's command first, then BobukPanel's routing.
    private func route(_ keyCode: UInt16, _ latin: String? = nil, _ flags: NSEvent.ModifierFlags) -> Route {
        let command = EditCommand.classify(keyCode: keyCode, latin: latin, flags: flags)
        if let own = LaunchaPanel.command(command, latin: latin, flags: flags) { return .launcha(own) }
        switch command {
        case .notCommand: return .notCommand
        case .editor: return .editor
        case .text(let selector): return .text(selector)
        case .close: return .close
        case .commandReturn, .other: return .swallow
        }
    }

    func testCommandArrowsAndDeletesGoToTheEditor() {
        let editing: [UInt16] = [VirtualKey.delete, VirtualKey.forwardDelete, VirtualKey.left, VirtualKey.right,
                                 VirtualKey.down, VirtualKey.up]
        let combos: [NSEvent.ModifierFlags] = [.command, [.command, .shift], [.command, .option],
                                               [.command, .shift, .option]]
        for keyCode in editing {
            for flags in combos {
                XCTAssertEqual(route(keyCode, nil, flags), .editor, "key \(keyCode) flags \(flags)")
            }
        }
    }

    func testPlainEditingIsNotTouched() {
        XCTAssertEqual(route(0, "a", []), .notCommand)
        XCTAssertEqual(route(VirtualKey.delete, nil, []), .notCommand)
        XCTAssertEqual(route(VirtualKey.left, nil, .shift), .notCommand)
        XCTAssertEqual(route(VirtualKey.delete, nil, .option), .notCommand)
    }

    func testTextCommandsAndReveal() {
        XCTAssertEqual(route(9, "v", .command), .text(#selector(NSText.paste(_:))))
        XCTAssertEqual(route(6, "z", [.command, .shift]), .text(NSSelectorFromString("redo:")))
        XCTAssertEqual(route(VirtualKey.returnKey, nil, .command), .launcha(.reveal))
        XCTAssertEqual(route(VirtualKey.keypadEnter, nil, .command), .launcha(.reveal))
        XCTAssertEqual(route(VirtualKey.returnKey, nil, [.command, .shift]), .swallow)
    }

    func testShortcutCommandUsesPhysicalLatinKey() {
        XCTAssertEqual(route(40, "k", [.command, .shift]), .launcha(.editShortcut))
        XCTAssertEqual(route(40, "k", .command), .swallow)
    }

    func testAppCommandsAreSwallowedAndCommandWCloses() {
        XCTAssertEqual(route(12, "q", .command), .swallow)
        XCTAssertEqual(route(13, "w", .command), .close)
        XCTAssertEqual(route(4, "h", .command), .swallow)
    }

    func testCommandCommaOpensSettings() {
        XCTAssertEqual(route(43, ",", .command), .launcha(.settings))
        // Only plain ⌘,: other modifiers stay swallowed.
        XCTAssertEqual(route(43, ",", [.command, .shift]), .swallow)
        XCTAssertEqual(route(43, ",", [.command, .option]), .swallow)
    }

    /// The real panel: key equivalents reach launcha's callbacks or are swallowed. The panel is
    /// never shown and no event is posted to the system.
    func testPanelDeliversItsCommandsAndSwallowsTheRest() throws {
        _ = NSApplication.shared
        let panel = LaunchaPanel()
        var reveals = 0
        var edits = 0
        var settings = 0
        var dismissals: [BobukPanel.DismissReason] = []
        panel.onReveal = { reveals += 1 }
        panel.onEditShortcut = { edits += 1 }
        panel.onOpenSettings = { settings += 1 }
        panel.onDismiss = { dismissals.append($0) }
        func key(_ code: UInt16, _ text: String, _ flags: NSEvent.ModifierFlags, repeat isARepeat: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: panel.windowNumber, context: nil, characters: text,
                                           charactersIgnoringModifiers: text, isARepeat: isARepeat, keyCode: code))
        }
        XCTAssertTrue(panel.performKeyEquivalent(with: try key(VirtualKey.returnKey, "\r", .command)))
        XCTAssertTrue(panel.performKeyEquivalent(with: try key(KeyCodes.code(for: "k")!, "k", [.command, .shift])))
        XCTAssertTrue(panel.performKeyEquivalent(with: try key(KeyCodes.code(for: ",")!, ",", .command)))
        XCTAssertTrue(panel.performKeyEquivalent(with: try key(KeyCodes.code(for: ",")!, ",", .command, repeat: true)))
        XCTAssertTrue(panel.performKeyEquivalent(with: try key(KeyCodes.code(for: "q")!, "q", .command)))
        XCTAssertFalse(panel.performKeyEquivalent(with: try key(VirtualKey.left, "", .command)), "the field moves to the line start")
        XCTAssertEqual(reveals, 1)
        XCTAssertEqual(edits, 1)
        XCTAssertEqual(settings, 1)
        XCTAssertEqual(dismissals, [])
        XCTAssertTrue(panel.performKeyEquivalent(with: try key(KeyCodes.code(for: "w")!, "w", .command)))
        XCTAssertEqual(dismissals, [.commandW])
        XCTAssertFalse(panel.isVisible)
    }
}

@MainActor
final class LeaderTokenLabelTests: XCTestCase {
    func testDefaultLabelsNameTheKeyAndDoubleTap() {
        XCTAssertEqual(LeaderToken.label(leader: "⌥Space", taps: 1, description: nil), "Leader key ⌥Space")
        XCTAssertEqual(LeaderToken.label(leader: "⌥Space", taps: 2, description: nil), "Leader key ⌥Space, pressed twice")
        XCTAssertEqual(LeaderToken.label(leader: "", taps: 1, description: nil), "Leader key")
        XCTAssertEqual(LeaderToken.label(leader: "⌥Space", taps: 2, description: "Open launcha"), "Open launcha")
    }

    func testLaunchaDescriptionNamesTheRealKeys() {
        var config = Config()
        XCTAssertEqual(LaunchaController.tokenDescription(config), "Open launcha")
        config.leader = .combo(keyCode: 49, modifiers: [.option])
        let leader = config.leader!.display
        XCTAssertEqual(LaunchaController.tokenDescription(config), "Open launcha: \(leader) pressed twice")
        config.launcha.hotkey = .combo(keyCode: 40, modifiers: [.command])
        let hotkey = config.launcha.hotkey!.display
        XCTAssertEqual(LaunchaController.tokenDescription(config),
                       "Open launcha: \(leader) pressed twice, or \(hotkey)")
        config.launcha.doubleTap = false
        XCTAssertEqual(LaunchaController.tokenDescription(config), "Open launcha: \(hotkey)")
    }
}
