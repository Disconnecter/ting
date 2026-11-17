import XCTest
import TingCore

final class AppShortcutTests: XCTestCase {
    private func shortcut(_ id: String, _ key: String) -> AppShortcut {
        .init(id: "app:" + id, name: id, path: "/Applications/\(id).app", hotkey: Hotkey(string: key)!)
    }

    func testOldConfigAndRoundTrip() throws {
        var config = try ConfigCodec.decode(Data("{}".utf8))
        XCTAssertEqual(config.appHotkeys, [])
        config.appHotkeys = [shortcut("Editor", "cmd+f12")]
        XCTAssertEqual(try ConfigCodec.decode(ConfigCodec.encode(config)), config)
    }

    func testAssignmentReplacesTheAppAndTheKeyButKeepsOthers() throws {
        var config = Config()
        config.appHotkeys = [shortcut("One", "cmd+f12"), shortcut("Two", "cmd+f13"), shortcut("Three", "cmd+f14")]
        try AppShortcutRules.assign(shortcut("One", "cmd+f13"), in: &config)
        XCTAssertEqual(config.appHotkeys, [shortcut("Three", "cmd+f14"), shortcut("One", "cmd+f13")])
    }

    func testReservedKeysNeverChangeExistingAssignments() throws {
        var config = Config()
        config.leader = Hotkey(string: "home")
        config.launcha.hotkey = Hotkey(string: "cmd+space")
        config.appHotkeys = [shortcut("Editor", "cmd+f12")]
        let original = config
        for key in ["home", "cmd+space", "right-option"] {
            XCTAssertThrowsError(try AppShortcutRules.assign(shortcut("Editor", key), in: &config))
            XCTAssertEqual(config, original)
        }
    }

    func testImportedConflictsCannotTakeProtectedKeys() {
        var config = Config()
        config.leader = Hotkey(string: "cmd+f12")
        config.launcha.hotkey = Hotkey(string: "cmd+f13")
        config.appHotkeys = [shortcut("Leader", "cmd+f12"), shortcut("Launcha", "cmd+f13"),
                             shortcut("Editor", "cmd+f14"), shortcut("Other", "cmd+f14"),
                             shortcut("Editor", "cmd+f15")]
        XCTAssertEqual(AppShortcutRules.active(in: config), [shortcut("Editor", "cmd+f14")])
        XCTAssertEqual(ConfigValidator.validate(config).filter { $0.kind == .appHotkey }.count, 4)
    }

    func testInvalidDuplicateDoesNotConsumeAnOtherwiseValidAppIdentity() {
        var config = Config()
        config.leader = Hotkey(string: "home")
        config.appHotkeys = [shortcut("One", "cmd+f12"), shortcut("Two", "cmd+f12"), shortcut("Two", "cmd+f13")]
        XCTAssertEqual(AppShortcutRules.active(in: config).map(\.id), ["app:One", "app:Two"])
        XCTAssertEqual(ConfigValidator.validate(config).filter { $0.kind == .appHotkey }.count, 1)
    }

    func testInvalidTargetAndModifierAreNeverActivated() throws {
        var config = Config()
        var invalid = shortcut("Editor", "cmd+f12")
        invalid.path = "/tmp/script.sh"
        XCTAssertThrowsError(try AppShortcutRules.assign(invalid, in: &config))
        config.appHotkeys = [invalid, shortcut("Modifier", "right-option")]
        XCTAssertEqual(AppShortcutRules.active(in: config), [])
    }
}
