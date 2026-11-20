// The Settings window: BobukKit's `ChromeWindow` in Ting's palette. The window draws the accent
// line and the strip with its close button (also ⌘W); the content fills the window's body.
import AppKit
import BobukUI
import SwiftUI
import TingCore

@MainActor
enum SettingsWindow {
    static let title = "Ting Settings"
    static let identifier = NSUserInterfaceItemIdentifier("io.bobuk.ting.settings")
    static let frameName = "io.bobuk.ting.settings.frame"
    /// The pages are laid out for at least this much room below the strip.
    static let minimumContentSize = NSSize(width: 900, height: 600)

    /// A Settings window whose body is `contentSize`. The content is added by the caller.
    static func make(contentSize: NSSize = NSSize(width: 1040, height: 720)) -> ChromeWindow {
        let window = ChromeWindow(contentRect: NSRect(origin: .zero, size: ChromeMetrics.windowSize(forBody: contentSize)),
                                  style: TingPickerStyle.palette.chromeStyle, resizable: true)
        window.title = title
        window.identifier = identifier
        window.contentMinSize = ChromeMetrics.windowSize(forBody: minimumContentSize)
        return window
    }
}

/// The one Settings window. Its content is released on close, so a shortcut recorder cannot keep
/// intercepting keys.
@MainActor
final class SettingsWindowController {
    private let hosted: HostedWindowController

    init(model: AppModel, remembersFrame: Bool = true) {
        hosted = HostedWindowController(frameName: remembersFrame ? SettingsWindow.frameName : nil,
                                        releasesContentOnClose: true,
                                        window: { SettingsWindow.make() },
                                        rootView: { SettingsRoot().environment(model) })
    }

    var window: NSWindow? { hosted.window }

    func show(activate: Bool = true) { hosted.show(activate: activate) }

    func close() { hosted.close() }
}
