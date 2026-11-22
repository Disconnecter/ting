import BobukCore
import Foundation
import TingCore

/// Resolved parameters for a headless `chatta:` micro-app step.
package struct MicroAppChattaRequest: Equatable, Sendable {
    package var prompt: String
    package var system: String?
    package var agent: String?
    package var model: String?
    package var effort: String?
    package var access: MicroAppStep.ChattaStep.Access
    package var cwd: String?
    package var workingDirectory: String
    package var timeout: TimeInterval
    package var environment: [String: String]

    package init(prompt: String, system: String? = nil, agent: String? = nil, model: String? = nil,
                 effort: String? = nil, access: MicroAppStep.ChattaStep.Access = .text, cwd: String? = nil,
                 workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
                 timeout: TimeInterval = MicroAppRunRules.timeLimit,
                 environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.prompt = prompt
        self.system = system
        self.agent = agent
        self.model = model
        self.effort = effort
        self.access = access
        self.cwd = cwd
        self.workingDirectory = workingDirectory
        self.timeout = timeout
        self.environment = environment
    }
}

/// Runs headless one-shot ACP calls for `chatta:` micro-app steps.
package enum MicroAppChatta {
    package static func run(
        _ request: MicroAppChattaRequest,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let preset: ACPAgentPreset
        if let id = request.agent?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            guard let named = ACPAgentPreset.named(id) else {
                throw MicroAppServiceError("unknown Chatta agent `\(id)`")
            }
            preset = named
        } else {
            let installed = ACPAgentPreset.detectInstalled(environment: request.environment).map(\.preset)
            guard let first = installed.first else {
                throw MicroAppServiceError("no ACP agent is installed; install one (e.g. agy, codex-acp, claude-agent-acp, gemini or opencode)")
            }
            preset = first
        }

        let effort: String?
        if let raw = request.effort?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let lowered = raw.lowercased()
            guard ChattaSettings.effortChoices.contains(lowered) else {
                throw MicroAppServiceError("chatta effort `\(raw)` must be one of: \(ChattaSettings.effortChoices.joined(separator: ", "))")
            }
            effort = lowered
        } else {
            effort = nil
        }

        let model = request.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = model.flatMap { $0.isEmpty ? nil : $0 }

        let policy: ACPAccessPolicy
        let directory: URL
        switch request.access {
        case .text:
            policy = .textOnly
            directory = FileManager.default.temporaryDirectory
        case .read:
            policy = .workspace(allowWrite: false, autoApproveTools: true)
            directory = try resolveDirectory(cwd: request.cwd, workingDirectory: request.workingDirectory)
        case .write:
            policy = .workspace(allowWrite: true, autoApproveTools: true)
            directory = try resolveDirectory(cwd: request.cwd, workingDirectory: request.workingDirectory)
        }

        let fullPrompt = ChattaPrompt.composeStepPrompt(system: request.system, prompt: request.prompt)
        let turnSeconds = max(1, Int(request.timeout.rounded(.up)))
        let options = ACPPromptOptions(
            model: resolvedModel,
            effort: effort,
            sandboxed: true,
            access: policy,
            requestTimeout: .seconds(min(25, turnSeconds)),
            turnTimeout: .seconds(turnSeconds)
        )

        let response = try await preset.ask(
            fullPrompt,
            in: directory,
            options: options,
            clientName: "ting",
            environment: request.environment,
            onChunk: onChunk
        )
        if response.stopReason == "cancelled" {
            throw CancellationError()
        }
        guard response.stopReason == "end_turn" else {
            throw MicroAppServiceError("Chatta stopped early (\(response.stopReason))")
        }
        return response.text
    }

    package static func resolveDirectory(cwd: String?, workingDirectory: String) throws -> URL {
        let base = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        let target: URL
        if let raw = cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            if (expanded as NSString).isAbsolutePath {
                target = URL(fileURLWithPath: expanded, isDirectory: true)
            } else {
                target = base.appendingPathComponent(expanded, isDirectory: true)
            }
        } else {
            target = base
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MicroAppServiceError("chatta directory does not exist: \(target.path)")
        }
        return target.standardizedFileURL
    }
}
