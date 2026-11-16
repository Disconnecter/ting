// The progress window of a Homebrew update: the command, the live output of brew and the result.
import AppKit
import Observation
import SwiftUI
import TingCore

@MainActor
@Observable
final class HomebrewUpdateModel {
    enum Phase: Equatable {
        case running
        case finished(HomebrewUpdateOutcome)
    }

    var command = ""
    var output = ""
    var phase: Phase = .running
    /// True after a success, while Ting quits so that the helper starts the new copy.
    var restarting = false

    var title: String {
        switch phase {
        case .running: "Updating Ting via Homebrew…"
        case .finished(.upgraded): restarting ? "Ting was updated. Restarting…" : "Ting was updated."
        case .finished(.upToDate): "Ting is already up to date."
        case .finished(.failed(let code, _)): "The update failed (brew exit code \(code))."
        case .finished(.cancelled): "The update was cancelled."
        }
    }

    var succeeded: Bool { phase == .finished(.upgraded) || phase == .finished(.upToDate) }

    /// Shows the result. A failure or cancel shows the text it carries: the whole brew output, or
    /// the reason why the run could not start when there is no log at all.
    func finish(_ outcome: HomebrewUpdateOutcome, log: String?) {
        switch outcome {
        case .failed(_, let text), .cancelled(let text):
            output = text.isEmpty ? (log ?? output) : text
        case .upgraded, .upToDate:
            output = log ?? output
        }
        phase = .finished(outcome)
    }
}

@MainActor
final class HomebrewUpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = HomebrewUpdateWindowController()

    private var window: NSWindow?
    private var runner: HomebrewUpdateRunner?
    private let model = HomebrewUpdateModel()

    /// Starts the update, or brings the running one to the front: a second start is refused.
    func start(_ install: HomebrewInstall) {
        // A run in progress, or a success while Ting quits to restart: show it, start nothing.
        if model.restarting || runner?.isRunning == true { show(); return }
        let runner = HomebrewUpdateRunner(install: install)
        self.runner = runner
        model.command = HomebrewUpdate.commandLine(for: install)
        model.output = ""
        model.phase = .running
        model.restarting = false
        show()
        runner.start(onOutput: { [weak self] in self?.model.output = $0 },
                     onFinish: { [weak self] in self?.finish($0) })
    }

    /// The copy that the helper started (`--homebrew-update-log`): it shows that run, live while
    /// brew still works, and takes over the restart after a success that it saw happen.
    func showRun(_ directory: URL) {
        if runner?.isRunning == true { show(); return }
        model.command = (try? String(contentsOf: directory.appendingPathComponent("command"), encoding: .utf8))
            ?? HomebrewUpdate.arguments.joined(separator: " ")
        model.output = HomebrewUpdateRunner.output(in: directory)
        model.phase = .running
        model.restarting = false
        // A result that is already there is the one this copy was restarted for: never restart again.
        let restartOnSuccess = HomebrewUpdateRunner.outcome(in: directory) == nil
        let runner = HomebrewUpdateRunner(install: nil)
        self.runner = runner
        show()
        runner.watch(directory, onOutput: { [weak self] in self?.model.output = $0 },
                     onFinish: { [weak self] in self?.finish($0, restart: restartOnSuccess) })
    }

    private func finish(_ outcome: HomebrewUpdateOutcome, restart: Bool = true) {
        model.finish(outcome, log: (runner?.directory).map(HomebrewUpdateRunner.output(in:)))
        guard outcome == .upgraded, restart else {
            runner?.acknowledge(relaunch: false)
            return
        }
        // Start Ting again from its installed place; the new copy shows this result again.
        model.restarting = true
        runner?.acknowledge(relaunch: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) }
    }

    private func cancel() { runner?.cancel() }

    private func show() {
        let window = self.window ?? makeWindow()
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window does not stop brew; the menu action shows it again.
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Update Ting via Homebrew"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: HomebrewUpdateView(
            model: model, cancel: { [weak self] in self?.cancel() }, close: { [weak window] in window?.close() }))
        self.window = window
        return window
    }
}

private struct HomebrewUpdateView: View {
    let model: HomebrewUpdateModel
    let cancel: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if model.phase == .running || model.restarting { ProgressView().controlSize(.small) }
                Text(model.title).font(.headline)
                    .foregroundStyle(model.phase == .running || model.succeeded ? Color.primary : Color.tingAmber)
            }
            Text(model.command)
                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.output.isEmpty ? "Waiting for brew…" : model.output)
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .foregroundStyle(model.output.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.output) { proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack {
                Text("Only Ting is updated. Settings, bindings and micro-apps are kept.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.phase == .running {
                    Button("Cancel", action: cancel)
                } else if !model.restarting {
                    Button("Close", action: close).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 340)
    }
}
