import XCTest
import TingCore

final class MicroAppInteractionTests: XCTestCase {
    func testLinesPreserveValuesAndDuplicateIdentity() throws {
        let choices = try MicroAppInteraction.choices(from: " /tmp/a b \r\n\nYes\nYes\n")
        XCTAssertEqual(choices.map(\.value), [" /tmp/a b ", "Yes", "Yes"])
        XCTAssertEqual(choices.map(\.id), [0, 1, 2])
    }

    func testJSONAndInvalidLists() throws {
        let choices = try MicroAppInteraction.choices(from: #"[{"title":"Report","subtitle":"PDF","value":"/tmp/report.pdf"},"Other"]"#)
        XCTAssertEqual(choices.first?.subtitle, "PDF")
        XCTAssertEqual(choices.first?.value, "/tmp/report.pdf")
        for input in ["", " \n", "[]", "[broken", "{}", "[4]", #"[{"title":"x"}]"#, #"[{"title":"x","value":3}]"#] {
            XCTAssertThrowsError(try MicroAppInteraction.choices(from: input), input)
        }
        let request = MicroAppInteraction.choose(prompt: "Pick", choices: choices)
        XCTAssertEqual(try request.validate("/tmp/report.pdf"), "/tmp/report.pdf")
        XCTAssertThrowsError(try request.validate("Report"))
    }

    func testRequiredAndOptionalText() throws {
        let required = MicroAppInteraction.ask(prompt: "Text", defaultValue: "", placeholder: "", multiline: true, required: true)
        XCTAssertThrowsError(try required.validate(" \n"))
        XCTAssertEqual(try required.validate(" a\nb "), " a\nb ")
        let optional = MicroAppInteraction.ask(prompt: "Text", defaultValue: "", placeholder: "", multiline: false, required: false)
        XCTAssertEqual(try optional.validate(""), "")
    }

    func testCheckerValidatesNewStepsAndTemplates() throws {
        let source = """
        format: ting.microapp/2
        description: Interactive example.
        input: none
        steps:
          - ask: Topic
            id: topic
            placeholder: A topic
            multiline: true
            required: false
          - ask: More about ${steps.topic}
            default: ${input}
          - choose: Pick one
        """
        let app = try MicroAppChecker.check(source, fileName: "test.yaml").get()
        XCTAssertEqual(app.steps.map(\.kind), [.ask, .ask, .choose])
        guard case .ask(let ask) = app.steps[0].action else { return XCTFail("not ask") }
        XCTAssertTrue(ask.multiline)
        XCTAssertFalse(ask.required)
        for invalid in [source.replacingOccurrences(of: "multiline: true", with: "multiline: yes"),
                        source.replacingOccurrences(of: "choose: Pick one", with: "choose: Pick one\n    default: x"),
                        source.replacingOccurrences(of: "required: false", with: "required: false\n    stream: true")] {
            guard case .failure = MicroAppChecker.check(invalid, fileName: "test.yaml") else {
                return XCTFail("accepted invalid step")
            }
        }
    }
}
