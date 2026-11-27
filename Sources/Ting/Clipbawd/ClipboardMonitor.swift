// Watches the clipboard for clipbawd. macOS has no change notification, so the monitor reads
// only `changeCount` twice a second and loads the data of a few known types after a change.
import AppKit
import Carbon
import ImageIO
import TingCore
import TingRuntime

/// While Ting copies the selection of another app with ⌘C (a micro-app context), that copy is
/// not the person's and is never kept.
@MainActor
enum ClipboardQuiet {
    private(set) static var depth = 0
    static var isActive: Bool { depth > 0 }
    static func begin() { depth += 1 }
    static func end() { depth = max(0, depth - 1) }
}

/// Tells whether the front window of a browser is private.
@MainActor
protocol ClipPrivacyChecking: AnyObject {
    func isPrivate(_ check: ClipPrivateWindow.Check, pid: pid_t, bundleID: String) async -> Bool
}

@MainActor
final class ClipPrivacyChecker: ClipPrivacyChecking {
    func isPrivate(_ check: ClipPrivateWindow.Check, pid: pid_t, bundleID: String) async -> Bool {
        switch check {
        case .title:
            guard AXIsProcessTrusted() else { return false }
            return ClipPrivateWindow.isPrivate(title: MicroAppAccessibility.window(pid: pid).title)
        case .script(let script):
            // Never shows the Automation prompt on a copy: without the permission the copy is kept.
            guard await Self.automationAllowed(bundleID: bundleID) else { return false }
            let result = await MicroAppScript.run(script, timeLimit: 3)
            return result.end == .success && ClipPrivateWindow.isPrivate(mode: result.stdout)
        }
    }

    nonisolated static func automationAllowed(bundleID: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let desc = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else {
                    return continuation.resume(returning: false)
                }
                continuation.resume(returning: AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false) == noErr)
            }
        }
    }
}

@MainActor
final class ClipboardMonitor {
    static let interval: TimeInterval = 0.5

    /// The app in front at a change: the best guess of where the copy came from.
    struct FrontApp: Equatable {
        var pid: pid_t
        var bundleID: String?
        var name: String

        static func current() -> FrontApp? {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            return FrontApp(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                            name: app.localizedName ?? app.bundleIdentifier ?? "Unknown app")
        }
    }

    /// A change to keep or skip; the history decides.
    var onCapture: ((ClipCapture) -> Void)?

    private let pasteboard: NSPasteboard
    private let frontmost: @MainActor () -> FrontApp?
    private let secureInput: @MainActor () -> Bool
    private let privacy: ClipPrivacyChecking
    private var lastChange: Int
    /// Change counts of Ting's own writes (copy or paste from the history).
    private var ignored: Set<Int> = []
    private var timer: Timer?
    private var generation = 0

    init(pasteboard: NSPasteboard = .general,
         frontmost: @escaping @MainActor () -> FrontApp? = { FrontApp.current() },
         secureInput: @escaping @MainActor () -> Bool = { IsSecureEventInputEnabled() },
         privacy: ClipPrivacyChecking? = nil) {
        self.pasteboard = pasteboard
        self.frontmost = frontmost
        self.secureInput = secureInput
        self.privacy = privacy ?? ClipPrivacyChecker()
        lastChange = pasteboard.changeCount
    }

    var isRunning: Bool { timer != nil }

    /// Starts from the current clipboard: what was copied before is not recorded.
    func start() {
        guard timer == nil else { return }
        lastChange = pasteboard.changeCount
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = Self.interval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        ignored.removeAll()
    }

    /// The change with this count is Ting's own write and is not recorded.
    func ignore(changeCount: Int) { ignored.insert(changeCount) }

    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChange else { return }
        lastChange = count
        let own = ignored.contains(count)
        ignored = ignored.filter { $0 > count }
        guard !own, !ClipboardQuiet.isActive else { return }

        // Secure input (a password field): the data is never read, only skipped.
        let secure = secureInput()
        var capture = secure ? ClipCapture(types: pasteboard.types?.map(\.rawValue) ?? []) : Self.read(pasteboard)
        let app = frontmost()
        if let app { capture.source = ClipSource(bundleID: app.bundleID, name: app.name) }
        capture.privateContext = secure
        let marked = capture.types.contains(where: ClipboardTypes.skipMarkers.contains)
        if !capture.privateContext, !marked, let app, let id = app.bundleID,
           let check = ClipPrivateWindow.check(for: id) {
            let pid = app.pid
            let token = generation
            Task { [weak self, privacy] in
                capture.privateContext = await privacy.isPrivate(check, pid: pid, bundleID: id)
                guard let self, self.generation == token else { return }
                self.deliver(capture)
            }
            return
        }
        deliver(capture)
    }

    private func deliver(_ capture: ClipCapture) {
        guard !capture.privateContext, !capture.types.contains(where: ClipboardTypes.skipMarkers.contains),
              ClipVideoCapture.needsInspection(capture) else {
            onCapture?(capture)
            return
        }
        let token = generation
        Task { [weak self] in
            let prepared = await Task.detached(priority: .utility) { await ClipVideoCapture.prepare(capture) }.value
            guard let self, self.generation == token else { return }
            self.onCapture?(prepared)
        }
    }

    /// The types list, and the data of the known types unless a marker says not to keep it.
    static func read(_ pasteboard: NSPasteboard) -> ClipCapture {
        let types = pasteboard.types?.map(\.rawValue) ?? []
        var capture = ClipCapture(types: types)
        guard !types.contains(where: ClipboardTypes.skipMarkers.contains) else { return capture }
        let items = pasteboard.pasteboardItems ?? []

        let fileType = NSPasteboard.PasteboardType(ClipboardTypes.fileURL)
        if types.contains(ClipboardTypes.fileURL) {
            (capture.files, capture.representations) = files(items.compactMap { $0.string(forType: fileType) })
        }
        guard capture.files.isEmpty, let first = items.first else { return capture }

        let known = ClipboardTypes.read.filter { $0 != ClipboardTypes.fileURL }
        let present = Set(first.types.map(\.rawValue))
        for type in known where present.contains(type) {
            if let data = first.data(forType: NSPasteboard.PasteboardType(type)) {
                capture.representations.append(ClipRepresentation(type: type, data: data))
            }
        }
        capture.text = first.string(forType: .string)
            ?? first.string(forType: NSPasteboard.PasteboardType(ClipboardTypes.markdown))
        let images = [ClipboardTypes.png, ClipboardTypes.tiff, ClipboardTypes.jpeg]
        if let image = capture.representations.first(where: { images.contains($0.type) }) {
            capture.image = imageInfo(image.data, type: image.type)
        }
        return capture
    }

    /// Size and format from the image header; the pixels are not decoded.
    static func imageInfo(_ data: Data, type: String) -> ClipImageInfo? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let format = switch type {
        case ClipboardTypes.png: "PNG"
        case ClipboardTypes.jpeg: "JPEG"
        default: "TIFF"
        }
        return ClipImageInfo(width: width, height: height, format: format, byteCount: data.count)
    }

    /// Files of `public.file-url` strings; anything that is not a file URL is left out.
    static func files(_ strings: [String]) -> ([ClipFile], [ClipRepresentation]) {
        var files: [ClipFile] = []
        var representations: [ClipRepresentation] = []
        for string in strings {
            guard let url = URL(string: string), url.isFileURL else { continue }
            files.append(file(url))
            representations.append(ClipRepresentation(type: ClipboardTypes.fileURL, data: Data(string.utf8)))
        }
        return (files, representations)
    }

    static func file(_ url: URL) -> ClipFile {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let isDirectory = values?.isDirectory ?? false
        return ClipFile(path: url.path, byteCount: isDirectory ? nil : values?.fileSize.map(Int64.init), isDirectory: isDirectory)
    }
}

/// Puts a history item back on the clipboard.
@MainActor
enum ClipboardWriter {
    /// Writes only the text, so the target app pastes it in its own style. Returns the new change count.
    @discardableResult
    static func writePlainText(_ text: String, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// Writes every kept representation; files as one item per file. Returns the new change count.
    @discardableResult
    static func write(_ entry: ClipEntry, to pasteboard: NSPasteboard) -> Int {
        let objects: [NSPasteboardItem]
        if case .files = entry.content {
            objects = entry.representations.filter { $0.type == ClipboardTypes.fileURL }.map {
                let item = NSPasteboardItem()
                item.setData($0.data, forType: NSPasteboard.PasteboardType(ClipboardTypes.fileURL))
                return item
            }
        } else {
            let item = NSPasteboardItem()
            if case .video = entry.content,
               let movie = entry.representations.first(where: { ClipboardTypes.videoTypes.contains($0.type) }) {
                guard let url = try? videoExport(movie, to: pasteboard) else { return pasteboard.changeCount }
                item.setString(url.absoluteString, forType: .fileURL)
            }
            for representation in entry.representations {
                item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
            }
            objects = [item]
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(objects)
        return pasteboard.changeCount
    }

    private static func exportDirectory(for pasteboard: NSPasteboard) -> URL {
        let key = ClipDigest(Data(pasteboard.name.rawValue.utf8)).bytes.prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory.appendingPathComponent("io.bobuk.ting.clipbawd-export-" + key)
    }

    static func clearVideoExport(from pasteboard: NSPasteboard) {
        try? FileManager.default.removeItem(at: exportDirectory(for: pasteboard))
    }

    /// Only the current clipboard movie needs a file URL; no growing shadow history.
    private static func videoExport(_ representation: ClipRepresentation, to pasteboard: NSPasteboard) throws -> URL {
        let exportDirectory = exportDirectory(for: pasteboard)
        let fm = FileManager.default
        if fm.fileExists(atPath: exportDirectory.path) { try fm.removeItem(at: exportDirectory) }
        try fm.createDirectory(at: exportDirectory, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        let url = exportDirectory.appendingPathComponent(representation.type == ClipboardTypes.quickTime ? "Video.mov" : "Video.mp4")
        try representation.data.write(to: url)
        return url
    }
}
