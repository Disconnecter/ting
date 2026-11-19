// The clipboard history. Disk work is serialized off the UI thread; tests opt into a temp store.
import AppKit
import Observation
import TingCore

@MainActor
@Observable
final class ClipbawdHistory {
    private(set) var history = ClipHistory()
    private(set) var settings = ClipbawdSettings()
    private(set) var storageError: String?
    private(set) var storedBytes = 0
    private(set) var isLoading = false
    @ObservationIgnored let monitor: ClipboardMonitor
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fetcher: LinkPreviewFetcher
    @ObservationIgnored private let disk: ClipHistoryDisk?
    @ObservationIgnored private let io = DispatchQueue(label: "io.bobuk.ting.clipbawd-storage", qos: .utility)
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var cleanupTimer: Timer?
    @ObservationIgnored private var fetching: [Int: Task<Void, Never>] = [:]

    init(monitor: ClipboardMonitor? = nil, pasteboard: NSPasteboard = .general, now: @escaping () -> Date = Date.init,
         fetcher: LinkPreviewFetcher = LinkPreviewFetcher(), directory: URL? = nil) {
        self.pasteboard = pasteboard
        self.fetcher = fetcher
        self.monitor = monitor ?? ClipboardMonitor(pasteboard: pasteboard)
        self.now = now
        disk = directory.map(ClipHistoryDisk.init(directory:))
        self.monitor.onCapture = { [weak self] capture in self?.record(capture) }
    }

    deinit { cleanupTimer?.invalidate() }

    var entries: [ClipEntry] { history.entries }

    func microAppSnapshot() -> [String?]? {
        guard settings.enabled else { return nil }
        monitor.poll()
        return entries.map { entry in
            switch entry.content {
            case .text(let text, _), .link(let text), .color(let text): return text
            case .files(let files): return files.map(\.path).joined(separator: "\n")
            case .image, .video: return nil
            }
        }
    }

    func configure(_ next: ClipbawdSettings) {
        let wasPersistent = configured && settings.enabled && settings.persistent
        let wasFetching = settings.fetchLinks
        let first = !configured
        configured = true
        settings = next
        history.apply(next, at: now())
        let persistent = next.enabled && next.persistent
        if !next.enabled {
            monitor.stop()
            ClipboardWriter.clearVideoExport(from: pasteboard)
            history.removeAll()
        }
        if first || wasPersistent != persistent {
            generation += 1
            isLoading = false
            if persistent, first, let disk {
                // Do not read the live clipboard while the saved history is being restored.
                isLoading = true
                monitor.stop()
                let token = generation
                io.async { [weak self] in
                    let result = Result { try disk.load() }
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        self.isLoading = false
                        switch result {
                        case .success(var restored):
                            restored.apply(self.settings, at: self.now())
                            if !self.settings.fetchLinks {
                                for entry in restored.entries where entry.link?.state == .loading {
                                    restored.setLink(ClipLinkPreview(state: .failed("Loading links is off.")), for: entry.id)
                                }
                            }
                            self.history = restored
                            self.persist()
                        case .failure(let error):
                            self.storageError = "History could not be restored: \(error.localizedDescription). Clear History to reset it."
                        }
                        if self.settings.enabled { self.monitor.start() }
                        self.loadLinks()
                    }
                }
            } else if !persistent {
                ClipboardWriter.clearVideoExport(from: pasteboard)
                deleteStoredHistory()
            }
        }
        if next.enabled, !isLoading { monitor.start() }
        if next.enabled, cleanupTimer == nil {
            let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.cleanup() }
            }
            timer.tolerance = 60
            RunLoop.main.add(timer, forMode: .common)
            cleanupTimer = timer
        } else if !next.enabled {
            cleanupTimer?.invalidate()
            cleanupTimer = nil
        }
        if !next.fetchLinks || !next.enabled {
            for (id, task) in fetching {
                task.cancel()
                history.setLink(ClipLinkPreview(state: .failed("Loading links is off.")), for: id)
            }
            fetching.removeAll()
        } else if !wasFetching, !isLoading {
            loadLinks()
        }
        if !isLoading { persist() }
    }

    func cleanup() {
        history.prune(at: now())
        persist()
    }

    private func loadLinks() {
        guard settings.fetchLinks else { return }
        for entry in history.entries.prefix(20) where entry.link?.state != .done { fetchLink(entry.id) }
    }

    @discardableResult
    func record(_ capture: ClipCapture) -> ClipRecordResult {
        guard settings.enabled else { return .skipped(.disabled) }
        let result = history.record(capture, rules: settings.rules, at: now())
        switch result {
        case .added(let id), .merged(let id):
            persist()
            if settings.fetchLinks, history.entry(id: id)?.link?.state != .done { fetchLink(id) }
        case .skipped: break
        }
        return result
    }

    private func fetchLink(_ id: Int) {
        guard fetching[id] == nil, let entry = history.entry(id: id), case .link(let url) = entry.content else { return }
        history.setLink(ClipLinkPreview(state: .loading), for: id)
        fetching[id] = Task { [weak self, fetcher] in
            let preview = await fetcher.preview(for: url)
            guard let self, !Task.isCancelled, self.settings.enabled, self.settings.fetchLinks else { return }
            self.fetching[id] = nil
            self.history.setLink(preview, for: id)
            self.history.prune(at: self.now())
            self.persist()
        }
    }

    func copy(id: Int) -> Bool {
        guard let entry = history.entry(id: id) else { return false }
        let previous = pasteboard.changeCount
        let written = ClipboardWriter.write(entry, to: pasteboard)
        guard written != previous else { return false }
        monitor.ignore(changeCount: written)
        history.promote(id: id, at: now())
        persist()
        return true
    }

    func remove(id: Int) { history.remove(id: id); persist() }

    func clear() {
        if isLoading {
            generation += 1
            isLoading = false
            if settings.enabled { monitor.start() }
        }
        ClipboardWriter.clearVideoExport(from: pasteboard)
        history.removeAll()
        for task in fetching.values { task.cancel() }
        fetching.removeAll()
        // Also resets an unreadable archive; never leave secret remnants behind on Clear.
        storageError = nil
        deleteStoredHistory()
    }

    func setLink(_ preview: ClipLinkPreview, for id: Int) {
        history.setLink(preview, for: id)
        history.prune(at: now())
        persist()
    }

    private func persist() {
        guard settings.enabled, settings.persistent, !isLoading, let disk else { return }
        revision += 1
        let serial = revision
        let token = generation
        let snapshot = history
        io.async { [weak self] in
            let result = Result { try disk.save(snapshot) }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.revision == serial else { return }
                switch result {
                case .success(let saved):
                    self.history = saved.history
                    self.storedBytes = saved.bytes
                    self.storageError = nil
                case .failure(let error): self.storageError = "History was not saved: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteStoredHistory() {
        guard let disk else { return }
        revision += 1
        let serial = revision
        let token = generation
        io.async { [weak self] in
            let result = Result { try disk.delete() }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.revision == serial else { return }
                switch result {
                case .success: self.storedBytes = 0; self.storageError = nil
                case .failure(let error): self.storageError = "Stored history was not deleted: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Finish queued saves/deletions before normal application termination.
    func finishStorage(_ completion: @escaping () -> Void) {
        monitor.stop()
        cleanupTimer?.invalidate()
        io.async { DispatchQueue.main.async(execute: completion) }
    }

    /// Test barrier for the serial disk queue (and its main-actor completions).
    func waitForStorage() async {
        await withCheckedContinuation { continuation in
            io.async { DispatchQueue.main.async { continuation.resume() } }
        }
        await Task.yield()
    }
}
