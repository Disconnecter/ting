import XCTest
import TingCore

final class MicroShortcutTests: XCTestCase {
    private func key(_ name: String) -> Hotkey { Hotkey(string: name)! }

    func testOldConfigAndRoundTrip() throws {
        var config = try ConfigCodec.decode(Data("{}".utf8))
        XCTAssertEqual(config.microHotkeys, [])
        config = try ConfigCodec.decode(Data(#"{"microHotkeys":[{"micro":"sort-selection","hotkey":"ctrl+option+shift+cmd+x"}]}"#.utf8))
        XCTAssertEqual(config.microHotkeys, [MicroShortcut(micro: "sort-selection", hotkey: key("ctrl+option+shift+cmd+x"))])
        XCTAssertEqual(try ConfigCodec.decode(ConfigCodec.encode(config)), config)
    }

    func testReservedDuplicateAndEmptyEntriesAreDisabled() {
        var config = Config()
        config.leader = key("cmd+f12")
        config.launcha.hotkey = key("cmd+f13")
        config.microHotkeys = [MicroShortcut(micro: "a", hotkey: key("cmd+f12")),
                               MicroShortcut(micro: "b", hotkey: key("cmd+f13")),
                               MicroShortcut(micro: "c", hotkey: key("right-option")),
                               MicroShortcut(micro: " ", hotkey: key("cmd+f14")),
                               MicroShortcut(micro: "d", hotkey: key("cmd+f15")),
                               MicroShortcut(micro: "e", hotkey: key("cmd+f15")),
                               MicroShortcut(micro: "d", hotkey: key("cmd+f16"))]
        let plan = HotkeyAssignments(config)
        XCTAssertEqual(plan.micros.map(\.micro), ["d", "d"])
        XCTAssertEqual(plan.launchers[.leader], key("cmd+f12"))
        XCTAssertEqual(plan.issues.filter { $0.kind == .microHotkey }.count, 5)
    }

    func testMicroKeysWinOverAppsAndBlockTheEditor() {
        var config = Config()
        config.leader = key("home")
        config.microHotkeys = [MicroShortcut(micro: "sort", hotkey: key("cmd+f12"))]
        let app = AppShortcut(id: "app:Editor", name: "Editor", path: "/Applications/Editor.app", hotkey: key("cmd+f12"))
        config.appHotkeys = [app]
        let plan = HotkeyAssignments(config)
        XCTAssertEqual(plan.micros.map(\.micro), ["sort"])
        XCTAssertEqual(plan.applications, [])
        XCTAssertEqual(plan.issues.map(\.kind), [.appHotkey])
        config.appHotkeys = []
        XCTAssertThrowsError(try AppShortcutRules.assign(app, in: &config)) {
            XCTAssertEqual($0 as? AppShortcutRules.Problem, .micro)
        }
    }

    func testEditorRefusesTakenKeysAndKeepsOneHotkeyPerMicroInPlace() {
        var config = Config()
        config.leader = key("cmd+f12")
        config.appHotkeys = [AppShortcut(id: "app:Editor", name: "Editor", path: "/Applications/Editor.app", hotkey: key("cmd+f13"))]
        config.microHotkeys = [MicroShortcut(micro: "a", hotkey: key("cmd+f14")),
                               MicroShortcut(micro: "b", hotkey: key("cmd+f15")),
                               MicroShortcut(micro: "a", hotkey: key("cmd+f16"))]
        XCTAssertNotNil(MicroShortcutRules.problem(for: key("cmd+f12"), micro: "a", in: config))
        XCTAssertNotNil(MicroShortcutRules.problem(for: key("cmd+f13"), micro: "a", in: config))
        XCTAssertNotNil(MicroShortcutRules.problem(for: key("cmd+f15"), micro: "a", in: config))
        XCTAssertNotNil(MicroShortcutRules.problem(for: key("right-option"), micro: "a", in: config))
        XCTAssertNil(MicroShortcutRules.problem(for: key("cmd+f16"), micro: "a", in: config))

        MicroShortcutRules.assign(key("cmd+f17"), to: "a", in: &config)
        XCTAssertEqual(config.microHotkeys, [MicroShortcut(micro: "a", hotkey: key("cmd+f17")),
                                             MicroShortcut(micro: "b", hotkey: key("cmd+f15"))])
        MicroShortcutRules.assign(key("cmd+f18"), to: "c", in: &config)
        XCTAssertEqual(config.microHotkeys.last, MicroShortcut(micro: "c", hotkey: key("cmd+f18")))
        MicroShortcutRules.assign(nil, to: "a", in: &config)
        XCTAssertEqual(config.microHotkeys.map(\.micro), ["b", "c"])
    }
}
