import Darwin
import Foundation
import TingCore

/// Headless front end to the exact engine used by Ting. No config, approvals, remembered values,
/// clipboard reads/writes or panels. Naming a file with `run` explicitly authorizes its execution.
package enum MicroAppCLI {
    package static let usage = """
    Usage:
      ting-micro check [--libs DIR] FILE.yaml [FILE.yaml ...]
      ting-micro check-config [CONFIG.json]
      ting-micro run FILE.yaml [--param NAME=VALUE ...] [--input TEXT] [--timeout SECONDS] [--libs DIR] [--verbose] [--allow-effects]

    check-config reads config.json (default: $TING_CONFIG, else ~/.config/ting/config.json) and
    reports format errors, binding problems and micro bindings to ids that the micro-apps folder
    next to it does not have. It changes nothing.
    Libraries (call, inherit) come from libs/ next to FILE.yaml, or from --libs DIR.
    A file inside a folder named libs is checked as a library.

    Input: piped stdin, or --input TEXT; empty when stdin is a terminal.
    Output: the final result on stdout; diagnostics and optional step progress on stderr.
    YAML output.to is ignored: the clipboard is never read or changed.
    --allow-effects permits open and notify steps (disabled by default).
    Shell/Python and HTTP/AI steps run with your full rights and may change files or cost money.
    Environment variables come from this terminal, not a second login shell.
    No config, approvals or remembered values are read or written.

    Exit codes: 0 success, 1 script/check failure, 2 usage/input error, 124 timeout, 130 cancelled.
    """

    struct Options: Equatable {
        var file: String
        var params: [String: String] = [:]
        var input: String?
        var timeout: TimeInterval?
        var verbose = false
        var allowEffects = false
        var libs: String?
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String
        init(_ text: String) { description = text }
    }

    static func parse(_ args: [String]) throws -> Options {
        guard let file = args.first, !file.hasPrefix("-") else { throw UsageError("run needs a YAML file") }
        var options = Options(file: file)
        var i = 1
        while i < args.count {
            let flag = args[i]
            i += 1
            switch flag {
            case "--verbose": options.verbose = true
            case "--allow-effects": options.allowEffects = true
            case "--libs":
                guard i < args.count else { throw UsageError("--libs needs a folder") }
                options.libs = args[i]; i += 1
            case "--param", "--input", "--timeout":
                guard i < args.count else { throw UsageError("\(flag) needs a value") }
                let value = args[i]; i += 1
                switch flag {
                case "--param":
                    guard let eq = value.firstIndex(of: "="), eq != value.startIndex else {
                        throw UsageError("--param needs NAME=VALUE")
                    }
                    let name = String(value[..<eq])
                    guard options.params[name] == nil else { throw UsageError("duplicate parameter `\(name)`") }
                    options.params[name] = String(value[value.index(after: eq)...])
                case "--input":
                    guard options.input == nil else { throw UsageError("--input was given twice") }
                    options.input = value
                default:
                    guard let n = Int(value), (1...MicroAppChecker.maxTimeLimit).contains(n) else {
                        throw UsageError("--timeout must be from 1 to \(MicroAppChecker.maxTimeLimit) seconds")
                    }
                    options.timeout = TimeInterval(n)
                }
            default: throw UsageError("unknown option `\(flag)`")
            }
        }
        return options
    }

    static func load(_ file: String, libs: String? = nil) throws -> MicroApp {
        guard file.hasSuffix(".yaml") else { throw UsageError("a script file must end in .yaml") }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: file)) }
        catch { throw UsageError("cannot read \(file): \(error.localizedDescription)") }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: MicroAppChecker.maxFileSize + 1) ?? Data()
        guard data.count <= MicroAppChecker.maxFileSize else { throw UsageError(MicroAppChecker.tooLargeMessage) }
        guard let text = String(data: data, encoding: .utf8) else { throw UsageError(MicroAppChecker.notUTF8Message) }
        let folder = libs.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? MicroAppCheckCommand.libraryFolder(for: file)
        return try MicroAppChecker.check(text, fileName: file, libraries: MicroAppLibraries.read(folder: folder)).get()
    }

    static func validate(_ options: Options, app: MicroApp) throws {
        for name in options.params.keys.sorted() where !app.params.contains(where: { $0.name == name }) {
            throw UsageError("unknown parameter `\(name)`")
        }
        for param in app.params {
            let value = options.params[param.name] ?? param.defaultValue
            if param.required && (value == nil || value!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                throw UsageError("missing required parameter: --param \(param.name)=VALUE")
            }
            if case .choice(let choices) = param.kind, let value, !choices.contains(value) {
                throw UsageError("parameter `\(param.name)` must be one of: \(choices.joined(separator: ", "))")
            }
        }
        if !options.allowEffects, let step = app.allSteps.first(where: { $0.kind == .open || $0.kind == .notify }) {
            throw UsageError("`\(step.kind.rawValue)` requires --allow-effects; no steps were run")
        }
    }

    package static func main(_ args: [String]) async -> Int32 {
        if args.isEmpty || args == ["--help"] || args == ["-h"] {
            out(usage + "\n")
            return 0
        }
        if args.first == "check-config" {
            return checkConfig(Array(args.dropFirst()))
        }
        if args.first == "check" || args.first == "--check" {
            var files = Array(args.dropFirst())
            var libs: String?
            if let at = files.firstIndex(of: "--libs") {
                guard at + 1 < files.count else { err("ting-micro: --libs needs a folder\n"); return 2 }
                libs = files[at + 1]
                files.removeSubrange(at...(at + 1))
            }
            let report = MicroAppCheckCommand.run(files, read: { path in
                let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
                defer { try? handle.close() }
                return try handle.read(upToCount: MicroAppChecker.maxFileSize + 1) ?? Data()
            }, libraries: { path in
                MicroAppLibraries.read(folder: libs.map { URL(fileURLWithPath: $0, isDirectory: true) }
                    ?? MicroAppCheckCommand.libraryFolder(for: path))
            })
            // Uses the same checker as Ting --check, including duplicate-id validation.
            report.output.forEach { out($0 + "\n") }
            report.errors.forEach { err($0.replacingOccurrences(of: "Ting --check", with: "ting-micro check") + "\n") }
            return report.exitCode
        }
        do {
            guard args.first == "run" else { throw UsageError("expected `run` or `check`; use --help") }
            let options = try parse(Array(args.dropFirst()))
            let app = try load(options.file, libs: options.libs)
            try validate(options, app: app)
            let input: String
            if let text = options.input { input = text }
            else if isatty(STDIN_FILENO) == 0 {
                let bytes = FileHandle.standardInput.readDataToEndOfFile()
                guard let text = String(data: bytes, encoding: .utf8) else { throw UsageError("stdin is not UTF-8 text") }
                input = text
            } else { input = "" }
            var runner = MicroAppRunner()
            let environment = ProcessInfo.processInfo.environment
            let path = environment["PATH"] ?? MicroAppRunRules.defaultPATH
            runner.environment = environment
            runner.path = { path }
            runner.timeLimit = options.timeout
            // CLI runs in the current folder, like other console programs.
            runner.workingDirectory = FileManager.default.currentDirectoryPath
            let verbose = options.verbose
            let progress: (@Sendable (MicroAppRunProgress) -> Void)?
            if verbose {
                progress = { update in
                    if update.liveOutput == nil { err(update.label + "\n") }
                }
            } else { progress = nil }
            let task = Task<MicroAppRunResult, Never> {
                await runner.run(app, values: options.params, stdin: input, progress: progress)
            }
            // Dispatch signal handlers cancel the task, which stops child process groups and HTTP.
            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)
            let signals = [SIGINT, SIGTERM].map { number in
                let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
                source.setEventHandler { task.cancel() }
                source.resume()
                return source
            }
            let result = await task.value
            signals.forEach { $0.cancel() }
            return report(result)
        } catch let failure as MicroAppFailure {
            err(failure.description + "\n")
            return 1
        } catch {
            err("ting-micro: \(error)\n")
            return 2
        }
    }

    /// The default config file: `$TING_CONFIG`, else `~/.config/ting/config.json`.
    static func defaultConfigPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment["TING_CONFIG"], !override.isEmpty { return override }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ting/config.json").path
    }

    /// The micro-apps folder of a config file, as Ting finds it.
    static func microFolder(configPath: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let url = URL(fileURLWithPath: configPath)
        if let override = environment["TING_CONFIG"], !override.isEmpty, override == configPath { return url.appendingPathExtension("micro") }
        return url.deletingLastPathComponent().appendingPathComponent("micro", isDirectory: true)
    }

    static func checkConfig(_ args: [String]) -> Int32 {
        guard args.count <= 1, !(args.first?.hasPrefix("-") ?? false) else {
            err("usage: ting-micro check-config [CONFIG.json]\n")
            return 2
        }
        let path = args.first ?? defaultConfigPath()
        guard let data = FileManager.default.contents(atPath: path) else {
            err("ting-micro check-config: cannot read \(path)\n")
            return 2
        }
        let config: Config
        do {
            config = try ConfigCodec.decode(data)
        } catch ConfigError.invalidFormat(let reason) {
            out("\(path): \(reason)\n")
            return 1
        } catch ConfigError.unsupportedVersion(let version) {
            out("\(path): version \(version) is newer than this Ting understands\n")
            return 1
        } catch {
            out("\(path): \(error)\n")
            return 1
        }
        var problems = ConfigValidator.validate(config).map { issue in
            issue.sequence.isEmpty ? issue.message : "\(issue.sequence.joined(separator: " ")): \(issue.message)"
        }
        // Micro-app bindings must name a micro-app that loads.
        let folder = microFolder(configPath: path)
        let libraries = MicroAppLibraries.read(folder: folder.appendingPathComponent(MicroAppLibraries.folderName))
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".yaml") && !$0.hasPrefix(".") }.sorted()
            .compactMap { name -> (name: String, text: String)? in
                guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(name).path),
                      let text = String(data: data, encoding: .utf8) else { return nil }
                return (name, text)
            }
        let catalog = MicroAppCatalog.load(files, libraries: libraries)
        func walk(_ items: [Item], _ prefix: [String]) {
            for item in items {
                let sequence = prefix + [item.key]
                switch item.action {
                case .group(let children): walk(children, sequence)
                case .micro(let id):
                    if let problem = catalog.resolve(id).problem(id: id, folder: folder.path) {
                        problems.append("\(sequence.joined(separator: " ")): \(problem)")
                    }
                default: break
                }
            }
        }
        walk(config.items, [])
        if problems.isEmpty {
            out("\(path): ok\n")
            return 0
        }
        problems.forEach { out("\(path): \($0)\n") }
        return 1
    }

    static func report(_ result: MicroAppRunResult) -> Int32 {
        switch result {
        case .success(let output):
            if !output.stdout.isEmpty { out(output.stdout + "\n") }
            if !output.stderr.isEmpty { err(output.stderr) }
            if output.stdoutCut || output.stderrCut { err(MicroAppResultPlan.cutNote() + "\n") }
            return 0
        case .cancelled: err("cancelled\n"); return 130
        case .timeout(let output):
            err("timeout\n" + output.stderr + output.stdout + "\n")
            return 124
        case .toolNotFound(let name): err("tool not found: \(name)\n"); return 1
        case .failure(let code, let output):
            err("exit \(code)\n" + output.stderr + output.stdout + "\n")
            return 1
        case .stepFailed(let failure):
            err("\(failure.stepNote): \(failure.note)\n" + failure.output.stderr + "\n" + failure.output.stdout)
            if !failure.output.stdout.isEmpty { err("\n") }
            if failure.note.hasPrefix("stopped after ") { return 124 }
            return 1
        }
    }

    static func out(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
    static func err(_ text: String) { FileHandle.standardError.write(Data(text.utf8)) }
}
