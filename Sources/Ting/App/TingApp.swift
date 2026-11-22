// Ting: a leader-key launcher that lives in the menu bar (LSUIElement, no Dock icon).
import AppKit
import BobukUI
import BobukUpdates
import SwiftUI
import TingCore

struct TingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Keep standard application/edit commands, but never open SwiftUI's titled Settings host.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { SettingsOpener.open() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared
    private var statusItem: StatusItemController?
    private lazy var welcome = WelcomeWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        _ = UpdateService.shared
        statusItem = StatusItemController(model: model,
                                          openSettings: { SettingsOpener.open() },
                                          openWelcome: { [weak self] in self?.welcome.show() })
        if model.config.leaders.isEmpty { welcome.show() }
        // Started by the Homebrew update helper: show the command, the output and the result of that run.
        HomebrewLaunch.showResultIfRequested(app: .ting, theme: .ting)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.clipbawd.finishStorage { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    /// Opening Ting again (Finder, Spotlight) shows Settings, or Welcome when there is no leader yet.
    /// This is the way back when the menu-bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.config.leaders.isEmpty { welcome.show() } else { SettingsOpener.open() }
        return false
    }
}

/// Every Settings entry point uses the same single BobukKit window.
@MainActor
enum SettingsOpener {
    private static let controller = SettingsWindowController(model: AppModel.shared)

    /// ⌘, as in every Mac app. Ting is not the active app while a launcher panel has the
    /// keys, so its menu never sees the shortcut; the panels check for it themselves.
    /// Matched by the Latin layout, so it also works with Ukrainian or Russian input.
    nonisolated static func isShortcut(latin: String?, flags: NSEvent.ModifierFlags) -> Bool {
        latin == "," && flags.intersection([.command, .shift, .option, .control]) == .command
    }

    static func open() { controller.show() }
}
