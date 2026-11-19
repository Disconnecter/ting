import AppKit
import AVFoundation
import XCTest
import TingCore
@testable import Ting

@MainActor
final class ClipPersistenceTests: XCTestCase {
    private func capture(_ text: String) -> ClipCapture {
        ClipCapture(types: [ClipboardTypes.plainText], text: text,
                    representations: [.init(type: ClipboardTypes.plainText, data: Data(text.utf8))])
    }

    private func board() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("io.bobuk.ting.persistence-tests." + UUID().uuidString))
    }

    func testRestoreDeleteAndNoResurrection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = ClipHistoryDisk(directory: directory)
        defer { try? disk.delete() }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        var settings = ClipbawdSettings()
        settings.persistent = true
        let first = ClipbawdHistory(pasteboard: pasteboard, directory: directory)
        first.configure(settings)
        await first.waitForStorage()
        first.record(capture("restored"))
        await first.waitForStorage()
        first.monitor.stop()
        XCTAssertEqual(try disk.load().entries.map(\.title), ["restored"])

        let second = ClipbawdHistory(pasteboard: pasteboard, directory: directory)
        second.configure(settings)
        await second.waitForStorage()
        XCTAssertEqual(second.entries.map(\.title), ["restored"])
        XCTAssertFalse(second.isLoading)
        second.clear()
        await second.waitForStorage()
        XCTAssertFalse(FileManager.default.fileExists(atPath: disk.file.path))
        XCTAssertTrue(second.entries.isEmpty)
        second.record(capture("memory"))
        settings.persistent = false
        second.configure(settings)
        await second.waitForStorage()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(second.entries.map(\.title), ["memory"])
        XCTAssertEqual(second.storedBytes, 0)
        second.monitor.stop()

        let third = ClipbawdHistory(pasteboard: pasteboard, directory: directory)
        settings.persistent = true
        third.configure(settings)
        third.clear() // While load is in flight: a late completion must not resurrect history.
        await third.waitForStorage()
        XCTAssertTrue(third.entries.isEmpty)
        XCTAssertFalse(third.isLoading)
        third.monitor.stop()
    }

    func testHourlyCleanupAndConfigChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = ClipHistoryDisk(directory: directory)
        defer { try? disk.delete() }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        var now = Date()
        let history = ClipbawdHistory(pasteboard: pasteboard, now: { now }, directory: directory)
        var settings = ClipbawdSettings()
        settings.persistent = true
        settings.maxDays = 1
        history.configure(settings)
        await history.waitForStorage()
        history.record(capture("expired"))
        now += 86_401
        history.cleanup()
        await history.waitForStorage()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertTrue(try disk.load().entries.isEmpty)
        history.record(capture("secret-value"))
        settings.ignoredPrefixes = ["secret-"]
        history.configure(settings)
        await history.waitForStorage()
        XCTAssertTrue(try disk.load().entries.isEmpty)
        history.monitor.stop()
    }

    func testCorruptionAndDeletionErrorsAreVisible() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = ClipHistoryDisk(directory: directory)
        defer { try? disk.delete() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: disk.file)
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let history = ClipbawdHistory(pasteboard: pasteboard, directory: directory)
        var settings = ClipbawdSettings()
        settings.persistent = true
        history.configure(settings)
        await history.waitForStorage()
        XCTAssertNotNil(history.storageError)
        history.clear()
        await history.waitForStorage()
        XCTAssertNil(history.storageError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        history.monitor.stop()
    }

    func testMarkdownRetainsSourceAndDoesNotCreateLinksOrImages() {
        let source = "# Heading\n**bold** `code`\n![secret](https://example.org/private.png)"
        let highlighted = ClipMarkdown.highlight(source)
        XCTAssertEqual(String(highlighted.characters), source)
        XCTAssertTrue(highlighted.runs.contains { $0.foregroundColor != nil })
        XCTAssertTrue(highlighted.runs.allSatisfy { $0.link == nil })
    }

    func testMoviePayloadSurvivesSourceDeletionAndRestoresFileURL() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("demo.mov")
        try await makeVideo(url: url, duration: 1)
        let original = ClipCapture(types: [ClipboardTypes.fileURL], files: [ClipboardMonitor.file(url)],
                                   representations: [.init(type: ClipboardTypes.fileURL, data: Data(url.absoluteString.utf8))])
        let prepared = await ClipVideoCapture.prepare(original)
        XCTAssertFalse(prepared.rejectedVideo)
        XCTAssertNotNil(prepared.video?.thumbnail)
        XCTAssertEqual(prepared.video?.duration ?? 0, 1, accuracy: 0.1)
        try FileManager.default.removeItem(at: url)
        var history = ClipHistory()
        _ = history.record(prepared, rules: .init(), at: Date())
        let restored = try ClipHistory.decode(history.encoded())
        let entry = try XCTUnwrap(restored.entries.first)
        let pasteboard = board()
        defer { ClipboardWriter.clearVideoExport(from: pasteboard); pasteboard.releaseGlobally() }
        ClipboardWriter.write(entry, to: pasteboard)
        let fileURL = try XCTUnwrap(pasteboard.string(forType: .fileURL).flatMap(URL.init(string:)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL), prepared.representations.first?.data)

        let longURL = directory.appendingPathComponent("too-long.mov")
        try await makeVideo(url: longURL, duration: 31)
        let long = ClipCapture(types: [ClipboardTypes.fileURL], files: [ClipboardMonitor.file(longURL)])
        let rejected = await ClipVideoCapture.prepare(long)
        XCTAssertTrue(rejected.rejectedVideo)
        XCTAssertNil(ClipContent.classify(rejected))
    }

    func testRawMovieAndPrivateExportCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("demo.mov")
        try await makeVideo(url: source, duration: 1)
        let bytes = try Data(contentsOf: source)
        let prepared = await ClipVideoCapture.prepare(.init(types: [ClipboardTypes.quickTime],
            representations: [.init(type: ClipboardTypes.quickTime, data: bytes)]))
        XCTAssertFalse(prepared.rejectedVideo)
        let pasteboard = board()
        defer { ClipboardWriter.clearVideoExport(from: pasteboard); pasteboard.releaseGlobally() }
        let history = ClipbawdHistory(pasteboard: pasteboard)
        history.configure(ClipbawdSettings())
        history.record(prepared)
        let id = try XCTUnwrap(history.entries.first?.id)
        XCTAssertTrue(history.copy(id: id))
        let export = try XCTUnwrap(pasteboard.string(forType: .fileURL).flatMap(URL.init(string:)))
        XCTAssertEqual(try Data(contentsOf: export), bytes)
        history.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        history.monitor.stop()
    }

    func testDisableDuringRestoreAndQuitDrainsLastSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = ClipHistoryDisk(directory: directory)
        defer { try? disk.delete() }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        var settings = ClipbawdSettings()
        settings.persistent = true
        let history = ClipbawdHistory(pasteboard: pasteboard, directory: directory)
        history.configure(settings)
        settings.persistent = false
        history.configure(settings)
        await history.waitForStorage()
        XCTAssertFalse(history.isLoading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        settings.persistent = true
        history.configure(settings)
        history.record(capture("last-before-quit"))
        await withCheckedContinuation { continuation in
            history.finishStorage { continuation.resume() }
        }
        XCTAssertEqual(try disk.load().entries.map(\.title), ["last-before-quit"])
        XCTAssertFalse(history.monitor.isRunning)
    }

    private func makeVideo(url: URL, duration: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32ARGB, nil, &buffer)
        let pixel = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        memset(CVPixelBufferGetBaseAddress(pixel), 0, CVPixelBufferGetDataSize(pixel))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for second in 0...duration {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertTrue(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(second), timescale: 1)))
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(duration), timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
