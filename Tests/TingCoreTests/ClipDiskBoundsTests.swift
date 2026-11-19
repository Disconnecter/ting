import Foundation
import Testing
@testable import TingCore

@Suite struct ClipDiskBoundsTests {
    @Test func serializedSizeAlsoFitsLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = ClipHistoryDisk(directory: directory)
        defer { try? disk.delete() }
        var history = ClipHistory()
        history.byteLimit = 1024 * 1024
        for index in 0..<8 {
            let text = String(repeating: Character(String(index)), count: 100_000)
            _ = history.record(.init(types: [ClipboardTypes.plainText], text: text,
                                     representations: [.init(type: ClipboardTypes.plainText, data: Data(text.utf8))]),
                               rules: .init(), at: Date().addingTimeInterval(Double(index)))
        }
        let saved = try disk.save(history)
        #expect(saved.bytes <= history.byteLimit)
        #expect(saved.history.entries.count < history.entries.count)
        #expect(!saved.history.entries.isEmpty)
        #expect(try disk.load().entries == saved.history.entries)
        let bytes = try Data(contentsOf: disk.file).count
        #expect(bytes == saved.bytes)
    }

    @Test func equalCopyDatesEvictOldestInsertion() {
        var history = ClipHistory(maxItems: 2)
        let date = Date()
        for word in ["first", "second", "third"] {
            _ = history.record(.init(types: [ClipboardTypes.plainText], text: word), rules: .init(), at: date)
        }
        #expect(history.entries.map(\.title) == ["third", "second"])
    }
}
