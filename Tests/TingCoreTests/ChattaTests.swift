import BobukCore
import Foundation
import Testing
@testable import TingCore

@Suite struct ChattaTests {
    private func decode(_ json: String) throws -> Config {
        try ConfigCodec.decode(Data(json.utf8))
    }

    @Test func settingsDefaultsRoundTripAndClamping() throws {
        let empty = try decode("{}")
        #expect(empty.chatta == ChattaSettings())
        #expect(empty.chatta.hotkey == nil)
        #expect(empty.chatta.agent == nil)
        #expect(empty.chatta.model == nil)
        #expect(empty.chatta.effort == nil)
        #expect(empty.chatta.idleTimeoutMinutes == 15)
        #expect(empty.chatta.idleTimeout == .seconds(15 * 60))
        #expect(empty.chatta.allowTools == false)

        let custom = try decode("""
        {
          "chatta": {
            "hotkey": "option+cmd+c",
            "agent": "codex",
            "model": "gpt-5",
            "effort": "HIGH",
            "idleTimeoutMinutes": 30,
            "allowTools": true
          },
          "items": [
            { "key": "c", "label": "Chatta", "open": "chatta" }
          ]
        }
        """)
        #expect(custom.chatta.hotkey == Hotkey(string: "option+cmd+c"))
        #expect(custom.chatta.agent == "codex")
        #expect(custom.chatta.model == "gpt-5")
        #expect(custom.chatta.effort == "high")
        #expect(custom.chatta.idleTimeoutMinutes == 30)
        #expect(custom.chatta.allowTools == true)
        #expect(custom.items == [.open("c", "Chatta", .chatta)])
        #expect(try ConfigCodec.decode(ConfigCodec.encode(custom)) == custom)

        // Clamping and invalid/empty normalization.
        let clamped = try decode(#"{"chatta":{"agent":"  ","model":"","effort":"turbo","idleTimeoutMinutes":-5}}"#)
        #expect(clamped.chatta.agent == nil)
        #expect(clamped.chatta.model == nil)
        #expect(clamped.chatta.effort == nil)
        #expect(clamped.chatta.idleTimeoutMinutes == 0)
        #expect(clamped.chatta.idleTimeout == nil)

        let capped = try decode(#"{"chatta":{"idleTimeoutMinutes":9999}}"#)
        #expect(capped.chatta.idleTimeoutMinutes == ChattaSettings.idleTimeoutMinutesRange.upperBound)
    }

    @Test func hotkeyConflictsAndReservation() throws {
        var config = Config()
        config.leader = Hotkey(string: "f13")
        config.chatta.hotkey = Hotkey(string: "f13")
        let conflict = ConfigValidator.validate(config)
        #expect(conflict.contains { $0.kind == .chattaHotkeyConflict })

        config.chatta.hotkey = Hotkey(string: "option+cmd+c")
        #expect(ConfigValidator.validate(config).isEmpty)
        #expect(AppShortcutRules.problem(for: Hotkey(string: "option+cmd+c")!, in: config) == .chatta)
    }

    @Test func promptPreparationAndAgentResolution() {
        let setup = { "SETUP_INSTRUCTIONS\n\nMy task: " }
        #expect(ChattaPrompt.prepare(userMessage: "hi", mode: .chat, isFirstMessage: true, setupPrompt: setup) == "hi")
        #expect(ChattaPrompt.prepare(userMessage: "add github", mode: .configure, isFirstMessage: true, setupPrompt: setup)
                == "SETUP_INSTRUCTIONS\n\nMy task: add github")
        #expect(ChattaPrompt.prepare(userMessage: "also add docs", mode: .configure, isFirstMessage: false, setupPrompt: setup)
                == "also add docs")
        #expect(ChattaPrompt.composeStepPrompt(system: "Be brief.", prompt: "Hi") == "Be brief.\n\nHi")
        #expect(ChattaPrompt.composeStepPrompt(system: "   ", prompt: "Hi") == "Hi")

        #expect(ChattaPrompt.resolveAgent(configuredID: "claude", installed: [.codex, .gemini]) == .claude)
        #expect(ChattaPrompt.resolveAgent(configuredID: nil, installed: [.codex, .gemini]) == .codex)
        #expect(ChattaPrompt.resolveAgent(configuredID: "unknown", installed: [.gemini]) == .gemini)
        #expect(ChattaPrompt.resolveAgent(configuredID: nil, installed: []) == .antigravity)

        let cfgDir = URL(fileURLWithPath: "/Users/test/.config/ting", isDirectory: true)
        let insideMicro = cfgDir.appendingPathComponent("micro", isDirectory: true)
        let resources = URL(fileURLWithPath: "/Applications/Ting.app/Contents/Resources", isDirectory: true)
        #expect(ChattaPrompt.configureAdditionalRoots(configDirectory: cfgDir, microAppsFolder: insideMicro, resourcesDirectory: resources)
                == [resources])
        let outsideMicro = URL(fileURLWithPath: "/tmp/demo.json.micro", isDirectory: true)
        #expect(ChattaPrompt.configureAdditionalRoots(configDirectory: cfgDir, microAppsFolder: outsideMicro, resourcesDirectory: resources)
                == [outsideMicro, resources])
    }

    @Test func checkerValidatesChattaMicroAppStep() throws {
        let minimal = """
        format: ting.microapp/2
        description: Summarize via Chatta.
        input: clipboard
        steps:
          - chatta: |
              Summarize:
              ${input}
        output:
          to: [panel]
        """
        let minApp = try MicroAppChecker.check(minimal, fileName: "summarize.yaml").get()
        guard case .chatta(let minStep) = minApp.steps.first?.action else {
            Issue.record("expected chatta step")
            return
        }
        #expect(minStep.agent == nil)
        #expect(minStep.model == nil)
        #expect(minStep.effort == nil)
        #expect(minStep.access == .text)
        #expect(minStep.cwd == nil)

        let full = """
        format: ting.microapp/2
        description: Review folder with Chatta.
        params:
          - name: model_name
            type: text
            required: true
        input: none
        steps:
          - chatta: Review the notes.
            agent: codex
            model: ${params.model_name}
            effort: medium
            system: Be thorough.
            access: read
            cwd: ~/Notes
        output:
          to: [panel]
        """
        let fullApp = try MicroAppChecker.check(full, fileName: "review.yaml").get()
        guard case .chatta(let fullStep) = fullApp.steps.first?.action else {
            Issue.record("expected chatta step")
            return
        }
        #expect(fullStep.agent == "codex")
        #expect(fullStep.access == .read)
        #expect(fullStep.cwd?.source == "~/Notes")

        // Invalid agent, effort, access, or cwd with access: text are rejected.
        let badCases = [
            ("unknown-agent.yaml", "format: ting.microapp/2\ndescription: x\ninput: none\nsteps:\n  - chatta: hi\n    agent: nope\n", "agent"),
            ("bad-effort.yaml", "format: ting.microapp/2\ndescription: x\ninput: none\nsteps:\n  - chatta: hi\n    effort: turbo\n", "effort"),
            ("bad-access.yaml", "format: ting.microapp/2\ndescription: x\ninput: none\nsteps:\n  - chatta: hi\n    access: root\n", "access"),
            ("cwd-text.yaml", "format: ting.microapp/2\ndescription: x\ninput: none\nsteps:\n  - chatta: hi\n    cwd: /tmp\n", "cwd"),
        ]
        for (file, yaml, fragment) in badCases {
            if case .failure(let failure) = MicroAppChecker.check(yaml, fileName: file) {
                #expect(failure.issues.contains { $0.message.contains(fragment) }, "\(file): \(failure)")
            } else {
                Issue.record("expected \(file) to fail validation")
            }
        }
    }
}
