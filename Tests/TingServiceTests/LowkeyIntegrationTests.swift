import XCTest
import TingCore
@testable import Ting

@MainActor final class LowkeyIntegrationTests: XCTestCase {
    private let appURL = URL(fileURLWithPath: "/tmp/Lowkey-test.app")
    private let config = Data(#"{"sites":[{"alias":"work","title":"Work Chat","startURL":"https://chat.example.com"}]}"#.utf8)

    func testDoesNotReadAnythingWhenLowkeyIsNotInstalled() {
        var reads = 0
        let service = LowkeyIntegration(locate: { nil }, read: { reads += 1; return self.config })
        service.refresh()
        XCTAssertFalse(service.isInstalled)
        XCTAssertTrue(service.sites.isEmpty)
        XCTAssertEqual(reads, 0)
    }

    func testReadsSavedSitesAndRefreshesAfterEditingAndUninstalling() {
        var installed = true
        var data = config
        let service = LowkeyIntegration(locate: { installed ? self.appURL : nil }, read: { data })
        service.refresh()
        XCTAssertEqual(service.sites.map(\.alias), ["work"])
        data = Data(#"{"sites":[{"alias":"mail","startURL":"https://mail.example.com"}]}"#.utf8)
        service.refresh()
        XCTAssertEqual(service.sites.map(\.alias), ["mail"])
        installed = false
        service.refresh()
        XCTAssertFalse(service.isInstalled)
        XCTAssertTrue(service.sites.isEmpty)
    }

    func testMalformedConfigClearsStaleSitesWithoutExposingItsContents() {
        var data = config
        let service = LowkeyIntegration(locate: { self.appURL }, read: { data })
        service.refresh()
        XCTAssertEqual(service.sites.count, 1)
        data = Data("private secret broken JSON".utf8)
        service.refresh()
        XCTAssertTrue(service.isInstalled)
        XCTAssertTrue(service.sites.isEmpty)
        XCTAssertNotNil(service.problem)
        XCTAssertFalse(service.problem?.contains("secret") ?? true)
    }

    func testOnlySupportedCommandsBecomeArguments() throws {
        XCTAssertEqual(LowkeySite.controlArguments(for: URL(string: "lowkey://HA")!), ["HA", "open"])
        XCTAssertEqual(LowkeySite.controlArguments(for: URL(string: "lowkey://Ha/TOGGLE/")!), ["Ha", "toggle"])
        for link in ["lowkey://*/toggle", "lowkey://HA/reload", "lowkey://HA/toggle/extra", "https://HA/toggle"] {
            XCTAssertNil(LowkeySite.controlArguments(for: try XCTUnwrap(URL(string: link))), link)
        }
    }

    func testControlRunsBundledExecutableWithTwoArgumentsAndNoURLFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let helpers = root.appendingPathComponent("Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = ActionRunner(locateLowkey: { root }, launchLowkey: { _, _ in XCTFail("unexpected URL launch") })
        let binding = Item.url("w", "Work", "lowkey://HA/toggle")
        let missing = await runner.run(binding)
        XCTAssertEqual(missing, .failed)
        let helper = helpers.appendingPathComponent("lowkeyctl")
        try "#!/bin/sh\n[ \"$#\" = 2 ] && [ \"$1\" = HA ] && [ \"$2\" = toggle ]\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let result = await runner.run(binding)
        XCTAssertEqual(result, .opened)
        let failed = await runner.openLowkeySite(URL(string: "lowkey://HA/open")!, name: "Work")
        XCTAssertEqual(failed, .failed)
    }

    func testRemovedLowkeyAndLaunchFailuresAreReportedWithoutOpeningOtherApps() async {
        var installed = true
        var attempts = 0
        var errors: [String] = []
        let runner = ActionRunner(locateLowkey: { installed ? self.appURL : nil }, launchLowkey: { _, _ in
            attempts += 1
            throw CocoaError(.fileReadNoSuchFile)
        })
        runner.onError = { errors.append($0) }
        let failed = await runner.run(.url("w", "Work", "lowkey://work/reload"))
        XCTAssertEqual(failed, .failed)
        installed = false
        let removed = await runner.run(.url("w", "Work", "lowkey://work/toggle"))
        XCTAssertEqual(removed, .failed)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(errors.count, 2)
    }

    func testMissingConfigIsAnEmptySiteList() {
        let service = LowkeyIntegration(locate: { self.appURL }, read: { throw CocoaError(.fileReadNoSuchFile) })
        service.refresh()
        XCTAssertTrue(service.isInstalled)
        XCTAssertTrue(service.sites.isEmpty)
        XCTAssertNil(service.problem)
    }
}

@MainActor private final class LowkeyTestOpener: LaunchaOpening {
    var outcome: LaunchOutcome = .opened
    var sites: [URL] = []
    var files: [URL] = []
    var revealed: [URL] = []
    func openApp(at url: URL, name: String) async -> LaunchOutcome { .opened }
    func openFile(_ url: URL, name: String) async -> LaunchOutcome { files.append(url); return .opened }
    func openLowkeySite(_ url: URL, name: String) async -> LaunchOutcome { sites.append(url); return outcome }
    func reveal(_ url: URL) -> LaunchOutcome { revealed.append(url); return .revealed }
}

@MainActor final class LowkeyLaunchaTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ting-lowkey-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func sites() throws -> [LowkeySite] {
        try LowkeySite.decode(Data(#"{"sites":[{"alias":"work","title":"Work Chat","startURL":"https://chat.example.com"}]}"#.utf8))
    }

    private func model(_ opener: LowkeyTestOpener, sites: @escaping () -> [LowkeySite],
                       refresh: Duration = .seconds(15), appRoots: [URL] = []) -> LaunchaModel {
        let home = root!
        return LaunchaModel(opener: opener, historyStore: LaunchaHistoryStore(url: home.appendingPathComponent("history.json")),
                            consent: LaunchaConsentStore(url: home.appendingPathComponent("consent.json")),
                            home: home, refreshInterval: refresh, lowkeySites: sites) { policy in
            LaunchaModel.Services(index: LaunchaAppIndex(home: home, protectedFolders: policy, roots: appRoots),
                                 spotlight: LaunchaSpotlight(home: home, protectedFolders: policy, debounce: .zero) { _ in [] })
        }
    }

    func testSearchesSitesByTitleAliasAndHostAndRecordsOnlySuccessfulOpen() async throws {
        let sites = try sites()
        let opener = LowkeyTestOpener()
        let model = model(opener, sites: { sites })
        for query in ["Work Chat", "work", "chat.example.com"] {
            model.open()
            model.query = query
            XCTAssertEqual(model.rows.map(\.id), [sites[0].id])
            XCTAssertTrue(model.selectedRow?.isLowkeySite == true)
            model.close()
        }
        model.open()
        model.query = "work"
        let opened = await model.activateSelection()
        XCTAssertEqual(opened, .opened)
        XCTAssertEqual(opener.sites, [sites[0].url()])
        XCTAssertTrue(opener.files.isEmpty)
        let snapshot = await model.historyStore.load()
        XCTAssertEqual(snapshot.history.entries[sites[0].id]?.events.count, 1)
        opener.outcome = .failed
        model.open()
        model.query = "work"
        let failed = await model.activateSelection()
        XCTAssertEqual(failed, .failed)
        let afterFailure = await model.historyStore.load()
        XCTAssertEqual(afterFailure.history.entries[sites[0].id]?.events.count, 1)
    }

    func testCommandReturnDoesNotRevealADeepLinkInFinder() async throws {
        let sites = try sites()
        let opener = LowkeyTestOpener()
        let model = model(opener, sites: { sites })
        model.open()
        model.query = "work"
        let result = await model.activateSelection(reveal: true)
        XCTAssertNil(result)
        XCTAssertTrue(opener.revealed.isEmpty)
        XCTAssertTrue(opener.sites.isEmpty)
    }

    func testSitesAppearAlongsideApplicationsAndRefreshWhileOpen() async throws {
        let folder = root.appendingPathComponent("Applications/Work Notes.app/Contents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let info = ["CFBundleName": "Work Notes", "CFBundleIdentifier": "io.bobuk.test.work", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: folder.appendingPathComponent("Info.plist"))
        var current = try sites()
        let model = model(LowkeyTestOpener(), sites: { current }, refresh: .milliseconds(20),
                          appRoots: [root.appendingPathComponent("Applications")])
        defer { model.close() }
        model.open()
        model.query = "work"
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !model.hasIndex, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.hasIndex)
        XCTAssertTrue(model.rows.contains(where: \.isApp))
        XCTAssertTrue(model.rows.contains(where: \.isLowkeySite))
        current = []
        while model.rows.contains(where: \.isLowkeySite), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.rows.contains(where: \.isLowkeySite))
        XCTAssertTrue(model.rows.contains(where: \.isApp))
    }

    func testRemovesStaleSitesOnReopen() throws {
        var sites = try sites()
        let model = model(LowkeyTestOpener(), sites: { sites })
        model.open()
        model.query = "work"
        XCTAssertEqual(model.rows.count, 1)
        model.close()
        sites = []
        model.open()
        XCTAssertFalse(model.rows.contains(where: \.isLowkeySite))
        model.close()
    }
}
