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

    /// The path with every symlink resolved, as `cd -P` in the helper gives it.
    private func real(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// A process that has already exited: a Ting that brew stopped or that crashed.
    private func deadPID() throws -> pid_t {
        let dead = Process()
        dead.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try dead.run()
        dead.waitUntilExit()
        return dead.processIdentifier
    }

    /// brew may stop or replace Ting while it runs. The helper sees that Ting is gone while brew
    /// still works and opens the installed copy at once; that copy watches the same run, gets the
    /// output that brew writes after Ting's exit and the result.
    @Test func homebrewProgressStaysVisibleAfterTingQuits() async throws {
        let install = try install(brew: "echo first\nsleep 1\necho second\necho '🍺  ting was successfully upgraded!'")
        let runner = try runner(install, pid: try deadPID())
        _ = runner.start(onOutput: { _ in }, onFinish: { _ in })
        let directory = try #require(runner.directory)
        let opened = try await waitFor("open-calls")
        #expect(opened == "\(real(install.app)) --args --homebrew-update-log \(directory.path)\n")
        // Opened while brew still runs: no result yet, and the rest of the output is still to come.
        #expect(HomebrewUpdateRunner.outcome(in: directory) == nil)
        #expect(!HomebrewUpdateRunner.output(in: directory).contains("second"))

        let watcher = HomebrewUpdateRunner(install: nil, base: root.appendingPathComponent("runs"), pollInterval: 0.05)
        var seen: [String] = []
        let outcome = try await withCheckedThrowingContinuation { continuation in
            watcher.watch(directory, onOutput: { seen.append($0) }, onFinish: { continuation.resume(returning: $0) })
        }
        #expect(outcome == .upgraded)
        #expect(seen.contains { $0.contains("second") })
        #expect(try String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)
            == String(ProcessInfo.processInfo.processIdentifier))
        watcher.acknowledge(relaunch: false)
    }

    /// The reopened copy has no helper of its own; its Cancel still stops brew, and is no success.
    @Test func homebrewWatcherCancelIsNotSuccess() async throws {
        let install = try install(brew: "echo started\nsleep 5\necho '🍺  ting was successfully upgraded!'")
        let runner = try runner(install)
        _ = runner.start(onOutput: { _ in }, onFinish: { _ in })
        let directory = try #require(runner.directory)
        let watcher = HomebrewUpdateRunner(install: nil, base: root.appendingPathComponent("runs"), pollInterval: 0.05)
        let outcome = try await withCheckedThrowingContinuation { continuation in
            watcher.watch(directory, onOutput: { _ in }, onFinish: { continuation.resume(returning: $0) })
            watcher.cancel()
        }
        guard case .cancelled = outcome else { Issue.record("Expected a cancel, got \(outcome)"); return }
        watcher.acknowledge(relaunch: false)
    }

    /// A copy that runs from the Caskroom: the upgrade removes its version folder. The restart
    /// opens the new record, not the old path.
    @Test func homebrewRestartOpensTheReplacement() async throws {
        let prefix = root.appendingPathComponent("prefix")
        let caskroom = prefix.appendingPathComponent("Caskroom/ting")
        let old = caskroom.appendingPathComponent("0.7.3/Ting.app")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        _ = try script("prefix/bin/brew", """
            rm -rf '\(caskroom.appendingPathComponent("0.7.3").path)'
            mkdir -p '\(caskroom.appendingPathComponent("0.7.4/Ting.app").path)'
            echo '🍺  ting was successfully upgraded!'
            """)
        let install = try #require(HomebrewDetection.install(of: old, prefixes: [prefix]))
        let ting = Process()
        ting.executableURL = URL(fileURLWithPath: "/bin/sleep")
        ting.arguments = ["30"]
        try ting.run()
        let runner = try runner(install, pid: ting.processIdentifier)
        #expect(try await finish(runner) == .upgraded)
        let directory = try #require(runner.directory)
        runner.acknowledge(relaunch: true)
        ting.terminate()
        ting.waitUntilExit()
        let opened = try await waitFor("open-calls")
        #expect(!fm.fileExists(atPath: old.path))
        #expect(opened == "\(real(caskroom.appendingPathComponent("0.7.4/Ting.app"))) --args --homebrew-update-log \(directory.path)\n")
    }

    /// A run that cannot start shows its reason, not an empty log.
    @Test func homebrewStartupFailuresShowTheReason() async throws {
        let install = try install(brew: "exit 0")
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let unpreparable = HomebrewUpdateRunner(install: install, base: blocker, pollInterval: 0.05)
        let unstartable = HomebrewUpdateRunner(install: install, base: root.appendingPathComponent("runs"),
                                               shell: root.appendingPathComponent("missing/sh"), pollInterval: 0.05)
        for (runner, reason) in [(unpreparable, "Could not prepare the update"), (unstartable, "Could not start the update helper")] {
            let outcome = try await finish(runner)
            guard case .failed(let code, let text) = outcome else { Issue.record("Expected a failure, got \(outcome)"); continue }
            #expect(code == -1)
            #expect(text.contains(reason))
            let model = HomebrewUpdateModel()
            model.finish(outcome, log: runner.directory.map(HomebrewUpdateRunner.output(in:)))
            #expect(model.output == text)
            #expect(model.phase == .finished(outcome))
            #expect(!model.succeeded)
        }
        #expect(read("brew-calls").isEmpty)
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
