import Testing
@testable import TingCore

@Suite struct SettingsCatalogTests {
    @Test func searchesParametersNotJustPageNames() {
        #expect(SettingsCatalog.search("days").map(\.id) == ["storage"])
        #expect(SettingsCatalog.search("volume").map(\.id) == ["sound"])
        #expect(SettingsCatalog.search("agent prompt").map(\.page) == [.microApps])
        #expect(SettingsCatalog.search("clipboard limit").map(\.id) == ["storage"])
        #expect(SettingsCatalog.search("UNKNOWN_SETTING").isEmpty)
        #expect(SettingsCatalog.search("LAUNCHA").first?.page == .activation)
        #expect(Set(SettingsCatalog.items.map(\.id)).count == SettingsCatalog.items.count)
        #expect(Set(SettingsCatalog.items.map(\.page)) == Set(SettingsPage.allCases))
    }
}
