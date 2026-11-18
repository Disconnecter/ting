import XCTest
import TingCore
@testable import Ting

final class BindingRecordingTests: XCTestCase {
    func testNewBindingStartsEmptyAndCannotSaveUntilKeysAreTyped() {
        let recording = BindingRecording.new(.url("", "New link", "https://example.com"))
        XCTAssertEqual(recording.initialKeys, [])
        XCTAssertNil(recording.sequence)
        XCTAssertEqual(recording.label, "New link")
        XCTAssertEqual(BindingTree.problem(placing: recording.initialKeys,
                                          moving: recording.sequence, in: []), .empty)
    }

    func testNewBindingDoesNotTreatAnExistingKeyAsItsOwn() {
        let recording = BindingRecording.new(.url("", "New link", "https://example.com"))
        let items: [Item] = [.url("a", "Existing", "https://example.com")]
        XCTAssertEqual(BindingTree.problem(placing: ["a"], moving: recording.sequence, in: items),
                       .taken(label: "Existing"))
        XCTAssertNil(BindingTree.problem(placing: ["b"], moving: recording.sequence, in: items))
    }

    func testEditingKeepsTheCurrentSequenceAndAllowsSavingItUnchanged() {
        let recording = BindingRecording.existing(sequence: ["g", "a"], label: "Existing")
        let items: [Item] = [.group("g", "Group", [.url("a", "Existing", "https://example.com")])]
        XCTAssertEqual(recording.initialKeys, ["g", "a"])
        XCTAssertEqual(recording.label, "Existing")
        XCTAssertNil(BindingTree.problem(placing: recording.initialKeys,
                                        moving: recording.sequence, in: items))
    }
}
