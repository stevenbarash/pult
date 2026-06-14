import Testing
@testable import PultCore

@Test
func mapsCommonAndroidKeyCodes() {
    #expect(RemoteKey.home.androidKeyCode == 3)
    #expect(RemoteKey.back.androidKeyCode == 4)
    #expect(RemoteKey.select.androidKeyCode == 23)
    #expect(RemoteKey.volumeUp.androidKeyCode == 24)
    #expect(RemoteKey.volumeDown.androidKeyCode == 25)
    #expect(RemoteKey.power.androidKeyCode == 26)
    #expect(RemoteKey.playPause.androidKeyCode == 85)
    #expect(RemoteKey.voiceSearch.androidKeyCode == 231)
    #expect(RemoteKey.search.androidKeyCode == 84)
}

@Test
func exposesCommandPresentationMetadata() {
    #expect(RemoteKey.volumeUp.displayTitle == "Volume Up")
    #expect(RemoteKey.volumeUp.systemImage == "speaker.plus")
    #expect(RemoteKey.voiceSearch.displayTitle == "Voice Search")
    #expect(RemoteKey.voiceSearch.systemImage == "mic.fill")
    #expect(RemoteKey.search.displayTitle == "Search")
    #expect(RemoteKey.search.systemImage == "magnifyingglass")
    #expect(RemoteKey.playPause.searchAliases.contains("play pause"))
    #expect(RemoteKey.voiceSearch.searchAliases.contains("google assistant"))
    #expect(RemoteKey.search.searchAliases.contains("text search"))
    #expect(RemoteCommandPlan.catalog.first?.action == .key(.up))
    #expect(RemoteCommandPlan.catalog.contains { $0.action == .openKeyboard })
    #expect(RemoteCommandPlan.catalog.contains { $0.action == .showFavoriteApps })
}

@Test
func plansNaturalLanguageCommandPhrases() {
    #expect(RemoteCommandPlan.plan(for: "play pause")?.remoteKey == .playPause)
    #expect(RemoteCommandPlan.plan(for: "Play/Pause")?.remoteKey == .playPause)
    #expect(RemoteCommandPlan.plan(for: "volume up")?.remoteKey == .volumeUp)
    #expect(RemoteCommandPlan.plan(for: "please turn it down")?.remoteKey == .volumeDown)
    #expect(RemoteCommandPlan.plan(for: "go home")?.remoteKey == .home)
    #expect(RemoteCommandPlan.plan(for: "voice search")?.remoteKey == .voiceSearch)
    #expect(RemoteCommandPlan.plan(for: "google assistant")?.remoteKey == .voiceSearch)
    #expect(RemoteCommandPlan.plan(for: "text search")?.remoteKey == .search)
    #expect(RemoteCommandPlan.plan(for: "open keyboard")?.action == .openKeyboard)
    #expect(RemoteCommandPlan.plan(for: "favorite apps")?.action == .showFavoriteApps)
    #expect(RemoteCommandPlan.plan(for: "summarize this show") == nil)
}

@Test
func suggestsCommandPlansDeterministically() {
    #expect(RemoteCommandPlan.suggestions(matching: "", limit: 2).map(\.action) == [.key(.up), .key(.down)])
    #expect(RemoteCommandPlan.suggestions(matching: "vol", limit: 2).map(\.action) == [.key(.volumeUp), .key(.volumeDown)])
    #expect(RemoteCommandPlan.suggestions(matching: "voice").first?.action == .key(.voiceSearch))
    #expect(RemoteCommandPlan.suggestions(matching: "search").first?.action == .key(.search))
    #expect(RemoteCommandPlan.suggestions(matching: "keyboard").first?.action == .openKeyboard)
    #expect(RemoteCommandPlan.suggestions(matching: "favorite").first?.action == .showFavoriteApps)
}
