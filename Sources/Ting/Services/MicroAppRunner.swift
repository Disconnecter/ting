// Runs a micro-app: checks its tools, then runs its command with `/bin/sh -c` in the home folder,
// with the user's PATH and the `TING_<NAME>` variables. No UI.
import Darwin
import Foundation
import TingCore

/// The PATH of the user's login shell, read with one call of the shell.
enum UserPATH {
    enum Source: Equatable, Sendable {
        case loginShell
        case fallback
    }

    /// The login shell gets this long to print its PATH.
    static let timeLimit: TimeInterval = 5

    /// The user's login shell from the user database, then `$SHELL`, then zsh.
    static func loginShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty { return shell }
        return "/bin/zsh"
    }

    /// Runs `shell` once as an interactive login shell and returns the PATH it prints. When the shell
    /// fails, is slow or prints no PATH, returns Ting's PATH with `/opt/homebrew/bin` and `/usr/local/bin`.
    static func read(shell: String = loginShell(),
                     environment: [String: String] = ProcessInfo.processInfo.environment,
                     home: String = NSHomeDirectory(),
                     timeLimit: TimeInterval = timeLimit) async -> (path: String, source: Source) {
        let request = ChildProcessRequest(executable: shell, arguments: MicroAppRunRules.pathShellArguments,
                                          environment: environment, workingDirectory: home, timeLimit: timeLimit,
                                          outputLimit: 256 * 1024)
        let outcome = await ChildProcess.run(request)
        if outcome.end == .exited(0), !outcome.stdoutCut,
           let path = MicroAppRunRules.pathFromShellOutput(String(decoding: outcome.stdout, as: UTF8.self)) {
            return (path, .loginShell)
        }
        return (MicroAppRunRules.fallbackPATH(tingPATH: environment["PATH"]), .fallback)
    }

    /// The user's PATH: the last read that `refresh` started, or a first read now.
    static func shared() async -> String {
        await UserPATHCache.shared.value()
    }

    /// Reads the PATH from the login shell again, in the background: at Ting's start and on each
    /// load of the micro-apps folder. A run that asks after the new read began waits for it.
    static func refresh() {
        Task { await UserPATHCache.shared.refresh() }
    }
}

/// Keeps the newest PATH read. A new read replaces the old one; `value` waits for the newest.
actor UserPATHCache {
    static let shared = UserPATHCache()

    private let reader: @Sendable () async -> String
    private var task: Task<String, Never>?

    init(reader: @escaping @Sendable () async -> String = { await UserPATH.read().path }) {
        self.reader = reader
    }

    func value() async -> String {
        if let task { return await task.value }
        return await refresh().value
    }

    @discardableResult
    func refresh() -> Task<String, Never> {
        let reader = self.reader
        let task = Task.detached { await reader() }
        self.task = task
        return task
    }
}

struct MicroAppRunner: Sendable {
    /// Gives the PATH for the command and the `tools` check.
    var path: @Sendable () async -> String = { await UserPATH.shared() }
    /// Ting's environment; the base of the command's environment.
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var workingDirectory: String = NSHomeDirectory()
    var timeLimit: TimeInterval = MicroAppRunRules.timeLimit
    var outputLimit: Int = MicroAppRunRules.outputLimit

    /// Runs the command as `shell -c command`.
    var shell = "/bin/sh"

    /// Runs `app` with parameter values by name and an optional stdin text.
    /// Cancelling the task stops the command and its children and gives `.cancelled`.
    func run(_ app: MicroApp, values: [String: String] = [:], stdin: String? = nil) async -> MicroAppRunResult {
        let path = await self.path()
        if let missing = app.tools.first(where: { Self.find($0, inPATH: path) == nil }) {
            return .toolNotFound(missing)
        }
        let request = ChildProcessRequest(
            executable: shell,
            arguments: ["-c", app.command],
            environment: MicroAppRunRules.environment(base: environment, path: path, params: app.params, values: values),
            workingDirectory: workingDirectory,
            stdin: Data((stdin ?? "").utf8),
            timeLimit: timeLimit,
            outputLimit: outputLimit)
        let outcome = await ChildProcess.run(request)
        let output = MicroAppRunOutput(stdout: MicroAppRunRules.text(outcome.stdout, cut: outcome.stdoutCut),
                                       stderr: MicroAppRunRules.text(outcome.stderr, cut: outcome.stderrCut),
                                       stdoutCut: outcome.stdoutCut, stderrCut: outcome.stderrCut)
        switch outcome.end {
        case .exited(0):
            var success = output
            success.stdout = MicroAppRunRules.removingEndNewlines(output.stdout)
            return .success(success)
        case .exited(let code):
            return .failure(exitCode: code, output)
        case .timedOut:
            return .timeout(output)
        case .cancelled:
            return .cancelled(output)
        case .notStarted(let code):
            var failed = output
            failed.stderr = "\(shell): \(String(cString: strerror(code)))"
            return .failure(exitCode: 127, failed)
        }
    }

    /// The first executable file named `tool` in the PATH directories, or `nil`.
    static func find(_ tool: String, inPATH path: String) -> String? {
        guard !tool.isEmpty, !tool.contains("/") else { return nil }
        for directory in MicroAppRunRules.directories(ofPATH: path) {
            let candidate = (directory as NSString).appendingPathComponent(tool)
            var info = stat()
            if stat(candidate, &info) == 0, info.st_mode & S_IFMT == S_IFREG, access(candidate, X_OK) == 0 {
                return candidate
            }
        }
        return nil
    }
}
