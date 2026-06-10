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
}
