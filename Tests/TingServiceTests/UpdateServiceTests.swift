import BobukUpdates
import Foundation
import Testing
import TingCore
@testable import Ting

/// Ting's wiring of BobukKit's updates: the identity, the menu titles and that a Homebrew copy never
/// creates Sparkle. The runner and the brew flow are tested in BobukKit.
@MainActor
@Suite struct UpdateServiceTests {
    private let install = HomebrewInstall(prefix: URL(fileURLWithPath: "/opt/homebrew"),
                                          record: URL(fileURLWithPath: "/opt/homebrew/Caskroom/ting/0.7.3/Ting.app"),
                                          app: URL(fileURLWithPath: "/Applications/Ting.app"),
                                          cask: AppUpdateIdentity.ting.cask)

    @Test func tingIdentity() {
        let ting = AppUpdateIdentity.ting
        #expect(ting.displayName == "Ting")
        #expect(ting.executableName == "Ting")
        #expect(ting.cask.name == "ting")
        #expect(ting.cask.tap == "bobuk-io/tap/ting")
        #expect(ting.cask.appBundleName == "Ting.app")
        #expect(HomebrewUpdate.arguments(for: ting.cask) == ["upgrade", "--cask", "--greedy", "bobuk-io/tap/ting"])
        #expect(ting.bundleIdentifier == "io.bobuk.ting")
        #expect(ting.keptNotice == "Settings, bindings and micro-apps are kept.")
        // The run folder of earlier Ting versions, so a restart after an update finds its run.
        #expect(ting.runBase == FileManager.default.temporaryDirectory.appendingPathComponent("io.bobuk.ting.homebrew-update"))
    }

    @Test func homebrewChoiceStartsNoSparkle() {
        var made = 0
        let service = UpdateService(app: .ting, choice: .homebrew(install), palette: TingPickerStyle.palette,
                                    makeSparkle: { made += 1; return FakeSparkle() })
        #expect(made == 0)
        #expect(service.homebrew == install)
        #expect(!service.isAvailable)
        #expect(service.menuTitle == "Update Ting via Homebrew…")
    }

    @Test func sparkleAndNone() {
        var made = 0
        let sparkle = UpdateService(app: .ting, choice: .sparkle, makeSparkle: { made += 1; return FakeSparkle() })
        #expect(made == 1)
        #expect(sparkle.isAvailable)
        #expect(sparkle.homebrew == nil)
        #expect(sparkle.menuTitle == "Check for Updates…")
        #expect(sparkle.automaticallyChecks)

        let none = UpdateService(app: .ting, choice: .none, makeSparkle: { made += 1; return FakeSparkle() })
        #expect(made == 1)
        #expect(!none.isAvailable)
        #expect(none.menuTitle == nil)
    }

    /// `swift test` runs no app bundle: the shared service has no updates and creates no Sparkle.
    @Test func developmentBuildHasNoUpdates() {
        #expect(UpdateService.shared.choice == .none)
        #expect(UpdateService.shared.menuTitle == nil)
    }
}

@MainActor
private final class FakeSparkle: SparkleUpdating {
    var automaticallyChecks = true
    var canCheck = true
    func check() {}
}
