// Runs a binding or a launcha result: opens an app (or brings it to the front), a URL or a file.
// Every open reports a `LaunchOutcome`, so the caller can count successful launches once.
import AppKit
import TingCore

/// What launcha needs to open its results. `ActionRunner` is the real one; tests use a fake.
@MainActor
protocol LaunchaOpening: AnyObject {
    /// Opens the app at `url` (the retained bundle URL from the index), or activates it.
    func openApp(at url: URL, name: String) async -> LaunchOutcome
    /// Opens a file or folder with its usual app.
    func openFile(_ url: URL, name: String) async -> LaunchOutcome
    /// Shows the item in Finder. Never counts as a launch.
    func reveal(_ url: URL) -> LaunchOutcome
}

@MainActor
final class ActionRunner: LaunchaOpening {
    /// Reports a short, user-facing error. Never throws or crashes.
    var onError: ((String) -> Void)?
    private var appURLs: [String: URL] = [:]

    func prepare(_ items: [Item]) {
        appURLs.removeAll()
        func visit(_ items: [Item]) {
            for item in items {
                switch item.action {
                case .group(let children): visit(children)
                case .app(let id):
                    appURLs[id] = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                default: break
                }
            }
        }
        visit(items)
    }

    /// Starts activation synchronously, before the leader panel returns focus to another app.
    func activateRunning(_ item: Item) -> LaunchOutcome? {
        guard case .app(let id) = item.action,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
              app.activate(options: []) else { return nil }
        return .activated
    }

    /// Runs a selecta binding.
    func run(_ item: Item) async -> LaunchOutcome {
        switch item.action {
        case .group, .micro, .open:
            // A micro-app binding starts its flow in `MicroAppFlowController`, a panel binding opens
            // in `AppModel`, not here.
            return .failed
        case .app(let bundleID):
            let name = item.label.isEmpty ? bundleID : item.label
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
               app.activate(options: []) { return .activated }
            guard !bundleID.isEmpty, let url = appURLs[bundleID] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                onError?("\(name): app not found (\(bundleID.isEmpty ? "no bundle ID" : bundleID))")
                return .failed
            }
            appURLs[bundleID] = url
            return await openApp(at: url, name: name)
        case .url(let text):
            return openURL(text, label: item.label)
        }
    }

    func openApp(at url: URL, name: String) async -> LaunchOutcome {
        let running = NSWorkspace.shared.runningApplications.first { $0.bundleURL == url }
        if let running, running.activate(options: []) { return .activated }
        let wasRunning = running != nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return wasRunning ? .activated : .opened
        } catch {
            onError?("\(name): \(error.localizedDescription)")
            return .failed
        }
    }

    func openFile(_ url: URL, name: String) async -> LaunchOutcome {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            return .opened
        } catch {
            onError?("\(name): \(error.localizedDescription)")
            return .failed
        }
    }

    func reveal(_ url: URL) -> LaunchOutcome {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return .revealed
    }

    private func openURL(_ text: String, label: String) -> LaunchOutcome {
        let name = label.isEmpty ? text : label
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.isEmpty == false else {
            onError?("\(name): invalid URL")
            return .failed
        }
        guard NSWorkspace.shared.open(url) else {
            onError?("\(name): cannot open \(text)")
            return .failed
        }
        return .opened
    }

}
