// First launch: there is no default leader; Ting asks for one and starts listening at once.
import AppKit
import SwiftUI
import TingCore
import BobukUI

/// The Welcome window: a fixed `ChromeWindow` sized to its content. Its content is released on
/// close, so the leader recorder stops (its onDisappear runs).
@MainActor
final class WelcomeWindowController {
    private let hosted: HostedWindowController

    init(model: AppModel) {
        // Set once the hosted controller exists; the Continue button closes through it.
        weak var weakHosted: HostedWindowController?
        hosted = HostedWindowController(window: {
            let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                                      theme: model.theme, resizable: false)
            window.title = "Welcome to Ting"
            window.isMovableByWindowBackground = true
            return window
        }, rootView: { WelcomeView { weakHosted?.close() }.environment(model) })
        hosted.sizesToFitContent = true
        weakHosted = hosted
    }

    var window: NSWindow? { hosted.window }

    /// Centered on every open, as before.
    func show() {
        hosted.prepare().center()
        hosted.show()
    }

    func close() { hosted.close() }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    let onContinue: () -> Void

    var body: some View {
        let ready = !model.config.leaders.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TingMark(size: 14)
                MonoLabel("Ting", size: 11, tracking: 2)
                Spacer()
                MonoLabel("01 / setup", size: 10, weight: .regular, tracking: 1).foregroundStyle(Color.tingMuted)
            }
            Text("Pick your leader.").font(.system(size: 27, weight: .medium)).tracking(-0.7).padding(.top, 18)
            Text("One shortcut opens Ting from anywhere. Then a key or two launches an app or a link.")
                .font(.system(size: 12)).foregroundStyle(Color.tingMuted).padding(.top, 7)
                .fixedSize(horizontal: false, vertical: true)
            LeaderField(large: true, autoStart: true).padding(.top, 20)
            Rectangle().fill(Color.tingInk.opacity(0.12)).frame(height: 1).padding(.top, 20)
            HStack {
                MonoLabel(ready ? "ready" : "waiting for a key", size: 9, weight: .regular, tracking: 1)
                    .foregroundStyle(ready ? Color.tingAmber : Color.tingMuted)
                Spacer()
                Button("Continue", action: onContinue)
                    .buttonStyle(.tingQuiet(prominent: ready))
                    .disabled(!ready)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .foregroundStyle(Color.tingInk)
        .padding(24)
        .padding(.top, 8)
        .frame(width: 440)
        .background(Color.tingPanel)
    }
}
