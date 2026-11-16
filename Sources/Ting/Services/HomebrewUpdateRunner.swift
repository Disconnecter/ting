// Runs the one Homebrew command that updates Ting and reports its live output and true result.
import Foundation
import TingCore

/// Design: brew replaces Ting.app while it runs, and the running Ting may be stopped or crash on
/// its replaced files. So Ting does not own the brew process through a pipe. A small detached
/// helper script runs brew with its output in a log file and its exit code in a status file of a
/// run folder; any Ting only reads those files. The helper ignores SIGHUP and outlives Ting.
///
/// The window must stay visible while brew works, so the helper watches the process whose pid is
/// in the run folder. When that Ting is gone while brew still runs, the helper starts the installed
/// copy with `--homebrew-update-log <run folder>`; that copy writes its own pid and shows the same
/// command, the rest of the live output and the result (`watch(_:)`). After brew the helper waits
/// for a Ting to see the result. When Ting asks for a restart (success), or no Ting is there to show
/// it, the helper starts the installed copy again. "Installed copy" is looked up after brew: the
/// newest `Caskroom/ting/<version>/Ting.app`, resolved, because an upgrade removes the old version
/// folder; the old place only when no record is left.
@MainActor
final class HomebrewUpdateRunner {
    /// Nil for a copy that only watches a run that another copy started.
    let install: HomebrewInstall?
    private let tingPID: pid_t
    private let base: URL
    private let opener: URL
    private let shell: URL
    private let pollInterval: TimeInterval

    private var helper: Process?
    private var timer: Timer?
    private var onOutput: ((String) -> Void)?
    private var onFinish: ((HomebrewUpdateOutcome) -> Void)?
    private var lastOutput = ""
    /// The run folder of the current or last run.
    private(set) var directory: URL?

    init(install: HomebrewInstall?, tingPID: pid_t = ProcessInfo.processInfo.processIdentifier,
         base: URL = HomebrewUpdateRunner.defaultBase,
         opener: URL = URL(fileURLWithPath: "/usr/bin/open"),
         shell: URL = URL(fileURLWithPath: "/bin/sh"), pollInterval: TimeInterval = 0.25) {
        self.install = install
        self.tingPID = tingPID
        self.base = base
        self.opener = opener
        self.shell = shell
        self.pollInterval = pollInterval
    }

    /// Per-user temporary folder; it survives the restart of Ting but holds no configuration.
    nonisolated static var defaultBase: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("io.bobuk.ting.homebrew-update")
    }

    var isRunning: Bool { timer != nil }

    /// Starts the update. Returns false, and starts nothing, while another run is in progress.
    /// A run that cannot start finishes at once with `.failed` and the reason as its output.
    @discardableResult
    func start(onOutput: @escaping (String) -> Void, onFinish: @escaping (HomebrewUpdateOutcome) -> Void) -> Bool {
        guard !isRunning else { return false }
        guard let install else {
            onFinish(.failed(exitCode: -1, output: "Homebrew does not manage this copy of Ting."))
            return true
        }
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
            try String(tingPID).write(to: folder.appendingPathComponent("pid"), atomically: false, encoding: .utf8)
        } catch {
            onFinish(.failed(exitCode: -1, output: "Could not prepare the update in \(folder.path): \(error.localizedDescription)"))
            return true
        }
        let process = Process()
        process.executableURL = shell
        process.arguments = [script.path, folder.path, install.app.path,
                             install.prefix.appendingPathComponent("Caskroom/\(HomebrewDetection.cask)").path,
                             opener.path, install.brew.path] + HomebrewUpdate.arguments
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
            onFinish(.failed(exitCode: -1, output: "Could not start the update helper \(shell.path): \(error.localizedDescription)"))
            return true
        }
        helper = process
        begin(folder, onOutput: onOutput, onFinish: onFinish)
        return true
    }

    /// Shows a run that another copy of Ting started (`--homebrew-update-log`): this process takes
    /// over as the one the helper waits for. Returns false while a run is in progress here.
    @discardableResult
    func watch(_ folder: URL, onOutput: @escaping (String) -> Void,
               onFinish: @escaping (HomebrewUpdateOutcome) -> Void) -> Bool {
        guard !isRunning else { return false }
        try? String(tingPID).write(to: folder.appendingPathComponent("pid"), atomically: false, encoding: .utf8)
        begin(folder, onOutput: onOutput, onFinish: onFinish)
        return true
    }

    private func begin(_ folder: URL, onOutput: @escaping (String) -> Void,
                       onFinish: @escaping (HomebrewUpdateOutcome) -> Void) {
        directory = folder
        lastOutput = ""
        self.onOutput = onOutput
        self.onFinish = onFinish
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    /// Stops brew. The result is a cancel, never a success. A watching copy has no helper of its
    /// own; it asks the helper through the run folder.
    func cancel() {
        guard isRunning, let directory else { return }
        if let helper, helper.isRunning {
            helper.terminate()
        } else {
            try? Data().write(to: directory.appendingPathComponent("cancel"))
        }
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
        guard let directory, isRunning else { return }
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

    /// Arguments: run folder, installed app, Caskroom folder of the cask, opener, then brew and its
    /// arguments. The command itself comes from `HomebrewUpdate.arguments`, never from this text.
    /// The pid of the Ting that shows the window is in `<run folder>/pid`.
    static let helperScript = #"""
    #!/bin/sh
    dir=$1; app=$2; caskroom=$3; opener=$4; shift 4
    trap '' HUP
    alive() { p=$(cat "$dir/pid" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
    target() {
      found=""
      for v in $(ls "$caskroom" 2>/dev/null | sort -V); do
        r="$caskroom/$v/Ting.app"
        [ -d "$r" ] && found=$(cd -P "$r" 2>/dev/null && pwd -P)
      done
      [ -z "$found" ] && [ -d "$app" ] && found=$app
      [ -n "$found" ] && printf '%s\n' "$found"
    }
    reopen() {
      t=$(target) || return 1
      [ -n "$t" ] || return 1
      rm -f "$dir/pid"
      "$opener" "$t" --args --homebrew-update-log "$dir"
    }
    "$@" >"$dir/output.log" 2>&1 </dev/null &
    child=$!
    trap ': >"$dir/cancelled"; kill -TERM "$child" 2>/dev/null' TERM INT
    last=0
    while kill -0 "$child" 2>/dev/null; do
      if [ -e "$dir/cancel" ] && [ ! -e "$dir/cancelled" ]; then : >"$dir/cancelled"; kill -TERM "$child" 2>/dev/null; fi
      if ! alive; then
        now=$(date +%s)
        if [ $((now - last)) -ge 10 ] && reopen; then last=$now; fi
      fi
      sleep 0.2
    done
    wait "$child"; code=$?
    printf '%s\n' "$code" >"$dir/status.tmp" && mv "$dir/status.tmp" "$dir/status"
    trap '' TERM INT
    gone=0
    while [ ! -e "$dir/handled" ] && [ "$gone" -lt 50 ]; do
      if alive; then gone=0; else gone=$((gone + 1)); fi
      sleep 0.2
    done
    if [ -e "$dir/handled" ] && [ ! -e "$dir/relaunch" ]; then exit 0; fi
    while alive; do sleep 0.2; done
    reopen
    """#
}
