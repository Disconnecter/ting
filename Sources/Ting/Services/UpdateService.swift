// Updates through BobukKit's `UpdateService`: a copy that Homebrew manages updates with brew only,
// from a progress window, and Sparkle is not created for it at all. Every other release copy
// updates with Sparkle from the public feed (`SUFeedURL` in Info.plist), verified with the EdDSA
// public key in `SUPublicEDKey` and by Apple's code signature checks. Sparkle is not a kit
// dependency: this file holds Ting's adapter.
import AppKit
import BobukUpdates
import Sparkle
import TingCore

@MainActor
final class SparkleUpdater: SparkleUpdating {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                          userDriverDelegate: nil)
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var canCheck: Bool { controller.updater.canCheckForUpdates }
    func check() { controller.checkForUpdates(nil) }
}

extension AppUpdateIdentity {
    static let ting = AppUpdateIdentity(displayName: "Ting", executableName: "Ting",
                                        cask: HomebrewCask(name: "ting", appBundleName: "Ting.app"),
                                        bundleIdentifier: "io.bobuk.ting",
                                        keptNotice: "Settings, bindings and micro-apps are kept.")
}

extension UpdateService {
    /// The updater of the running copy: Homebrew, Sparkle or nothing (development builds).
    static let shared = UpdateService.detect(app: .ting, palette: TingPickerStyle.palette,
                                             makeSparkle: { SparkleUpdater() })
}
