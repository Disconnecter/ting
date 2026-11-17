// The clipboarda history of this session: the monitor feeds it, the panel reads it, copy and
// paste put an item back. Lives in memory only and is gone when Ting quits.
import AppKit
import Observation
import TingCore

@MainActor
@Observable
final class ClipboardaHistory {
    private(set) var history = ClipHistory()
    @ObservationIgnored private(set) var settings = ClipboardaSettings()
    @ObservationIgnored let monitor: ClipboardMonitor
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fetcher: LinkPreviewFetcher
    /// Links being loaded, by item id.
    @ObservationIgnored private var fetching: [Int: Task<Void, Never>] = [:]

    init(monitor: ClipboardMonitor? = nil, pasteboard: NSPasteboard = .general, now: @escaping () -> Date = Date.init,
         fetcher: LinkPreviewFetcher = LinkPreviewFetcher()) {
        self.pasteboard = pasteboard
        self.fetcher = fetcher
        self.monitor = monitor ?? ClipboardMonitor(pasteboard: pasteboard)
        self.now = now
        self.monitor.onCapture = { [weak self] capture in self?.record(capture) }
    }

    var entries: [ClipEntry] { history.entries }

    /// Applies the config. Turning recording off forgets the history.
    func configure(_ next: ClipboardaSettings) {
        let wasFetching = settings.fetchLinks
        settings = next
        history.maxItems = next.maxItems
        history.prune()
        for app in next.excludedApps { history.removeAll(fromApp: app) }
        if next.enabled {
            monitor.start()
        } else {
            monitor.stop()
            history.removeAll()
        }
        if next.fetchLinks {
            guard !wasFetching else { return }
            // Just turned on: load the newest links that have no preview yet.
            for entry in history.entries.prefix(20) where entry.link?.state != .done { fetchLink(entry.id) }
        } else {
            for (id, task) in fetching {
                task.cancel()
                history.setLink(ClipLinkPreview(state: .failed("Loading links is off.")), for: id)
            }
            fetching.removeAll()
        }
    }

    @discardableResult
    func record(_ capture: ClipCapture) -> ClipRecordResult {
        guard settings.enabled else { return .skipped(.disabled) }
        let result = history.record(capture, rules: settings.rules, at: now())
        switch result {
        case .added(let id), .merged(let id):
            if settings.fetchLinks, history.entry(id: id)?.link?.state != .done { fetchLink(id) }
        case .skipped:
            break
        }
        return result
    }

    /// Loads the preview of a link item once; the result is dropped if fetching was turned off.
    private func fetchLink(_ id: Int) {
        guard fetching[id] == nil, let entry = history.entry(id: id), case .link(let url) = entry.content else { return }
        history.setLink(ClipLinkPreview(state: .loading), for: id)
        fetching[id] = Task { [weak self, fetcher] in
            let preview = await fetcher.preview(for: url)
            guard let self, !Task.isCancelled, self.settings.fetchLinks else { return }
            self.fetching[id] = nil
            self.history.setLink(preview, for: id)
        }
    }

    /// Puts the item on the clipboard and moves it to the top; the monitor skips this write.
    func copy(id: Int) -> Bool {
        guard let entry = history.entry(id: id) else { return false }
        monitor.ignore(changeCount: ClipboardWriter.write(entry, to: pasteboard))
        history.promote(id: id, at: now())
        return true
    }

    func remove(id: Int) { history.remove(id: id) }

    func clear() { history.removeAll() }

    func setLink(_ preview: ClipLinkPreview, for id: Int) { history.setLink(preview, for: id) }
}
