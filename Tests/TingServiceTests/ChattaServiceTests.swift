import AppKit
import BobukCore
import BobukUI
import Foundation
import SwiftUI
import XCTest
import TingCore
@testable import TingRuntime
@testable import Ting

@MainActor
final class ChattaServiceTests: XCTestCase {
    private func fakeAgentScript(recordingTo logFile: URL) -> String {
        """
        while IFS= read -r line; do
            case "$line" in
                *initialize*)
                    printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}'
                    ;;
                *session*new*)
                    printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"sessionId":"demo","configOptions":[]}}'
                    ;;
                *session*prompt*)
                    printf '%s\\n' "$line" >> "\(logFile.path)"
                    printf '%s\\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"demo","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Ack"}}}}'
                    printf '%s\\n' '{"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}'
                    ;;
            esac
        done
        """
    }

    func testChattaControllerModesPromptInjectionAndWindowBuild() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ting-chatta-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let promptLog = dir.appendingPathComponent("prompts.log")
        let script = fakeAgentScript(recordingTo: promptLog)
        let suite = UserDefaults(suiteName: "io.bobuk.ting.tests.chatta." + UUID().uuidString)!
        let theme = ThemeStore(defaults: suite, keys: ThemeStore.tingKeys,
                               defaultAppearance: .dark, defaultPreset: .amber, appliesToApplication: false)

        let controller = ChattaController(
            theme: theme,
            configURL: dir.appendingPathComponent("config.json"),
            microAppsFolderURL: { dir.appendingPathComponent("micro") },
            presentsWindow: false,
            setupPromptProvider: { "TING_SETUP_PREFIX: " },
            installedAgents: { [.codex] },
            customClientFactory: { _, _, _, access in
                ACPClient(
                    launch: .init(
                        executable: URL(fileURLWithPath: "/bin/bash"),
                        arguments: ["-c", script],
                        directory: dir,
                        environment: ["PATH": "/usr/bin:/bin"],
                        clientName: "ting-test",
                        isolation: .unrestricted,
                        access: access
                    ),
                    requestTimeout: .seconds(2)
                )
            }
        )
        defer { Task { await controller.shutdown() } }

        // Window prepares cleanly without showing on screen, and SwiftUI updates never resize it.
        let win = controller.prepareWindow()
        XCTAssertFalse(win.isVisible)
        XCTAssertEqual(win.title, "Chatta")
        let hosting = try XCTUnwrap(win.body.subviews.first as? NSHostingView<ChattaView>)
        XCTAssertEqual(hosting.sizingOptions, [])
        let initialSize = win.frame.size
        win.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(win.frame.size, initialSize)

        // Chat mode: auto-connects and sends raw user message without setup prefix.
        controller.open(mode: .chat)
        for _ in 0..<200 where controller.session.phase == .connecting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.session.phase, .ready)
        win.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(win.frame.size, initialSize)

        // Switching agents and reconnecting keeps the window size unchanged.
        controller.session.disconnect()
        controller.selectedAgent = .gemini
        controller.agentSelectionChanged()
        for _ in 0..<200 where controller.session.phase == .connecting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.session.phase, .ready)
        win.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(win.frame.size, initialSize)
        controller.session.draft = "plain hello"
        controller.session.send()
        for _ in 0..<200 where controller.session.phase == .replying {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.session.lastReply, "Ack")
        let chatLog = try String(contentsOf: promptLog, encoding: .utf8)
        XCTAssertTrue(chatLog.contains("plain hello"))
        XCTAssertFalse(chatLog.contains("TING_SETUP_PREFIX"))

        // Configure mode: injects setup prompt on the first turn only.
        try "".write(to: promptLog, atomically: true, encoding: .utf8)
        controller.setMode(.configure)
        for _ in 0..<200 where controller.session.phase == .connecting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.session.phase, .ready)
        controller.session.draft = "add github binding"
        controller.session.send()
        for _ in 0..<200 where controller.session.phase == .replying {
            try await Task.sleep(for: .milliseconds(10))
        }
        controller.session.draft = "second follow up"
        controller.session.send()
        for _ in 0..<200 where controller.session.phase == .replying {
            try await Task.sleep(for: .milliseconds(10))
        }
        let lines = try String(contentsOf: promptLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("TING_SETUP_PREFIX: add github binding"), lines[0])
        XCTAssertFalse(lines[1].contains("TING_SETUP_PREFIX"), lines[1])
        XCTAssertTrue(lines[1].contains("second follow up"), lines[1])

        await controller.shutdown()
    }

    func testLaunchaListsChattaAndOpensIt() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ting-launcha-chatta-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        final class DummyOpener: LaunchaOpening {
            func openApp(at url: URL, name: String) async -> LaunchOutcome { .opened }
            func openFile(_ url: URL, name: String) async -> LaunchOutcome { .opened }
            func reveal(_ url: URL) -> LaunchOutcome { .revealed }
        }
        let model = LaunchaModel(
            opener: DummyOpener(),
            historyStore: LaunchaHistoryStore(url: dir.appendingPathComponent("history.json")),
            consent: LaunchaConsentStore(url: dir.appendingPathComponent("consent.json")),
            usageStore: LaunchaHistoryStore(url: dir.appendingPathComponent("usage.json")),
            lowkeySites: { [] },
            runningAppIDs: { [] },
            makeServices: { _ in
                LaunchaModel.Services(index: LaunchaAppIndex(roots: []), spotlight: LaunchaSpotlight())
            }
        )
        var opened = false
        model.chattaEnabled = true
        model.onOpenChatta = { opened = true }
        model.open()
        model.query = "chatta"
        XCTAssertEqual(model.rows.first?.name, "Chatta")
        _ = await model.activateSelection()
        XCTAssertTrue(opened)
    }

    func testMicroAppChattaStepUsesDefaultsOverridesStreamsAndChecksEffects() async throws {
        let yaml = """
        format: ting.microapp/2
        description: Summarize with Chatta.
        input: clipboard
        steps:
          - chatta: Summarize ${input}
            system: Short answer.
        output:
          to: [panel]
        """
        let app = try MicroAppChecker.check(yaml, fileName: "sum.yaml").get()

        final class Capture: @unchecked Sendable {
            private let lock = NSLock()
            var request: MicroAppChattaRequest?
            func set(_ req: MicroAppChattaRequest) { lock.lock(); request = req; lock.unlock() }
            func get() -> MicroAppChattaRequest? { lock.lock(); defer { lock.unlock() }; return request }
        }
        let capture = Capture()
        var runner = MicroAppRunner()
        runner.path = { "/usr/bin:/bin" }
        runner.environment = [:]
        runner.chattaDefaults.agent = "claude"
        runner.chattaDefaults.model = "sonnet"
        runner.chattaDefaults.effort = "low"
        runner.chatta = { request, onChunk in
            capture.set(request)
            await onChunk("One ")
            await onChunk("two")
            return "One two"
        }

        let result = await runner.run(app, stdin: "long article")
        guard case .success(let out) = result else { return XCTFail("unexpected result: \(result)") }
        XCTAssertEqual(out.stdout, "One two")
        let seen = try XCTUnwrap(capture.get())
        XCTAssertEqual(seen.prompt, "Summarize long article")
        XCTAssertEqual(seen.system, "Short answer.")
        XCTAssertEqual(seen.agent, "claude")
        XCTAssertEqual(seen.model, "sonnet")
        XCTAssertEqual(seen.effort, "low")
        XCTAssertEqual(seen.access, .text)

        // CLI validation requires --allow-effects for access: write, but not for access: text or read.
        let writeYAML = """
        format: ting.microapp/2
        description: Edit file.
        input: none
        steps:
          - chatta: Update README
            access: write
            cwd: /tmp
        """
        let writeApp = try MicroAppChecker.check(writeYAML, fileName: "edit.yaml").get()
        XCTAssertThrowsError(try MicroAppCLI.validate(.init(file: "edit.yaml"), app: writeApp))
        XCTAssertNoThrow(try MicroAppCLI.validate(.init(file: "edit.yaml", allowEffects: true), app: writeApp))
        XCTAssertNoThrow(try MicroAppCLI.validate(.init(file: "sum.yaml"), app: app))
    }

    func testChattaZoomSavesTextScaleAndConfigReachesTheWindow() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ting-chatta-zoom-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
        let model = AppModel(presentsWindows: false, store: store)
        XCTAssertEqual(model.chatta.textScale, 1)
        XCTAssertEqual(model.chatta.sendKey, .commandReturn)

        model.chatta.zoom(by: 1)
        model.chatta.zoom(by: 1)
        XCTAssertEqual(model.chatta.textScale, 1.2, accuracy: 0.0001)
        XCTAssertEqual(model.config.chatta.textScale, 1.2, accuracy: 0.0001, "⌘+ is saved to the config")
        model.chatta.zoom(by: -1)
        XCTAssertEqual(model.config.chatta.textScale, 1.1, accuracy: 0.0001)
        model.chatta.zoom(by: nil)
        XCTAssertEqual(model.chatta.textScale, 1)
        XCTAssertEqual(model.config.chatta.textScale, 1, "⌘0 returns to 100%")
        for _ in 0..<20 { model.chatta.zoom(by: -1) }
        XCTAssertEqual(model.config.chatta.textScale, ChatTextScale.range.lowerBound)

        // Settings change the open window too.
        model.update { $0.chatta.textScale = 1.5; $0.chatta.sendKey = .return }
        XCTAssertEqual(model.chatta.textScale, 1.5)
        XCTAssertEqual(model.chatta.sendKey, .return)
        _ = model.chatta.prepareWindow()
    }

    func testChattaSettingsGearOpensChattaSettingsPage() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ting-chatta-settings-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let model = AppModel(presentsWindows: false,
                             store: ConfigStore(url: dir.appendingPathComponent("config.json")))
        var openedPages: [SettingsPage] = []
        model.settingsPageOpener = { openedPages.append($0) }

        let win = model.chatta.prepareWindow()
        XCTAssertEqual(win.strip.trailing.count, 1)
        model.chatta.openSettings()
        XCTAssertEqual(openedPages, [.chatta])

        let settings = SettingsWindowController(model: model, remembersFrame: false)
        settings.show(page: .chatta, activate: false)
        XCTAssertEqual(settings.navigation.page, .chatta)
        let firstRequestID = settings.navigation.requestID

        settings.show(page: .bindings, activate: false)
        XCTAssertEqual(settings.navigation.page, .bindings)
        XCTAssertGreaterThan(settings.navigation.requestID, firstRequestID)

        settings.close()
        settings.show(activate: false)
        XCTAssertEqual(settings.navigation.page, .general)
        settings.close()
    }

    func testChattaToolApprovalChoicesAndSessionOverride() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ting-chatta-tools-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let toolAgent = #"""
        while IFS= read -r line; do
            case "$line" in
                *initialize*)
                    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}'
                    ;;
                *session*new*)
                    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"sessionId":"demo","configOptions":[]}}'
                    ;;
                *session*prompt*)
                    printf '%s\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"demo","update":{"sessionUpdate":"tool_call","title":"web_search","status":"in_progress"}}}'
                    printf '%s\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"demo","update":{"sessionUpdate":"tool_call_update","status":"completed"}}}'
                    printf '%s\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"demo","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Searched"}}}}'
                    printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}'
                    ;;
            esac
        done
        """#

        let suite = UserDefaults(suiteName: "io.bobuk.ting.tests.chatta.tools." + UUID().uuidString)!
        let theme = ThemeStore(defaults: suite, keys: ThemeStore.tingKeys,
                               defaultAppearance: .dark, defaultPreset: .amber, appliesToApplication: false)
        var persistedAlwaysCount = 0
        var seenPolicies: [ACPAccessPolicy] = []

        let controller = ChattaController(
            theme: theme,
            configURL: dir.appendingPathComponent("config.json"),
            microAppsFolderURL: { dir.appendingPathComponent("micro") },
            presentsWindow: false,
            onAllowToolsPermanently: { persistedAlwaysCount += 1 },
            installedAgents: { [.codex] },
            customClientFactory: { _, _, _, access in
                seenPolicies.append(access)
                return ACPClient(
                    launch: .init(
                        executable: URL(fileURLWithPath: "/bin/bash"),
                        arguments: ["-c", toolAgent],
                        directory: dir,
                        environment: ["PATH": "/usr/bin:/bin"],
                        clientName: "ting-test",
                        isolation: .unrestricted,
                        access: access
                    ),
                    requestTimeout: .seconds(2)
                )
            }
        )
        defer { Task { await controller.shutdown() } }

        // Default is tools off (.textOnly).
        XCTAssertFalse(controller.effectiveAllowTools)
        controller.open(mode: .chat)
        for _ in 0..<200 where controller.session.phase == .connecting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(seenPolicies.last, .textOnly)

        // First tool attempt triggers the inline prompt instead of a fatal error.
        controller.session.draft = "Search docs"
        controller.session.send()
        for _ in 0..<200 where controller.session.phase == .replying {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.session.pendingToolApproval?.toolName, "web_search")
        XCTAssertEqual(controller.session.pendingToolApproval?.promptText, "Search docs")

        // Allow for this session: does not persist permanently, switches policy to .tools, retries automatically.
        controller.session.resolveToolApproval(.allowForSession)
        for _ in 0..<200 where controller.session.phase != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(persistedAlwaysCount, 0)
        XCTAssertTrue(controller.effectiveAllowTools)
        XCTAssertEqual(seenPolicies.last, .tools(autoApproveTools: true))
        XCTAssertEqual(controller.session.lastReply, "Searched")

        // New chat resets session-only override back to permanent setting (false).
        controller.newChat()
        for _ in 0..<200 where controller.session.phase == .connecting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(controller.effectiveAllowTools)
        XCTAssertEqual(seenPolicies.last, .textOnly)

        // Allow Always persists via callback and retries automatically.
        controller.session.draft = "Search again"
        controller.session.send()
        for _ in 0..<200 where controller.session.phase == .replying {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.session.pendingToolApproval?.toolName, "web_search")
        controller.session.resolveToolApproval(.allowAlways)
        for _ in 0..<200 where controller.session.phase != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(persistedAlwaysCount, 1)
        XCTAssertTrue(controller.allowToolsPermanently)
        XCTAssertTrue(controller.effectiveAllowTools)
        XCTAssertEqual(controller.session.lastReply, "Searched")
        await controller.shutdown()
    }

    func testChattaPersistsPreferencesAndAutoConnectsOnSend() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ting-chatta-prefs-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let agentScript = #"""
        while IFS= read -r line; do
            case "$line" in
                *initialize*)
                    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}'
                    ;;
                *session*new*)
                    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"sessionId":"demo","configOptions":[{"type":"select","category":"model","id":"model","currentValue":"m1","options":[{"value":"m1","name":"Model 1"},{"value":"m2","name":"Model 2"}]},{"type":"select","category":"reasoning_effort","id":"effort","currentValue":"medium","options":[{"value":"low","name":"Low"},{"value":"medium","name":"Medium"},{"value":"high","name":"High"}]}]}}'
                    ;;
                *set_config_option*)
                    id=$(printf '%s\n' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
                    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"configOptions\":[{\"type\":\"select\",\"category\":\"model\",\"id\":\"model\",\"currentValue\":\"m2\",\"options\":[{\"value\":\"m1\",\"name\":\"Model 1\"},{\"value\":\"m2\",\"name\":\"Model 2\"}]},{\"type\":\"select\",\"category\":\"reasoning_effort\",\"id\":\"effort\",\"currentValue\":\"high\",\"options\":[{\"value\":\"low\",\"name\":\"Low\"},{\"value\":\"medium\",\"name\":\"Medium\"},{\"value\":\"high\",\"name\":\"High\"}]}]}}"
                    ;;
                *session*prompt*)
                    id=$(printf '%s\n' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
                    printf '%s\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"demo","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Auto-connected"}}}}'
                    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"stopReason\":\"end_turn\"}}"
                    ;;
            esac
        done
        """#

        let defaultsSuiteName = "io.bobuk.ting.tests.chatta.prefs." + UUID().uuidString
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let theme = ThemeStore(defaults: defaults, keys: ThemeStore.tingKeys,
                               defaultAppearance: .dark, defaultPreset: .amber, appliesToApplication: false)
        let keys = AgentChatPreferences.StorageKeys(agentID: "a", model: "m", effort: "e")
        let prefs1 = AgentChatPreferences(defaults: defaults, keys: keys, agents: ACPAgentPreset.all, defaultAgent: .codex)

        let first = ChattaController(
            theme: theme,
            configURL: dir.appendingPathComponent("config.json"),
            microAppsFolderURL: { dir.appendingPathComponent("micro") },
            presentsWindow: false,
            preferences: prefs1,
            installedAgents: { [.codex, .gemini] },
            customClientFactory: { _, _, _, access in
                ACPClient(
                    launch: .init(
                        executable: URL(fileURLWithPath: "/bin/bash"),
                        arguments: ["-c", agentScript],
                        directory: dir,
                        environment: ["PATH": "/usr/bin:/bin"],
                        clientName: "ting-test",
                        isolation: .unrestricted,
                        access: access
                    ),
                    requestTimeout: .seconds(2)
                )
            }
        )

        // BobukKit 0.10.0 auto-connects on send from .disconnected without requiring connect() first.
        XCTAssertEqual(first.session.phase, .disconnected)
        first.selectedAgent = .gemini
        first.agentSelectionChanged()
        for _ in 0..<200 where first.session.phase == .connecting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(first.session.phase, .ready)
        first.session.selectModel("m2")
        for _ in 0..<200 where first.session.phase == .switching {
            try await Task.sleep(for: .milliseconds(10))
        }
        first.recordPreferences()
        await first.shutdown()

        // Disconnected send auto-connects and gets a reply.
        first.session.draft = "Hello offline"
        first.session.send()
        for _ in 0..<200 where first.session.phase != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(first.session.lastReply, "Auto-connected")
        await first.shutdown()

        // A fresh controller restores the last selected agent, model and effort from AgentChatPreferences.
        let prefs2 = AgentChatPreferences(defaults: defaults, keys: keys, agents: ACPAgentPreset.all, defaultAgent: .codex)
        let second = ChattaController(
            theme: theme,
            configURL: dir.appendingPathComponent("config.json"),
            microAppsFolderURL: { dir.appendingPathComponent("micro") },
            presentsWindow: false,
            preferences: prefs2,
            installedAgents: { [.codex, .gemini] }
        )
        XCTAssertEqual(second.selectedAgent, .gemini)
        XCTAssertEqual(second.session.initialModel, "m2")
        XCTAssertEqual(second.session.initialEffort, "high")
    }
}
