import Foundation
import Testing
@testable import TingCore

@Suite struct ClipRetentionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func capture(_ text: String) -> ClipCapture {
        ClipCapture(types: [ClipboardTypes.plainText], text: text,
                    representations: [.init(type: ClipboardTypes.plainText, data: Data(text.utf8))])
    }

    @Test func defaultsAndClamping() throws {
        let defaults = ClipbawdSettings()
        #expect(defaults.maxItems == 100)
        #expect(defaults.maxMegabytes == 50)
        #expect(defaults.maxDays == 30)
        #expect(!defaults.persistent)
        let settings = try ConfigCodec.decode(Data(#"{"clipbawd":{"maxMegabytes":-1,"maxDays":99999,"persistent":true}}"#.utf8)).clipbawd
        #expect(settings.maxMegabytes == 1)
        #expect(settings.maxDays == 3650)
        #expect(settings.persistent)
        #expect(try ConfigCodec.decode(ConfigCodec.encode(Config())).clipbawd == defaults)
    }

    @Test func simultaneousBoundsAndReuseDoesNotExtendAge() {
        var history = ClipHistory(maxItems: 2)
        history.maxDays = 0
        history.byteLimit = 8
        _ = history.record(capture("one"), rules: .init(), at: now)
        _ = history.record(capture("two"), rules: .init(), at: now + 1)
        history.promote(id: 1, at: now + 5)
        _ = history.record(capture("three"), rules: .init(), at: now + 6)
        #expect(history.entries.map(\.title) == ["three", "two"])
        #expect(history.totalBytes == 8)
        history.byteLimit = 2
        history.prune(at: now + 7)
        #expect(history.entries.isEmpty)
        #expect(history.record(capture("big"), rules: .init(), at: now) == .skipped(.tooLarge))

        history.byteLimit = 100
        history.maxDays = 1
        _ = history.record(capture("old"), rules: .init(), at: now)
        history.promote(id: history.entries[0].id, at: now + 80_000)
        history.prune(at: now + 86_401)
        #expect(history.entries.isEmpty)
    }

    @Test func allRepresentationsAndThumbnailCount() {
        let movie = Data([1, 2, 3, 4])
        let video = ClipVideoInfo(duration: 30, thumbnail: Data([5, 6]))
        var history = ClipHistory()
        let capture = ClipCapture(types: [ClipboardTypes.mpeg4],
                                  representations: [.init(type: ClipboardTypes.mpeg4, data: movie)], video: video)
        #expect(history.record(capture, rules: .init(), at: now) == .added(1))
        #expect(history.entries[0].byteCount == 6)
        #expect(history.entries[0].content == .video(video))
        var long = capture
        long.video?.duration = 30.01
        #expect(history.record(long, rules: .init(), at: now) == .skipped(.empty))
        long.video?.duration = .nan
        #expect(history.record(long, rules: .init(), at: now) == .skipped(.empty))
    }

    @Test func diskRoundTripAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = ClipHistoryDisk(directory: directory)
        defer { try? disk.delete() }
        var history = ClipHistory()
        var rich = capture("# Hello **world**")
        rich.representations.append(.init(type: ClipboardTypes.markdown, data: Data("# Hello **world**".utf8)))
        _ = history.record(rich, rules: .init(), at: now)
        _ = history.record(rich, rules: .init(), at: now + 1)
        #expect(try disk.save(history).bytes > 0)
        var restored = try disk.load()
        #expect(restored.entries == history.entries)
        #expect(restored.entries[0].copyCount == 2)
        _ = restored.record(capture("next"), rules: .init(), at: now + 2)
        #expect(restored.entries[0].id == 2)
        let mode = try FileManager.default.attributesOfItem(atPath: disk.file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        try Data("corrupt".utf8).write(to: disk.file)
        #expect(throws: (any Error).self) { try disk.load() }
        try disk.delete()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(try disk.load().entries.isEmpty)
    }

    @Test func currentExclusionsApplyToRestoredHistory() {
        var history = ClipHistory()
        _ = history.record(capture("secret-text"), rules: .init(), at: now)
        var settings = ClipbawdSettings()
        settings.ignoredPrefixes = ["secret-"]
        history.apply(settings, at: now)
        #expect(history.entries.isEmpty)
    }

    @Test func overridesAreIsolated() {
        let first = ClipHistoryDisk.defaultDirectory(environment: ["TING_CONFIG": "/tmp/a.json"])
        let second = ClipHistoryDisk.defaultDirectory(environment: ["TING_CONFIG": "/tmp/b.json"])
        #expect(first.path == "/tmp/a.json.clipbawd")
        #expect(first != second)
    }
}
