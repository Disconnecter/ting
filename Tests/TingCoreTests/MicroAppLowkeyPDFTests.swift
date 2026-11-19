import Testing
@testable import TingCore

@Suite struct MicroAppLowkeyPDFTests {
    private func check(_ fields: String) -> Result<MicroApp, MicroAppFailure> {
        MicroAppChecker.check("""
        format: ting.microapp/2
        description: Export a demo page
        input: clipboard
        steps:
          - lowkey: demo
            action: save-pdf
        \(fields)
        output:
          to: [panel]
        """, fileName: "save-page.yaml")
    }

    @Test func acceptsPDFPathTemplate() throws {
        let app = try check("    file: ~/Desktop/${input|trim}.pdf").get()
        guard case .lowkey(let alias, let action, let arguments, let json) = app.steps[0].action else {
            Issue.record("Expected a lowkey step"); return
        }
        #expect(alias.literalText == "demo")
        #expect(action == "save-pdf")
        #expect(arguments.count == 1)
        #expect(arguments[0].render { _ in "report" } == "~/Desktop/report.pdf")
        #expect(!json)
    }

    @Test(arguments: ["", "    file: ''", "    label: Report", "    file: /tmp/report.pdf\n    field: Document", "    file: /tmp/report.pdf\n    as: json"])
    func rejectsMissingOrInapplicableFields(_ fields: String) {
        if case .success = check(fields) { Issue.record("Accepted invalid PDF step: \(fields)") }
    }
}
