import Foundation
import XCTest

/// Runs the built `Ting` executable with `--check`: it prints, exits and starts nothing.
final class CheckCommandTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The executable next to the test bundle in the build products folder.
    private var executable: URL {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("Ting")
    }

    private struct Run { var status: Int32; var output: String; var errors: String }

    private func run(_ arguments: [String], environment: [String: String]) throws -> Run {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = Self.root
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let errors = err.fileHandleForReading.readDataToEndOfFile()
        // The app would keep running; the check returns at once.
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); XCTFail("Ting --check did not exit") }
        return Run(status: process.terminationStatus, output: String(decoding: output, as: UTF8.self),
                   errors: String(decoding: errors, as: UTF8.self))
    }

    func testCheckRunsWithoutStartingTheApp() throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path), executable.path)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ting-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let bad = directory.appendingPathComponent("bad.yaml")
        try "format: nope\n".write(to: bad, atomically: true, encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var environment = ProcessInfo.processInfo.environment
        environment["TING_CONFIG"] = directory.appendingPathComponent("config.json").path

        let names = ["change-case", "count-text", "dns-lookup", "encode-decode", "format-json"]
        let good = try run(["--check"] + names.map { "docs/micro-apps/examples/\($0).yaml" }, environment: environment)
        XCTAssertEqual(good.status, 0, good.errors)
        XCTAssertEqual(good.output, names.map { "docs/micro-apps/examples/\($0).yaml: ok\n" }.joined())
        XCTAssertEqual(good.errors, "")

        let problems = try run(["--check", bad.path], environment: environment)
        XCTAssertEqual(problems.status, 1)
        XCTAssertTrue(problems.output.hasPrefix(bad.path + ":1: "), problems.output)
        XCTAssertEqual(problems.errors, "")

        let wrong = try run(["--check", "Package.swift"], environment: environment)
        XCTAssertEqual(wrong.status, 2)
        XCTAssertEqual(wrong.output, "")
        XCTAssertTrue(wrong.errors.contains("Package.swift: the name does not end in .yaml"), wrong.errors)

        // No config, log, micro-apps folder, approvals or values were made next to TING_CONFIG.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), before)
    }
}
