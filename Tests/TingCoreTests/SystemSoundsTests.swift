import Foundation
import Testing
@testable import TingCore

@Suite struct SystemSoundsTests {
    @Test func listsSoundFilesSortedWithoutExtension() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ting-sounds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for file in ["Tink.aiff", "Glass.aiff", "Pop.AIFF", "Blow.caf", "notes.txt", "README", ".Hidden.aiff"] {
            try Data().write(to: folder.appendingPathComponent(file))
        }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Sub"), withIntermediateDirectories: false)
        #expect(SystemSounds.names(in: folder) == ["Blow", "Glass", "Pop", "Tink"])
    }

    @Test func missingFolderGivesEmptyList() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("ting-no-such-\(UUID().uuidString)")
        #expect(SystemSounds.names(in: missing).isEmpty)
    }

    @Test func defaults() {
        #expect(SystemSounds.defaultFolder.path == "/System/Library/Sounds")
        #expect(SystemSounds.defaultName == "Tink")
    }
}
