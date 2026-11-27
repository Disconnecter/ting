import XCTest
import TingCore
@testable import Ting

@MainActor
private final class FakeOpener: LaunchaOpening {
    var outcome: LaunchOutcome = .opened
    private(set) var opened: [URL] = []
    private(set) var files: [URL] = []
    private(set) var revealed: [URL] = []

    func openApp(at url: URL, name: String) async -> LaunchOutcome {
        opened.append(url)
        return outcome
    }

    func openFile(_ url: URL, name: String) async -> LaunchOutcome {
        files.append(url)
        return outcome
    }

    func reveal(_ url: URL) -> LaunchOutcome {
        revealed.append(url)
        return .revealed
    }
}

/// Thread-safe record of Spotlight provider calls.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var queries: [String] = []
    func add(_ query: String) { lock.withLock { queries.append(query) } }
    var all: [String] { lock.withLock { queries } }
}

@MainActor
final class LaunchaModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ting-launcha-model-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = try XCTUnwrap(LaunchaPathPolicy.realURL(url))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func app(_ name: String, id: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name + ".app")
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleName": name, "CFBundleIdentifier": id, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }

    private struct Fixture {
        var model: LaunchaModel
        var opener: FakeOpener
        var calls: Calls
        var history: URL
        var consent: URL
    }

    func testClipbawdSearchOpenAndDisabled() async throws {
        let fixture = try makeModel()
        let model = fixture.model
        var opened = 0
        model.onOpenClipbawd = { opened += 1 }
        model.clipbawdEnabled = true
        model.open()
        model.query = "Clipbawd"
        XCTAssertEqual(model.rows.first?.kind, .clipbawd)
        _ = await model.activateSelection()
        XCTAssertEqual(opened, 1)
        XCTAssertTrue(fixture.opener.files.isEmpty)
        model.clipbawdEnabled = false
        model.open()
        model.query = "Clipbawd"
        XCTAssertFalse(model.rows.contains { $0.kind == .clipbawd })
        model.close()
    }

    private var policies: [ProtectedFolderPolicy] = []
    private var folderRequests: [[String]] = []

    private func makeModel(files: [URL] = [], spotlightDelay: Duration = .zero, running: Set<String> = []) throws -> Fixture {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let opener = FakeOpener()
        let calls = Calls()
        let home = root!
        let historyURL = root.appendingPathComponent("history.json")
        let consentURL = root.appendingPathComponent("consent.json")
        let model = LaunchaModel(opener: opener, historyStore: LaunchaHistoryStore(url: historyURL),
                                 consent: LaunchaConsentStore(url: consentURL), home: home,
                                 runningAppIDs: { running }, makeServices: { [weak self] policy in
            self?.policies.append(policy)
            let desktop = home.appendingPathComponent("Desktop")
            return LaunchaModel.Services(
                index: LaunchaAppIndex(home: home, protectedFolders: policy, roots: [apps, desktop]),
                spotlight: LaunchaSpotlight(home: home, protectedFolders: policy, debounce: .zero) { query in
                    calls.add(query)
                    if spotlightDelay > .zero { try? await Task.sleep(for: spotlightDelay) }
                    return files
                })
        }, requestFolderAccess: { [weak self] urls in
            self?.folderRequests.append(urls.map(\.lastPathComponent))
        })
        return Fixture(model: model, opener: opener, calls: calls, history: historyURL, consent: consentURL)
    }

    private func wait(_ message: String = "condition", timeout: Duration = .seconds(3),
                      until condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while !condition() {
            guard clock.now < end else { return XCTFail("Timed out waiting for \(message)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testEmptyQueryRanksAppsAndFilesFollowApps() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let alpha = try app("Alpha", id: "io.bobuk.Alpha", in: apps)
        _ = try app("Beta", id: "io.bobuk.beta", in: apps)
        let note = root.appendingPathComponent("Projects/zeta-note.txt")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: note)
        let fixture = try makeModel(files: [note])
        let model = fixture.model

        // History decides the order: Beta was launched, so it comes first.
        await model.record(.opened, id: "app:io.bobuk.beta")
        model.open()
        try await wait("index") { model.hasIndex && model.rows.count == 2 }
        XCTAssertEqual(model.rows.map(\.name), ["Beta", "Alpha"])
        XCTAssertEqual(model.rows.last?.url?.path, alpha.path)
        XCTAssertTrue(fixture.calls.all.isEmpty)

        model.query = "al"
        XCTAssertEqual(model.rows.map(\.name), ["Alpha"])
        XCTAssertTrue(fixture.calls.all.isEmpty, "a short query that matches an app does not search files")

        // A longer query also searches files; they go below the app, which stays selected.
        model.query = "alp"
        try await wait("files below apps") { model.rows.count == 2 }
        XCTAssertEqual(fixture.calls.all, ["alp"])
        XCTAssertEqual(model.rows.map(\.name), ["Alpha", "zeta-note.txt"])
        XCTAssertEqual(model.rows.last?.kind, .file(note))
        XCTAssertEqual(model.selectedRow?.name, "Alpha")
        // ⌘↓ jumps past the apps to the first file.
        XCTAssertTrue(model.canJumpToFiles)
        model.selectFirstFile()
        XCTAssertEqual(model.selectedRow?.kind, .file(note))

        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedRow?.name, "Alpha")

        // The last results, narrowed to the new query, stay until Spotlight answers it.
        model.query = "zeta"
        XCTAssertEqual(model.rows.map(\.kind), [.file(note)])
        XCTAssertEqual(model.spotlight.status, .searching)
        try await wait("files") { model.spotlight.status == .results }
        XCTAssertEqual(model.rows.map(\.kind), [.file(note)])
        XCTAssertFalse(model.canJumpToFiles, "files alone need no jump")
        XCTAssertEqual(fixture.calls.all, ["alp", "zeta"])
        XCTAssertEqual(model.rows.compactMap { $0.url?.path }, [note.path])
        XCTAssertEqual(model.rows.first?.detail, "~/Projects")
        XCTAssertTrue(model.showsConsentNotice, "Protected folders were skipped; the search is not complete")

        // An app match cancels the file search and hides its results.
        model.query = "be"
        XCTAssertEqual(model.rows.map(\.name), ["Beta"])
        XCTAssertEqual(model.spotlight.status, .idle)
        model.close()
    }

    func testSelectionStaysOnFilesWhileTypingAfterCommandDown() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        _ = try app("Alpha", id: "io.bobuk.Alpha", in: apps)
        let report = root.appendingPathComponent("Projects/alpha-report.txt")
        try FileManager.default.createDirectory(at: report.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: report)
        let fixture = try makeModel(files: [report])
        let model = fixture.model
        model.open()
        try await wait("index") { model.hasIndex }

        model.query = "alp"
        try await wait("files below apps") { model.rows.count == 2 }
        XCTAssertEqual(model.selectedRow?.name, "Alpha")
        model.selectFirstFile()
        XCTAssertEqual(model.selectedRow?.kind, .file(report))

        // Typing more keeps the selection on files, with no keystroke where an app is selected.
        model.query = "alph"
        XCTAssertEqual(model.selectedRow?.kind, .file(report))
        try await wait("new results") { model.spotlight.status == .results }
        XCTAssertEqual(model.selectedRow?.kind, .file(report))

        // Files are searched below apps even for a short query while the selection follows them.
        model.query = "al"
        XCTAssertEqual(model.selectedRow?.kind, .file(report))
        try await wait("short query results") { model.spotlight.status == .results }
        XCTAssertEqual(fixture.calls.all, ["alp", "alph", "al"])

        // Moving onto an app ends it: the next query selects the best app again.
        model.moveSelection(by: -1)
        model.query = "alp"
        XCTAssertEqual(model.selectedRow?.name, "Alpha")
        try await wait("results") { model.spotlight.status == .results }
        XCTAssertEqual(model.selectedRow?.name, "Alpha")

        // ⌘↓ on a short query that only lists apps starts the file search and selects the first file.
        model.query = "a"
        XCTAssertEqual(model.selectedRow?.name, "Alpha")
        XCTAssertTrue(model.canJumpToFiles)
        XCTAssertFalse(model.rows.contains(where: \.isFile), "a short query alone does not search files")
        model.selectFirstFile()
        try await wait("file search on ⌘↓") { model.selectedRow?.kind == .file(report) }
        XCTAssertEqual(fixture.calls.all.last, "a")

        // A new session starts on apps.
        model.selectFirstFile()
        model.close()
        model.open()
        model.query = "alp"
        XCTAssertEqual(model.selectedRow?.name, "Alpha")
        model.close()
    }

    func testIncompleteAndFailedStatesAreShown() async throws {
        let fixture = try makeModel(files: [])
        let model = fixture.model
        model.open()
        try await wait("index") { model.hasIndex }
        XCTAssertEqual(model.statusMessage, .info("No apps found."))
        model.query = "nothing"
        try await wait("empty search") { model.spotlight.status == .empty }
        XCTAssertEqual(model.statusMessage, .info("No apps or files match “nothing”."))
        XCTAssertEqual(Set(model.spotlight.issues.map(\.kind)), [.needsConsent])
        XCTAssertTrue(model.showsConsentNotice)
        XCTAssertNil(model.incompleteMessage)
        model.close()
    }

    func testClosedSessionIgnoresLateResults() async throws {
        let late = root.appendingPathComponent("late.txt")
        try Data().write(to: late)
        let fixture = try makeModel(files: [late], spotlightDelay: .milliseconds(150))
        let model = fixture.model
        model.open()
        try await wait("index") { model.hasIndex }
        model.query = "late"
        XCTAssertEqual(model.spotlight.status, .searching)
        model.close()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.spotlight.status, .idle)

        // A new session starts clean, with no results of the old query.
        model.open()
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.query, "")
        model.close()
    }

    func testOnlySuccessfulLaunchesCountOnceWithRetainedURL() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let tool = try app("Tool", id: "io.bobuk.Tool", in: apps)
        let fixture = try makeModel()
        let model = fixture.model
        var closeRequests = 0
        model.onRequestClose = { closeRequests += 1 }

        model.open()
        try await wait("index") { model.rows.count == 1 }
        var outcome = await model.activateSelection()
        XCTAssertEqual(outcome, .opened)
        XCTAssertEqual(fixture.opener.opened.map(\.path), [tool.path])
        XCTAssertFalse(model.isOpen)
        XCTAssertEqual(closeRequests, 1)
        var saved = try LaunchHistory.decode(Data(contentsOf: fixture.history))
        XCTAssertEqual(saved.entries["app:io.bobuk.tool"]?.events.count, 1, "Same identity as selecta: app: + lower-case bundle ID")

        fixture.opener.outcome = .failed
        model.open()
        try await wait("index") { model.rows.count == 1 }
        outcome = await model.activateSelection()
        XCTAssertEqual(outcome, .failed)

        model.open()
        try await wait("index") { model.rows.count == 1 }
        outcome = await model.activateSelection(reveal: true)
        XCTAssertEqual(outcome, .revealed)
        XCTAssertEqual(fixture.opener.revealed.map(\.path), [tool.path])

        fixture.opener.outcome = .activated
        model.open()
        try await wait("index") { model.rows.count == 1 }
        outcome = await model.activateSelection()
        XCTAssertEqual(outcome, .activated)

        saved = try LaunchHistory.decode(Data(contentsOf: fixture.history))
        XCTAssertEqual(saved.entries["app:io.bobuk.tool"]?.events.count, 2, "Failed opens and reveals are not counted")
        let closed = await model.activateSelection()
        XCTAssertNil(closed, "Nothing happens while closed")
    }

    func testSelectionMovesWithinBounds() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        for name in ["A1", "A2", "A3"] { _ = try app(name, id: "io.bobuk." + name, in: apps) }
        let model = try makeModel().model
        model.open()
        try await wait("index") { model.rows.count == 3 }
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selection, 0)
        model.moveSelection(by: 8)
        XCTAssertEqual(model.selection, 2)
        model.query = "a2"
        XCTAssertEqual(model.selection, 0, "A new query selects the first result")
        model.close()
    }

    func testConsentRecreatesServicesAndPersistsSeparately() async throws {
        let desktop = root.appendingPathComponent("Desktop")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        _ = try app("DeskTool", id: "io.bobuk.desk", in: desktop)
        policies = []
        folderRequests = []
        let fixture = try makeModel()
        let model = fixture.model
        XCTAssertEqual(folderRequests, [], "No folder is read before consent")
        model.open()
        try await wait("index") { model.hasIndex }
        XCTAssertTrue(model.rows.isEmpty, "Desktop needs consent first")
        XCTAssertEqual(model.indexIssues.map(\.kind), [.needsConsent])

        model.isExplainingConsent = true
        model.allowProtectedFolders()
        XCTAssertFalse(model.isExplainingConsent)
        XCTAssertEqual(model.protectedFolders, .allowed)
        XCTAssertEqual(policies, [.needsConsent, .allowed])
        XCTAssertEqual(folderRequests, [["Desktop", "Documents", "Downloads"]], "Each folder is read so macOS asks")
        try await wait("desktop app") { model.rows.map(\.name) == ["DeskTool"] }
        XCTAssertFalse(model.showsConsentNotice)

        // A fresh store reads the saved choice.
        XCTAssertEqual(LaunchaConsentStore(url: fixture.consent).policy, .allowed)
        // A model with saved consent asks again: consent may predate the folder reads.
        _ = try makeModel()
        XCTAssertEqual(folderRequests.count, 2)

        model.revokeProtectedFolders()
        XCTAssertTrue(model.rows.isEmpty, "Apps from folders no longer allowed are dropped at once")
        XCTAssertEqual(LaunchaConsentStore(url: fixture.consent).policy, .needsConsent)
        XCTAssertEqual(folderRequests.count, 2, "Revoking reads nothing")
        model.close()
    }

    func testConsentStoreIsolationAndFailClosed() throws {
        let config = root.appendingPathComponent("ting-test.json")
        let isolated = LaunchaConsentStore.defaultURL(environment: ["TING_CONFIG": config.path], home: root)
        XCTAssertTrue(isolated.path.hasPrefix(config.path + "."))
        XCTAssertNotEqual(isolated, LaunchaHistoryStore.defaultURL(environment: ["TING_CONFIG": config.path], home: root))
        XCTAssertEqual(LaunchaConsentStore.defaultURL(environment: [:], home: root).path,
                       root.appendingPathComponent("Library/Application Support/Ting/launcha-consent.json").path)

        let fresh = LaunchaConsentStore(url: root.appendingPathComponent("missing.json"))
        XCTAssertEqual(fresh.policy, .needsConsent)
        XCTAssertNil(fresh.error)

        let broken = root.appendingPathComponent("broken.json")
        try Data("{\"protectedFolders\": tru".utf8).write(to: broken)
        let store = LaunchaConsentStore(url: broken)
        XCTAssertEqual(store.policy, .needsConsent)
        XCTAssertNotNil(store.error)

        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        let unwritable = LaunchaConsentStore(url: blocked.appendingPathComponent("consent.json"))
        XCTAssertFalse(unwritable.set(.allowed))
        XCTAssertEqual(unwritable.policy, .needsConsent, "The choice changes only when it was saved")
    }

    func testAppUseRanksOnlyWhileOnAndIsDeletedWhenOff() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        _ = try app("Safari", id: "com.apple.Safari", in: apps)
        _ = try app("1Password for Safari", id: "com.1password.safari", in: apps)
        let fixture = try makeModel(running: ["app:com.apple.safari"])
        let model = fixture.model
        let usage = root.appendingPathComponent("app-usage.json")
        model.open()
        try await wait("index") { model.hasIndex && model.rows.count == 2 }

        // Off: nothing is recorded and running apps do not move.
        model.noteActivation(bundleID: "com.1password.safari")
        model.query = "sfr"
        XCTAssertEqual(model.rows.map(\.name), ["Safari", "1Password for Safari"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: usage.path))

        model.appSwitching = true
        model.noteActivation(bundleID: "com.1password.safari")
        try await wait("usage") { model.rows.first?.name == "1Password for Safari" }
        XCTAssertTrue(FileManager.default.fileExists(atPath: usage.path))

        // The running Safari goes first, above more use.
        model.runningApps = .higher
        XCTAssertEqual(model.rows.map(\.name), ["Safari", "1Password for Safari"])
        model.runningApps = .lower
        XCTAssertEqual(model.rows.map(\.name), ["1Password for Safari", "Safari"])

        model.appSwitching = false
        try await wait("deleted") { !FileManager.default.fileExists(atPath: usage.path) }
        XCTAssertEqual(model.rows.map(\.name), ["Safari", "1Password for Safari"])
        // A late activation never brings the record back.
        model.noteActivation(bundleID: "com.1password.safari")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(FileManager.default.fileExists(atPath: usage.path))
    }

    func testMicroAppsAreListedAndStartTheFlow() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        _ = try app("Safari", id: "com.apple.Safari", in: apps)
        let fixture = try makeModel(files: [root.appendingPathComponent("never.txt")])
        let model = fixture.model
        let good = """
        format: ting.microapp/2
        name: Format JSON
        description: Pretty-print JSON.
        input: clipboard
        command: cat
        output:
          to: [panel]
        """
        let hidden = good.replacingOccurrences(of: "name: Format JSON", with: "name: Hidden JSON\nhidden: true")
        let catalog = MicroAppCatalog.load([
            ("format-json.yaml", good),
            ("hidden-json.yaml", hidden),
            ("broken-json.yaml", "format: ting.microapp/2\n"),
        ])
        let folder = root.appendingPathComponent("micro")
        model.setMicroApps(catalog.launchaCandidates(bindings: []), folder: folder)
        var started: [LaunchaMicroStart] = []
        model.onStartMicro = { started.append($0) }

        model.open()
        try await wait("index") { model.hasIndex && model.rows.count == 3 }
        XCTAssertEqual(Set(model.rows.map(\.name)), ["Safari", "Format JSON", "broken-json"])

        model.query = "json"
        XCTAssertEqual(model.rows.map(\.name), ["broken-json", "Format JSON"])
        XCTAssertFalse(model.rows.first?.isWorking ?? true)
        XCTAssertTrue(model.rows.first?.detail.hasPrefix("Not working: line ") ?? false)
        XCTAssertEqual(model.rows.last?.detail, "Pretty-print JSON.")
        XCTAssertEqual(model.rows.last?.url, folder.appendingPathComponent("format-json.yaml"))
        XCTAssertTrue(model.rows.last?.isWorking ?? false)

        model.query = "format"
        XCTAssertEqual(model.rows.map(\.name), ["Format JSON"])

        var outcome = await model.activateSelection()
        XCTAssertEqual(outcome, .opened)
        XCTAssertEqual(started, [.id("format-json")])
        XCTAssertFalse(model.isOpen)
        XCTAssertTrue(fixture.opener.files.isEmpty)
        XCTAssertTrue(fixture.opener.opened.isEmpty)
        let saved = try LaunchHistory.decode(Data(contentsOf: fixture.history))
        XCTAssertEqual(saved.entries["micro:format-json"]?.events.count, 1)

        // A broken file starts the flow too, which shows its error; it is not counted.
        model.open()
        model.query = "broken"
        try await wait("broken row") { model.rows.count == 1 }
        outcome = await model.activateSelection()
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(started, [.id("format-json"), .file("broken-json.yaml")])

        // ⌘↩ shows the file in Finder and starts nothing.
        model.open()
        model.query = "format"
        try await wait("format row") { model.rows.count == 1 }
        outcome = await model.activateSelection(reveal: true)
        XCTAssertEqual(outcome, .revealed)
        XCTAssertEqual(fixture.opener.revealed, [folder.appendingPathComponent("format-json.yaml")])
        XCTAssertEqual(started.count, 2)
    }
}

extension LaunchaModelTests {
    func testACalculationComesFirstAndReturnCopiesIt() async throws {
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        _ = try app("Calc 2", id: "io.bobuk.calc2", in: apps)
        let report = root.appendingPathComponent("2+2 notes.txt")
        try Data().write(to: report)
        let fixture = try makeModel(files: [report])
        let model = fixture.model
        var copied: [String] = []
        var closed = 0
        model.onCopyValue = { copied.append($0) }
        model.onRequestClose = { closed += 1 }
        model.open()
        try await wait("index") { model.hasIndex }

        // No app matches: the value first, the files after it.
        model.query = "2+2"
        XCTAssertEqual(model.rows.first?.kind, .calculation(value: "4"))
        XCTAssertEqual(model.rows.first?.name, "4")
        try await wait("files") { model.rows.count == 2 }
        XCTAssertEqual(model.rows.map(\.kind), [.calculation(value: "4"), .file(report)])
        XCTAssertEqual(model.selection, 0)

        // An app whose name matches the digits comes after the value.
        model.query = "2 * 3"
        XCTAssertEqual(model.rows.first?.kind, .calculation(value: "6"))
        model.query = "calc 2"
        XCTAssertEqual(model.rows.map(\.name), ["Calc 2"], "no operator: no value")

        // Plain text and lone numbers are not calculations.
        model.query = "42"
        XCTAssertFalse(model.rows.contains(where: \.isCalculation))

        // Return copies the value and closes; nothing is opened or counted.
        model.query = "1,5 × 4"
        let outcome = await model.activateSelection()
        XCTAssertNil(outcome)
        XCTAssertEqual(copied, ["6"])
        XCTAssertEqual(closed, 1)
        XCTAssertTrue(fixture.opener.opened.isEmpty && fixture.opener.files.isEmpty && fixture.opener.revealed.isEmpty)

        // Command-Return copies too: a value has nothing to reveal.
        model.open()
        model.query = "10/4"
        _ = await model.activateSelection(reveal: true)
        XCTAssertEqual(copied, ["6", "2.5"])
        XCTAssertTrue(fixture.opener.revealed.isEmpty)

        // Turned off in Settings: no value, at once.
        model.open()
        model.query = "2+2"
        XCTAssertTrue(model.rows.first?.isCalculation == true)
        model.calculator = false
        XCTAssertFalse(model.rows.contains(where: \.isCalculation))
        model.close()
    }

    func testAConversionComesFirstAndReturnCopiesTheNumber() async throws {
        let fixture = try makeModel(files: [])
        let model = fixture.model
        var copied: [String] = []
        model.onCopyValue = { copied.append($0) }
        model.open()
        try await wait("index") { model.hasIndex }

        // The row shows the unit; Return copies the number alone.
        model.query = "5 yd to m"
        XCTAssertEqual(model.rows.first?.kind, .calculation(value: "4.572"))
        XCTAssertEqual(model.rows.first?.name, "4.572 m")
        XCTAssertEqual(model.rows.first?.detail, "5 yd · Return copies 4.572")
        _ = await model.activateSelection()
        XCTAssertEqual(copied, ["4.572"])
        XCTAssertTrue(fixture.opener.opened.isEmpty && fixture.opener.files.isEmpty)

        // A bare 0xff converts too; plain words with "to" are not a conversion.
        model.open()
        model.query = "0xff"
        XCTAssertEqual(model.rows.first?.kind, .calculation(value: "255"))
        model.query = "go to market"
        XCTAssertFalse(model.rows.contains(where: \.isCalculation))

        // Turned off in Settings: no value, at once; the calculator stays.
        model.query = "255 to hex"
        XCTAssertEqual(model.rows.first?.kind, .calculation(value: "0xff"))
        model.converter = false
        XCTAssertFalse(model.rows.contains(where: \.isCalculation))
        model.query = "2+2"
        XCTAssertEqual(model.rows.first?.kind, .calculation(value: "4"))
        model.close()
    }
}
