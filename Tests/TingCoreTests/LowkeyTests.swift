import Foundation
import Testing
@testable import TingCore

@Suite struct LowkeyTests {
    private func sites(_ json: String) throws -> [LowkeySite] { try LowkeySite.decode(Data(json.utf8)) }

    @Test func publicMetadataAndCommands() throws {
        let site = try #require(sites(#"{"sites":[{"id":"C21D79E1-F87F-424F-97B5-70FBEF757212","alias":"work","title":"Work Chat","startURL":"https://chat.example.com/","extraOrigins":["login.example.com"]}],"appearance":{}}"#).first)
        #expect(site.id == "lowkey:c21d79e1-f87f-424f-97b5-70fbef757212")
        #expect(site.name == "Work Chat")
        #expect(site.url().absoluteString == "lowkey://work/open")
        #expect(site.url(.toggle).absoluteString == "lowkey://work/toggle")
        let results = LaunchaSearch.results(for: "work", in: [site.candidate], history: LaunchHistory(), now: Date())
        #expect(results.map(\.candidate.id) == [site.id])
        for query in ["Work Chat", "work", "chat.example.com"] {
            #expect(LaunchaSearch.results(for: query, in: [site.candidate], history: LaunchHistory(), now: Date()).count == 1)
        }
    }

    @Test func skipsInvalidAliasesURLsAndDuplicates() throws {
        let list = try sites(#"{"sites":[{"alias":"work","startURL":"https://example.com"},{"alias":"WORK","startURL":"https://other.example"},{"alias":"bad/path","startURL":"https://example.com"},{"alias":"рус","startURL":"https://example.com"},{"alias":"bad","startURL":"javascript:alert(1)"},{"alias":"missing"},{"alias":"ok-2_x","title":" ","startURL":"http://localhost:8080"},null]}"#)
        #expect(list.map(\.alias) == ["work", "ok-2_x"])
        #expect(list.last?.name == "ok-2_x")
    }

    @Test func stableIdentitySurvivesAliasAndTitleChanges() throws {
        let old = try sites(#"{"sites":[{"id":"C21D79E1-F87F-424F-97B5-70FBEF757212","alias":"old","startURL":"https://example.com"}]}"#)
        let new = try sites(#"{"sites":[{"id":"C21D79E1-F87F-424F-97B5-70FBEF757212","alias":"new","title":"New title","startURL":"https://example.com"}]}"#)
        #expect(old.first?.id == new.first?.id)
        #expect(new.first?.url().host == "new")
    }

    @Test func acceptsLowkeyBareHostStartURLs() throws {
        let list = try sites(#"{"sites":[{"alias":"web","startURL":"example.com/path"},{"alias":"local","startURL":"localhost:8080"},{"alias":"nas","startURL":"nas.local:5000"},{"alias":"bad","startURL":"not a url"}]}"#)
        #expect(list.map(\.startURL.absoluteString) == ["https://example.com/path", "http://localhost:8080", "https://nas.local:5000"])
    }

    @Test func duplicateProfileIDsAreSkipped() throws {
        let list = try sites(#"{"sites":[{"id":"C21D79E1-F87F-424F-97B5-70FBEF757212","alias":"one","startURL":"https://example.com"},{"id":"C21D79E1-F87F-424F-97B5-70FBEF757212","alias":"two","startURL":"https://example.com"}]}"#)
        #expect(list.count == 1)
    }

    @Test func malformedAndOversizeSettingsFail() throws {
        #expect(throws: (any Error).self) { try sites("[]") }
        #expect(throws: (any Error).self) { try sites(#"{"sites":"wrong"}"#) }
        #expect(throws: (any Error).self) { try sites("not json") }
        #expect(throws: LowkeySite.ReadError.self) {
            try LowkeySite.decode(Data(repeating: 32, count: LowkeySite.maximumConfigSize + 1))
        }
        #expect(try sites("{}").isEmpty)
    }
}
