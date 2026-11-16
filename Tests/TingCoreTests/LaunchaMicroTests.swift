import Foundation
import Testing
@testable import TingCore

private func file(id: String? = nil, name: String? = nil, hidden: Bool = false, description: String = "Say hi.") -> String {
    var text = "format: ting.microapp/2\n"
    if let id { text += "id: \(id)\n" }
    if let name { text += "name: \(name)\n" }
    if hidden { text += "hidden: true\n" }
    text += """
    description: \(description)
    input: none
    command: echo hi
    output:
      to: [panel]
    """
    return text
}

@Suite struct LaunchaMicroTests {
    @Test func everyLoadedMicroAppIsACandidateWithOrWithoutABinding() {
        let catalog = MicroAppCatalog.load([
            ("format-json.yaml", file(name: "Format JSON", description: "Pretty-print JSON.")),
            ("count.yaml", file()),
        ])
        let candidates = catalog.launchaCandidates(bindings: [])
        #expect(candidates.map(\.microID) == ["count", "format-json"])
        #expect(candidates.map(\.candidate.id) == ["micro:count", "micro:format-json"])
        #expect(candidates.map(\.candidate.target) == [.micro("count"), .micro("format-json")])
        #expect(candidates.allSatisfy { $0.isWorking })
        #expect(candidates.last?.file == "format-json.yaml")
        #expect(candidates.last?.description == "Pretty-print JSON.")
    }

    @Test func nameIsTheBindingLabelThenNameThenId() {
        let catalog = MicroAppCatalog.load([
            ("labelled.yaml", file(name: "Own Name")),
            ("named.yaml", file(name: "Format JSON")),
            ("plain.yaml", file()),
            ("bound-no-label.yaml", file()),
        ])
        let items = [
            Item(key: "m", label: "", action: .group([
                Item(key: "l", label: "Bound Label", action: .micro("labelled")),
                Item(key: "b", label: "", action: .micro("bound-no-label")),
            ])),
            Item(key: "x", label: "Later Label", action: .micro("labelled")),
        ]
        let names = Dictionary(uniqueKeysWithValues: catalog.launchaCandidates(bindings: items).map { ($0.microID, $0.candidate.name) })
        #expect(names["labelled"] == "Bound Label", "the first labelled binding, depth-first")
        #expect(names["named"] == "Format JSON")
        #expect(names["plain"] == "plain")
        #expect(names["bound-no-label"] == "bound-no-label", "an empty label falls back to the id")
        // Without bindings the `name` key is shown.
        let unbound = catalog.launchaCandidates(bindings: []).first { $0.microID == "labelled" }
        #expect(unbound?.candidate.name == "Own Name")
    }

    @Test func hiddenMicroAppIsLeftOutButStillStartsByItsBinding() {
        let catalog = MicroAppCatalog.load([
            ("secret.yaml", file(hidden: true)),
            ("shown.yaml", file()),
        ])
        let items = [Item(key: "s", label: "Secret", action: .micro("secret"))]
        #expect(catalog.launchaCandidates(bindings: items).map(\.microID) == ["shown"])
        #expect(catalog.resolve("secret").isWorking, "a hidden micro-app still resolves for its binding")
    }

    @Test func brokenFileIsListedAsNotWorking() {
        let catalog = MicroAppCatalog.load([
            ("broken.yaml", "format: ting.microapp/2\ndescription: x\n"),
            ("custom.yaml", "format: ting.microapp/2\nid: format-json\n"),
            ("good.yaml", file()),
        ])
        let candidates = catalog.launchaCandidates(bindings: [Item(key: "b", label: "Broken One", action: .micro("broken"))])
        #expect(candidates.map(\.microID) == ["broken", "format-json", "good"])
        let broken = candidates[0]
        #expect(!broken.isWorking)
        #expect(broken.candidate.name == "Broken One")
        #expect(broken.problem?.hasPrefix("line ") == true)
        #expect(candidates[1].candidate.name == "format-json", "a broken file is found by its kept id")
        #expect(!candidates[1].isWorking)
        // A start of a broken candidate resolves to its file and shows its error.
        guard case .broken(let entry) = catalog.resolve(broken.microID) else { Issue.record("expected broken"); return }
        #expect(entry.file == "broken.yaml")
        #expect(catalog.resolve(broken.microID).problem(id: broken.microID, folder: "~/.config/ting/micro") != nil)
    }

    @Test func duplicateIdFileIsNotListedTwice() {
        let app = MicroApp(id: "same", description: "Say hi.", input: .none, command: "echo hi", output: .init(targets: [.panel]))
        let catalog = MicroAppCatalog.build([("a.yaml", .success(app)), ("b.yaml", .success(app))])
        let candidates = catalog.launchaCandidates(bindings: [])
        // The duplicate is broken and found by its file name, which no working micro-app owns.
        #expect(candidates.map(\.microID) == ["same", "b"])
        #expect(candidates.map(\.isWorking) == [true, false])
        #expect(candidates[1].problem?.contains("duplicate id") == true)
    }

    @Test func microAppsMatchByNameInSearch() {
        let catalog = MicroAppCatalog.load([
            ("format-json.yaml", file(name: "Format JSON")),
            ("count.yaml", file(name: "Count words and characters")),
        ])
        let apps = [LaunchaCandidate.app(bundleID: "com.apple.Safari", name: "Safari")]
        let candidates = catalog.launchaCandidates(bindings: []).map(\.candidate) + apps
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(LaunchaSearch.results(for: "json", in: candidates, history: LaunchHistory(), now: now)
            .map(\.candidate.id) == ["micro:format-json"])
        #expect(LaunchaSearch.results(for: "fj", in: candidates, history: LaunchHistory(), now: now)
            .map(\.candidate.id) == ["micro:format-json"])
        #expect(LaunchaSearch.results(for: "cwac", in: candidates, history: LaunchHistory(), now: now)
            .map(\.candidate.id) == ["micro:count"])
        #expect(LaunchaSearch.results(for: "saf", in: candidates, history: LaunchHistory(), now: now)
            .map(\.candidate.id) == ["app:com.apple.safari"])
        #expect(LaunchaSearch.results(for: "", in: candidates, history: LaunchHistory(), now: now).count == 3)
    }

    @Test func microCandidateIdentity() {
        let candidate = LaunchaCandidate.micro(id: "dns-lookup", name: "DNS lookup")
        #expect(candidate.id == "micro:dns-lookup")
        #expect(candidate.target == .micro("dns-lookup"))
    }
}
