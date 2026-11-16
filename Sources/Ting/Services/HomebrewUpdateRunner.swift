// Runs the one Homebrew command that updates Ting and reports its live output and true result.
import Foundation
import TingCore

/// Design: brew replaces /Applications/Ting.app while it runs, and the running Ting may be stopped
/// or crash on its replaced files. So Ting does not own the brew process through a pipe. A small
/// detached helper script runs brew with its output in a log file and its exit code in a status
/// file of a run folder; Ting only reads those files. The helper ignores SIGHUP and outlives Ting.
/// After brew it waits for Ting: if Ting asks for a restart (success) or is gone without having
/// seen the result, the helper starts the installed copy again with `--homebrew-update-log <run
/// folder>`, and that copy shows the same command, output and result. So the result stays visible
/// whatever brew does to the running app.
@MainActor
final class HomebrewUpdateRunner {
    let install: HomebrewInstall
    private let tingPID: pid_t
    private let base: URL
    private let opener: URL
    private let pollInterval: TimeInterval

    private var helper: Process?
    private var timer: Timer?
    private var onOutput: ((String) -> Void)?
    private var onFinish: ((HomebrewUpdateOutcome) -> Void)?
    private var lastOutput = ""
    /// The run folder of the current or last run.
    private(set) var directory: URL?

    init(install: HomebrewInstall, tingPID: pid_t = ProcessInfo.processInfo.processIdentifier,
         base: URL = HomebrewUpdateRunner.defaultBase,
         opener: URL = URL(fileURLWithPath: "/usr/bin/open"), pollInterval: TimeInterval = 0.25) {
        self.install = install
        self.tingPID = tingPID
        self.base = base
        self.opener = opener
        self.pollInterval = pollInterval
    }

    /// Per-user temporary folder; it survives the restart of Ting but holds no configuration.
    nonisolated static var defaultBase: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("io.bobuk.ting.homebrew-update")
    }

    var isRunning: Bool { timer != nil }

    /// Starts the update. Returns false, and starts nothing, while another run is in progress.
    @discardableResult
    func start(onOutput: @escaping (String) -> Void, onFinish: @escaping (HomebrewUpdateOutcome) -> Void) -> Bool {
        guard !isRunning else { return false }
        let fm = FileManager.default
        let folder = base.appendingPathComponent(UUID().uuidString)
        let script = folder.appendingPathComponent("update.sh")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try Self.helperScript.write(to: script, atomically: false, encoding: .utf8)
            try Data().write(to: folder.appendingPathComponent("output.log"))
            try HomebrewUpdate.commandLine(for: install)
                .write(to: folder.appendingPathComponent("command"), atomically: false, encoding: .utf8)
        } catch {
            onFinish(.failed(exitCode: -1, output: "Could not prepare the update: \(error.localizedDescription)"))
            return true
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, folder.path, String(tingPID), install.app.path, opener.path,
                             install.brew.path] + HomebrewUpdate.arguments
        var environment = ProcessInfo.processInfo.environment
        // A Ting started by Finder or at login has a minimal PATH; brew needs its own prefix.
        let prefix = install.prefix.path
        environment["PATH"] = "\(prefix)/bin:\(prefix)/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        // No terminal: a password prompt (sudo) fails instead of waiting forever, and brew reports it.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            onFinish(.failed(exitCode: -1, output: "Could not start brew: \(error.localizedDescription)"))
            return true
        }
        helper = process
        directory = folder
        lastOutput = ""
        self.onOutput = onOutput
        self.onFinish = onFinish
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        return true
    }

    /// Stops brew. The result is a cancel, never a success.
    func cancel() {
        guard isRunning, let helper, helper.isRunning else { return }
        helper.terminate()
    }

    /// Tells the helper that Ting has seen the result; with `relaunch` the helper starts the
    /// installed copy again as soon as this process has quit.
    func acknowledge(relaunch: Bool) {
        guard let directory else { return }
        // Plain writes: the helper only checks that the markers exist.
        if relaunch { try? Data().write(to: directory.appendingPathComponent("relaunch")) }
        try? Data().write(to: directory.appendingPathComponent("handled"))
    }

    private func poll() {
        guard let directory else { return }
        let output = Self.output(in: directory)
        if output != lastOutput {
            lastOutput = output
            onOutput?(output)
        }
        guard let outcome = Self.outcome(in: directory) else { return }
        timer?.invalidate()
        timer = nil
        helper = nil
        let finish = onFinish
        onOutput = nil
        onFinish = nil
        finish?(outcome)
    }

    static func output(in directory: URL) -> String {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("output.log")) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The result once the helper wrote the exit code of brew; nil while brew runs.
    static func outcome(in directory: URL) -> HomebrewUpdateOutcome? {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("status"), encoding: .utf8),
              let code = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let cancelled = FileManager.default.fileExists(atPath: directory.appendingPathComponent("cancelled").path)
        return HomebrewUpdate.outcome(exitCode: code, output: output(in: directory), cancelled: cancelled)
    }

    /// Arguments: run folder, Ting's pid, installed app, opener, then brew and its arguments.
    /// The command itself comes from `HomebrewUpdate.arguments`, never from this text.
    static let helperScript = #"""
    #!/bin/sh
    dir=$1; pid=$2; app=$3; opener=$4; shift 4
    trap '' HUP
    "$@" >"$dir/output.log" 2>&1 </dev/null &
    child=$!
    trap ': >"$dir/cancelled"; kill -TERM "$child" 2>/dev/null' TERM INT
    wait "$child"; code=$?
    while kill -0 "$child" 2>/dev/null; do wait "$child"; code=$?; done
    printf '%s\n' "$code" >"$dir/status.tmp" && mv "$dir/status.tmp" "$dir/status"
    trap '' TERM INT
    while kill -0 "$pid" 2>/dev/null && [ ! -e "$dir/handled" ]; do sleep 0.2; done
    if [ -e "$dir/handled" ] && [ ! -e "$dir/relaunch" ]; then exit 0; fi
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    exec "$opener" "$app" --args --homebrew-update-log "$dir"
    """#
}
