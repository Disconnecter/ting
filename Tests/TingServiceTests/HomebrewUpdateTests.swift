import Foundation
import Testing
import TingCore
@testable import Ting

/// The runner and the updater choice of the app. `brew` and `open` are fake scripts in a temporary
/// folder: no test runs the real Homebrew, touches /Applications or opens an app.
@MainActor
@Suite(.serialized) struct HomebrewUpdateTests {
    private let root: URL
    private let fm = FileManager.default

    init() throws {
        root = fm.temporaryDirectory.appendingPathComponent("ting-brew-run-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func script(_ path: String, _ body: String) throws -> URL {
        let file = root.appendingPathComponent(path)
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n\(body)\n".write(to: file, atomically: false, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    /// A Homebrew prefix whose fake `brew` records its arguments and then runs `body`.
    private func install(brew body: String) throws -> HomebrewInstall {
        let prefix = root.appendingPathComponent("prefix")
        let calls = root.appendingPathComponent("brew-calls").path
        _ = try script("prefix/bin/brew", "printf '%s\\n' \"$*\" >> '\(calls)'\n\(body)")
        let app = root.appendingPathComponent("Applications/Ting.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let folder = prefix.appendingPathComponent("Caskroom/ting/0.7.3")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Ting.app"), withDestinationURL: app)
        return try #require(HomebrewDetection.install(of: app, prefixes: [prefix]))
    }

    private func runner(_ install: HomebrewInstall, pid: pid_t = ProcessInfo.processInfo.processIdentifier) throws -> HomebrewUpdateRunner {
        let opener = try script("bin/open", "printf '%s\\n' \"$*\" >> '\(root.appendingPathComponent("open-calls").path)'")
        return HomebrewUpdateRunner(install: install, tingPID: pid,
                                    base: root.appendingPathComponent("runs"), opener: opener, pollInterval: 0.05)
    }

    private func finish(_ runner: HomebrewUpdateRunner, output: ((String) -> Void)? = nil) async throws -> HomebrewUpdateOutcome {
        try await withCheckedThrowingContinuation { continuation in
            let started = runner.start(onOutput: { output?($0) }, onFinish: { continuation.resume(returning: $0) })
            if !started { continuation.resume(throwing: CancellationError()) }
        }
    }

    private func read(_ name: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    private func waitFor(_ name: String) async throws -> String {
        for _ in 0..<200 {
            let text = read(name)
            if !text.isEmpty { return text }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return ""
    }

    @Test func homebrewSuccessRunsOnlyTheTingCask() async throws {
        let install = try install(brew: "echo '==> Upgrading 1 outdated package:'\necho '🍺  ting was successfully upgraded!'")
        let runner = try runner(install)
        var lines = ""
        let outcome = try await finish(runner) { lines = $0 }
        #expect(outcome == .upgraded)
        #expect(read("brew-calls") == "upgrade --cask --greedy bobuk-io/tap/ting\n")
        #expect(lines.contains("successfully upgraded"))
        let directory = try #require(runner.directory)
        runner.acknowledge(relaunch: true)
        // The helper starts the installed copy again once this process is gone; here it is
        // still alive, so the opener has not run yet.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(read("open-calls").isEmpty)
        #expect(fm.fileExists(atPath: directory.appendingPathComponent("relaunch").path))
    }

    @Test func homebrewUpToDate() async throws {
        let install = try install(brew: "echo 'Warning: Not upgrading ting, the latest version is already installed' >&2")
        let runner = try runner(install)
        #expect(try await finish(runner) == .upToDate)
        runner.acknowledge(relaunch: false)
    }

    @Test func homebrewFailureKeepsTheOutput() async throws {
        let install = try install(brew: "echo 'Error: Download failed: Could not resolve host' >&2\nexit 1")
        let runner = try runner(install)
        let outcome = try await finish(runner)
        #expect(outcome == .failed(exitCode: 1, output: "Error: Download failed: Could not resolve host\n"))
        runner.acknowledge(relaunch: false)
    }

    @Test func homebrewSecondStartIsRefused() async throws {
        let install = try install(brew: "sleep 1\necho done")
        let runner = try runner(install)
        let first = Task { try await finish(runner) }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(runner.isRunning)
        #expect(!runner.start(onOutput: { _ in }, onFinish: { _ in }))
        #expect(try await first.value == .upToDate)
        #expect(read("brew-calls") == "upgrade --cask --greedy bobuk-io/tap/ting\n")
        runner.acknowledge(relaunch: false)
    }

    @Test func homebrewCancelIsNotSuccess() async throws {
        let install = try install(brew: "echo started\nsleep 5\necho '🍺  ting was successfully upgraded!'")
        let runner = try runner(install)
        let pending = Task { try await finish(runner) }
        try await Task.sleep(nanoseconds: 300_000_000)
        runner.cancel()
        let outcome = try await pending.value
        guard case .cancelled = outcome else { Issue.record("Expected a cancel, got \(outcome)"); return }
        runner.acknowledge(relaunch: false)
    }

    /// brew may stop or replace Ting while it runs: the helper outlives Ting and opens the
    /// installed copy with the log, so the result stays visible.
    @Test func homebrewHelperSurvivesTingAndReopensIt() async throws {
        let dead = Process()
        dead.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try dead.run()
        dead.waitUntilExit()
        let install = try install(brew: "echo '🍺  ting was successfully upgraded!'")
        let runner = try runner(install, pid: dead.processIdentifier)
        _ = runner.start(onOutput: { _ in }, onFinish: { _ in })
        let directory = try #require(runner.directory)
        let opened = try await waitFor("open-calls")
        #expect(opened == "\(install.app.path) --args --homebrew-update-log \(directory.path)\n")
        let log = try String(contentsOf: directory.appendingPathComponent("output.log"), encoding: .utf8)
        #expect(log.contains("successfully upgraded"))
    }

    @Test func homebrewChoiceStartsNoSparkle() throws {
        let install = try install(brew: "exit 0")
        var made = 0
        let service = UpdateService(choice: .homebrew(install), makeSparkle: { made += 1; return FakeSparkle() })
        #expect(made == 0)
        #expect(service.homebrew == install)
        #expect(!service.isAvailable)
        #expect(service.menuTitle == "Update Ting via Homebrew…")
    }

    @Test func homebrewChoiceSparkleAndNone() {
        var made = 0
        let sparkle = UpdateService(choice: .sparkle, makeSparkle: { made += 1; return FakeSparkle() })
        #expect(made == 1)
        #expect(sparkle.isAvailable)
        #expect(sparkle.homebrew == nil)
        #expect(sparkle.menuTitle == "Check for Updates…")

        let none = UpdateService(choice: .none, makeSparkle: { made += 1; return FakeSparkle() })
        #expect(made == 1)
        #expect(!none.isAvailable)
        #expect(none.menuTitle == nil)
    }
}

@MainActor
private final class FakeSparkle: SparkleUpdating {
    var automaticallyChecks = true
    var canCheck = true
    func check() {}
}
