import Foundation

/// A micro-app: one shell command with a name, parameters, an input and an output.
/// The format is described in `docs/micro-apps/FORMAT.md`.
public struct MicroApp: Equatable, Sendable {
    public enum Input: String, Equatable, Sendable, CaseIterable {
        /// The clipboard text goes to the command's stdin.
        case clipboard
        /// The command gets an empty stdin.
        case none
    }

    public enum OutputTarget: String, Equatable, Sendable, CaseIterable {
        case clipboard, panel
    }

    /// How the result panel shows stdout.
    public enum OutputStyle: String, Equatable, Sendable, CaseIterable {
        case text, markdown, code, console
    }

    public struct Output: Equatable, Sendable {
        /// In file order, without duplicates.
        public var targets: [OutputTarget]
        public var style: OutputStyle

        public init(targets: [OutputTarget], style: OutputStyle = .markdown) {
            self.targets = targets
            self.style = style
        }
    }

    public struct Param: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case text
            /// The allowed values, in file order.
            case choice([String])
        }

        /// `a-z`, `0-9` and `_` only.
        public var name: String
        public var kind: Kind
        public var required: Bool
        /// Set for an optional parameter, never for a required one; one of the choices for a choice.
        public var defaultValue: String?
        public var prompt: String?

        public init(name: String, kind: Kind, required: Bool, defaultValue: String? = nil, prompt: String? = nil) {
            self.name = name
            self.kind = kind
            self.required = required
            self.defaultValue = defaultValue
            self.prompt = prompt
        }

        /// The environment variable the command reads: `TING_` + upper-case name.
        public var environmentName: String { MicroApp.environmentName(for: name) }
        /// The prompt, or the name when the file has no prompt.
        public var shownPrompt: String { prompt ?? name }
    }

    /// From the file, or the file name without `.yaml`.
    public var id: String
    /// From the file; `nil` when the file has no `name`.
    public var name: String?
    public var description: String
    public var tools: [String]
    /// Not listed in launcha; still starts from a key binding.
    public var hidden: Bool
    /// Offer the last used parameter values next time (default `true`).
    public var remember: Bool
    public var params: [Param]
    public var input: Input
    /// Shell code for `/bin/sh -c`, exactly as written in the file.
    public var command: String
    public var output: Output

    public init(id: String, name: String? = nil, description: String, tools: [String] = [], hidden: Bool = false, remember: Bool = true,
                params: [Param] = [], input: Input, command: String, output: Output) {
        self.id = id
        self.name = name
        self.description = description
        self.tools = tools
        self.hidden = hidden
        self.remember = remember
        self.params = params
        self.input = input
        self.command = command
        self.output = output
    }

    /// The name shown in menus: `name`, or the id when the file has no name.
    public var shownName: String { name ?? id }

    public static func environmentName(for paramName: String) -> String { "TING_" + paramName.uppercased() }
}

/// One mistake in a micro-app file.
public struct MicroAppIssue: Equatable, Sendable, CustomStringConvertible {
    /// The file name, as given to the checker.
    public var file: String
    /// 1-based line number.
    public var line: Int
    public var message: String

    public init(file: String, line: Int, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String { "\(file):\(line): \(message)" }
}

public struct MicroAppFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// Sorted by line; never empty.
    public var issues: [MicroAppIssue]
    /// The `id` the checker could read from the file: a kebab-case text value. `nil` when the file
    /// is not valid YAML or its `id` is missing or not valid.
    public var id: String?

    public init(issues: [MicroAppIssue], id: String? = nil) {
        self.issues = issues
        self.id = id
    }

    public var description: String { issues.map(\.description).joined(separator: "\n") }
}

/// Turns the text of a micro-app file into a `MicroApp` or a list of issues.
public enum MicroAppChecker {
    public static let format = "ting.microapp/2"
    public static let fileExtension = "yaml"
    public static let topKeys = ["format", "id", "name", "description", "tools", "hidden", "remember", "params", "input", "command", "output"]
    public static let requiredTopKeys = ["format", "description", "input", "command", "output"]
    public static let paramKeys = ["name", "type", "required", "default", "choices", "prompt"]
    public static let paramTypes = ["text", "choice"]
    public static let outputKeys = ["to", "as"]

    /// `fileName` is the file name or path; its last component is used in issues and gives the id
    /// when the file has none.
    public static func check(_ text: String, fileName: String) -> Result<MicroApp, MicroAppFailure> {
        let file = (fileName as NSString).lastPathComponent
        var run = Run(file: file)
        let root: YAMLNode
        do {
            root = try YAMLSubset.parse(text)
        } catch let error as YAMLError {
            return .failure(MicroAppFailure(issues: [MicroAppIssue(file: file, line: error.line, message: error.message)]))
        } catch {
            return .failure(MicroAppFailure(issues: [MicroAppIssue(file: file, line: 1, message: "\(error)")]))
        }
        let app = run.check(root)
        if run.issues.isEmpty, let app { return .success(app) }
        let sorted = run.issues.enumerated().sorted { ($0.element.line, $0.offset) < ($1.element.line, $1.offset) }.map(\.element)
        return .failure(MicroAppFailure(issues: sorted, id: run.explicitID))
    }

    /// `a-z0-9` words joined by single `-`.
    public static func isKebabCase(_ s: String) -> Bool {
        let words = s.split(separator: "-", omittingEmptySubsequences: false)
        return !s.isEmpty && words.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) } }
    }

    public static func isParamName(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }

    public static func isToolName(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._+-".contains($0)) }
    }

    private struct Run {
        let file: String
        var issues: [MicroAppIssue] = []
        /// The `id` key of the file when it is a kebab-case text value.
        var explicitID: String?

        init(file: String) { self.file = file }

        mutating func fail(_ line: Int, _ message: String) {
            issues.append(MicroAppIssue(file: file, line: line, message: message))
        }

        // MARK: Value helpers

        mutating func string(_ node: YAMLNode, _ what: String, oneLine: Bool = true, nonEmpty: Bool = true) -> String? {
            guard case .scalar(let s) = node else {
                fail(node.line, "`\(what)` must be a text value")
                return nil
            }
            if oneLine && s.value.contains("\n") {
                fail(s.line, "`\(what)` must be one line")
                return nil
            }
            if nonEmpty && s.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fail(s.line, "`\(what)` must not be empty")
                return nil
            }
            return s.value
        }

        mutating func bool(_ node: YAMLNode, _ what: String) -> Bool? {
            if case .scalar(let s) = node, s.style == .plain {
                if s.value == "true" { return true }
                if s.value == "false" { return false }
            }
            fail(node.line, "`\(what)` must be `true` or `false`")
            return nil
        }

        mutating func list(_ node: YAMLNode, _ what: String) -> [YAMLNode]? {
            guard case .sequence(let items, _) = node else {
                fail(node.line, "`\(what)` must be a list")
                return nil
            }
            return items
        }

        mutating func entries(_ node: YAMLNode, _ what: String, allowed: [String]) -> [String: YAMLEntry]? {
            guard case .mapping(let entries, _) = node else {
                fail(node.line, "`\(what)` must be a map of `key: value` lines")
                return nil
            }
            var result: [String: YAMLEntry] = [:]
            for entry in entries {
                if allowed.contains(entry.key) {
                    result[entry.key] = entry
                } else {
                    fail(entry.keyLine, "unknown key `\(entry.key)` in \(what); allowed: \(allowed.joined(separator: ", "))")
                }
            }
            return result
        }

        mutating func oneOf(_ node: YAMLNode, _ what: String, _ values: [String]) -> String? {
            if case .scalar(let s) = node, values.contains(s.value), !s.value.contains("\n") { return s.value }
            let shown: String
            if case .scalar(let s) = node { shown = "`\(s.value)`" } else { shown = "this value" }
            fail(node.line, "`\(what)` is \(shown); it must be one of: \(values.joined(separator: ", "))")
            return nil
        }

        // MARK: File

        mutating func check(_ root: YAMLNode) -> MicroApp? {
            guard case .mapping = root else {
                fail(root.line, "a micro-app file must be a map of `key: value` lines")
                return nil
            }
            guard let top = entries(root, "the file", allowed: MicroAppChecker.topKeys) else { return nil }
            for key in MicroAppChecker.requiredTopKeys where top[key] == nil {
                fail(root.line, "missing required key `\(key)`")
            }

            if let e = top["format"], let value = string(e.value, "format"), value != MicroAppChecker.format {
                fail(e.value.line, "`format` must be `\(MicroAppChecker.format)`, not `\(value)`")
            }

            let stem = fileStem(line: root.line)
            var id = stem
            if let e = top["id"], let value = string(e.value, "id") {
                if !MicroAppChecker.isKebabCase(value) {
                    fail(e.value.line, "`id` `\(value)` must be kebab-case: a-z and 0-9 words joined by `-`")
                } else {
                    explicitID = value
                    if let stem, value != stem {
                        fail(e.value.line, "`id` `\(value)` must equal the file name `\(stem)`; rename the file or remove `id`")
                    }
                }
                id = value
            } else if top["id"] == nil, let stem, !MicroAppChecker.isKebabCase(stem) {
                fail(root.line, "the file name `\(stem)` must be kebab-case (a-z and 0-9 words joined by `-`), because it is the id")
            }

            let name = top["name"].flatMap { string($0.value, "name") }
            let description = top["description"].flatMap { string($0.value, "description") }

            var tools: [String] = []
            if let e = top["tools"], let items = list(e.value, "tools") {
                for item in items {
                    guard let tool = string(item, "tools") else { continue }
                    if MicroAppChecker.isToolName(tool) {
                        tools.append(tool)
                    } else {
                        fail(item.line, "`tools`: `\(tool)` is not a command name")
                    }
                }
            }

            let hidden = top["hidden"].flatMap { bool($0.value, "hidden") } ?? false
            let remember = top["remember"].flatMap { bool($0.value, "remember") } ?? true
            let params = top["params"].map { checkParams($0.value) } ?? []
            let input = top["input"].flatMap { oneOf($0.value, "input", MicroApp.Input.allCases.map(\.rawValue)) }.flatMap(MicroApp.Input.init)
            let command = top["command"].flatMap { checkCommand($0.value, params: params) }
            let output = top["output"].flatMap { checkOutput($0.value, keyLine: $0.keyLine) }

            guard let id, let description, let input, let command, let output else { return nil }
            return MicroApp(id: id, name: name, description: description, tools: tools, hidden: hidden, remember: remember,
                            params: params.map(\.param), input: input, command: command, output: output)
        }

        mutating func fileStem(line: Int) -> String? {
            let suffix = "." + MicroAppChecker.fileExtension
            guard file.hasSuffix(suffix), file.count > suffix.count else {
                fail(line, "a micro-app file name must end in `\(suffix)`")
                return nil
            }
            return String(file.dropLast(suffix.count))
        }

        // MARK: Params

        struct CheckedParam {
            var param: MicroApp.Param
            var line: Int
        }

        mutating func checkParams(_ node: YAMLNode) -> [CheckedParam] {
            guard let items = list(node, "params") else { return [] }
            var result: [CheckedParam] = []
            var seen: [String: Int] = [:]
            for (i, item) in items.enumerated() {
                let what = "params[\(i)]"
                guard let keys = entries(item, what, allowed: MicroAppChecker.paramKeys) else { continue }
                var ok = true

                var name: String?
                if let e = keys["name"], let value = string(e.value, "\(what).name") {
                    if !MicroAppChecker.isParamName(value) {
                        fail(e.value.line, "\(what): name `\(value)` may only use a-z, 0-9 and `_`")
                        ok = false
                    } else if let first = seen[value] {
                        fail(e.value.line, "\(what): param `\(value)` is already declared on line \(first)")
                        ok = false
                    } else {
                        seen[value] = e.value.line
                        name = value
                    }
                } else if keys["name"] == nil {
                    fail(item.line, "\(what): missing required key `name`")
                }

                let type = keys["type"].flatMap { oneOf($0.value, "\(what).type", MicroAppChecker.paramTypes) }
                if keys["type"] == nil { fail(item.line, "\(what): missing required key `type`") }

                var required: Bool?
                if let e = keys["required"] {
                    required = bool(e.value, "\(what).required")
                } else {
                    fail(item.line, "\(what): `required` must be written out as `true` or `false`")
                }

                let defaultValue = keys["default"].flatMap { string($0.value, "\(what).default", nonEmpty: false) }
                if required == false && keys["default"] == nil {
                    fail(keys["required"]!.value.line, "\(what): an optional param needs a `default`")
                    ok = false
                }
                if required == true, let d = keys["default"] {
                    fail(d.keyLine, "\(what): a required param cannot have a `default`; remembered values already fill it in")
                    ok = false
                }
                let prompt = keys["prompt"].flatMap { string($0.value, "\(what).prompt") }

                var kind: MicroApp.Param.Kind?
                switch type {
                case "text":
                    if let e = keys["choices"] {
                        fail(e.keyLine, "\(what): `choices` is only for `type: choice`")
                        ok = false
                    }
                    kind = .text
                case "choice":
                    guard let e = keys["choices"] else {
                        fail(item.line, "\(what): a choice needs `choices`")
                        break
                    }
                    guard let options = list(e.value, "\(what).choices") else { break }
                    var values: [String] = []
                    for option in options {
                        guard let value = string(option, "\(what).choices") else { continue }
                        if values.contains(value) {
                            fail(option.line, "\(what): choice `\(value)` is listed twice")
                        } else {
                            values.append(value)
                        }
                    }
                    if options.isEmpty { fail(e.value.line, "\(what): `choices` must not be empty") }
                    if let defaultValue, !values.contains(defaultValue), let d = keys["default"] {
                        fail(d.value.line, "\(what): default `\(defaultValue)` is not one of the choices")
                        ok = false
                    }
                    if !values.isEmpty { kind = .choice(values) }
                default:
                    break
                }

                if ok, let name, let kind, let required {
                    let param = MicroApp.Param(name: name, kind: kind, required: required, defaultValue: defaultValue,
                                               prompt: prompt)
                    result.append(CheckedParam(param: param, line: keys["name"]?.keyLine ?? item.line))
                } else if let name, let e = keys["name"] {
                    // Keep the variable known, so the command check does not report it again.
                    result.append(CheckedParam(param: MicroApp.Param(name: name, kind: .text, required: true), line: e.keyLine))
                }
            }
            return result
        }

        // MARK: Command

        mutating func checkCommand(_ node: YAMLNode, params: [CheckedParam]) -> String? {
            guard case .scalar(let s) = node, !s.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail(node.line, "`command` must be one non-empty string; use `command: |` for several lines")
                return nil
            }
            let command = s.value
            func line(at index: String.Index) -> Int {
                s.contentLine + command[..<index].reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
            }
            let before = issues.count

            for p in params {
                if let range = command.range(of: "{\(p.param.name)}"), !command[..<range.lowerBound].hasSuffix("$") {
                    fail(line(at: range.lowerBound), "command: `{\(p.param.name)}` templates are not allowed; use `\"$\(p.param.environmentName)\"`")
                }
            }

            let declared = Set(params.map(\.param.environmentName))
            var used: Set<String> = []
            var reported: Set<String> = []
            var search = command.startIndex
            while let range = command.range(of: "TING_", range: search..<command.endIndex) {
                search = range.upperBound
                let prefix = command[..<range.lowerBound]
                guard prefix.hasSuffix("$") || prefix.hasSuffix("${") else { continue }
                let nameEnd = command[range.upperBound...].firstIndex { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")) } ?? command.endIndex
                let variable = String(command[range.lowerBound..<nameEnd])
                used.insert(variable)
                if !declared.contains(variable) && !reported.contains(variable) {
                    reported.insert(variable)
                    fail(line(at: range.lowerBound), "command: `$\(variable)` is not a declared param")
                }
            }
            for p in params where !used.contains(p.param.environmentName) {
                fail(p.line, "param `\(p.param.name)` is never used: the command must read `$\(p.param.environmentName)`")
            }
            return issues.count == before ? command : nil
        }

        // MARK: Output

        mutating func checkOutput(_ node: YAMLNode, keyLine: Int) -> MicroApp.Output? {
            guard let keys = entries(node, "output", allowed: MicroAppChecker.outputKeys) else { return nil }
            var targets: [MicroApp.OutputTarget] = []
            var ok = true
            if let e = keys["to"] {
                if let items = list(e.value, "output.to") {
                    if items.isEmpty { fail(e.value.line, "`output.to` must not be empty"); ok = false }
                    for item in items {
                        guard let raw = oneOf(item, "output.to", MicroApp.OutputTarget.allCases.map(\.rawValue)),
                              let target = MicroApp.OutputTarget(rawValue: raw)
                        else { ok = false; continue }
                        if targets.contains(target) {
                            fail(item.line, "`output.to`: `\(raw)` is listed twice")
                            ok = false
                        } else {
                            targets.append(target)
                        }
                    }
                } else {
                    ok = false
                }
            } else {
                fail(keyLine, "`output` needs `to`: a list of `clipboard`, `panel` or both")
                ok = false
            }
            var style = MicroApp.OutputStyle.markdown
            if let e = keys["as"] {
                if let raw = oneOf(e.value, "output.as", MicroApp.OutputStyle.allCases.map(\.rawValue)),
                   let value = MicroApp.OutputStyle(rawValue: raw) {
                    style = value
                } else {
                    ok = false
                }
            }
            return ok ? MicroApp.Output(targets: targets, style: style) : nil
        }
    }
}
