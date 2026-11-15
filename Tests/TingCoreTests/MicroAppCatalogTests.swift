import Foundation
import Testing
@testable import TingCore

private func good(_ description: String = "Say hi.", id: String? = nil) -> String {
    (id.map { "id: \($0)\n" } ?? "") + """
    format: ting.microapp/2
    description: \(description)
    input: none
    command: echo hi
    output:
      to: [panel]
    """
}

private func app(_ id: String) -> MicroApp {
    MicroApp(id: id, description: "Say hi.", input: .none, command: "echo hi", output: .init(targets: [.panel]))
}

@Suite struct MicroAppCatalogTests {
    @Test func loadsGoodAndBrokenFilesInNameOrder() {
        let catalog = MicroAppCatalog.load([
            ("zeta.yaml", good()),
            ("alpha.yaml", good()),
            ("broken.yaml", "format: ting.microapp/2\n"),
        ])
        #expect(catalog.entries.map(\.file) == ["alpha.yaml", "broken.yaml", "zeta.yaml"])
        #expect(catalog.apps.map(\.id) == ["alpha", "zeta"])
        #expect(catalog.brokenFiles == ["broken.yaml"])
        #expect(!catalog.issues.isEmpty)
        #expect(catalog.issues.allSatisfy { $0.file == "broken.yaml" })
    }

    @Test func duplicateIdKeepsTheFirstFileByName() {
        // The checker ties the id to the file name, so the folder store cannot produce this; the
        // rule still holds for any two files that end up with the same id.
        let catalog = MicroAppCatalog.build([
            ("b-copy.yaml", .success(app("same"))),
            ("a-first.yaml", .success(app("same"))),
            ("c-other.yaml", .success(app("other"))),
        ])
        #expect(catalog.apps.map(\.id) == ["same", "other"])
        let duplicate = catalog.entries.first { $0.file == "b-copy.yaml" }
        #expect(duplicate?.isBroken == true)
        #expect(duplicate?.issues.count == 1)
        #expect(duplicate?.issues.first?.line == 1)
        #expect(duplicate?.issues.first?.message.contains("duplicate id `same`") == true)
        #expect(duplicate?.issues.first?.message.contains("a-first.yaml") == true)
    }

    @Test func brokenFileDoesNotClaimAnId() {
        let catalog = MicroAppCatalog.build([
            ("a.yaml", .failure(MicroAppFailure(issues: [MicroAppIssue(file: "a.yaml", line: 2, message: "bad")]))),
            ("b.yaml", .success(app("a"))),
        ])
        #expect(catalog.apps.map(\.id) == ["a"])
    }

    @Test func logHasOneLinePerProblemAndIsEmptyWhenGood() {
        let broken = MicroAppCatalog.build([
            ("a.yaml", .failure(MicroAppFailure(issues: [
                MicroAppIssue(file: "a.yaml", line: 2, message: "first"),
                MicroAppIssue(file: "a.yaml", line: 5, message: "two\nlines"),
            ]))),
            ("b.yaml", .success(app("b"))),
        ])
        #expect(broken.logText == "a.yaml:2: first\na.yaml:5: two lines\n")
        #expect(MicroAppCatalog.load([("a.yaml", good())]).logText == "")
        #expect(MicroAppCatalog().logText == "")
    }

    @Test func toastOnlyForNewOrChangedBrokenFiles() {
        let fine = MicroAppCatalog.load([("a.yaml", good()), ("b.yaml", good())])
        let oneBroken = MicroAppCatalog.load([("a.yaml", good()), ("b.yaml", "format: ting.microapp/2\n")])
        #expect(oneBroken.toastMessage(since: fine)?.hasPrefix("Micro-app b.yaml, line 1: ") == true)
        // The same problems again: no toast.
        #expect(oneBroken.toastMessage(since: oneBroken) == nil)
        // Fixed: no toast.
        #expect(fine.toastMessage(since: oneBroken) == nil)
        // A different problem in the same file: toast.
        let changed = MicroAppCatalog.load([("a.yaml", good()), ("b.yaml", good(id: "Bad"))])
        #expect(changed.toastMessage(since: oneBroken) != nil)
        // Two new broken files.
        let two = MicroAppCatalog.load([("a.yaml", "x: 1\n"), ("b.yaml", "format: ting.microapp/2\n")])
        #expect(two.toastMessage(since: fine)?.hasPrefix("2 micro-app files have errors") == true)
    }

    @Test func emptyCatalog() {
        let catalog = MicroAppCatalog.load([])
        #expect(catalog.entries.isEmpty && catalog.issues.isEmpty && catalog.apps.isEmpty)
    }
}
