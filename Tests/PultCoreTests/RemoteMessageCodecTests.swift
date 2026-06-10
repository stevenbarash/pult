import Foundation
import Testing
@testable import PultCore

private let codec = AndroidTVRemoteMessageCodec()

@Test
func encodesShortKeyInject() throws {
    #expect(try codec.encode(.key(.home, .tap)) == Data([0x52, 0x04, 0x08, 0x03, 0x10, 0x03]))
}

@Test
func encodesAppLinkLaunch() throws {
    let encoded = try codec.encode(.appLink(URL(string: "https://x")!))
    #expect(encoded == Data([0xD2, 0x05, 0x0B, 0x0A, 0x09]) + Data("https://x".utf8))
}

@Test
func encodesControlResponses() {
    #expect(codec.encodePingResponse(5) == Data([0x4A, 0x02, 0x08, 0x05]))
    #expect(codec.encodeSetActiveResponse() == Data([0x12, 0x03, 0x08, 0xEE, 0x04]))
    #expect(
        codec.encodeConfigureResponse() == Data([
            0x0A, 0x25, 0x08, 0xEE, 0x04, 0x12, 0x20,
            0x0A, 0x04, 0x50, 0x75, 0x6C, 0x74,
            0x12, 0x04, 0x50, 0x75, 0x6C, 0x74,
            0x18, 0x01,
            0x22, 0x01, 0x31,
            0x2A, 0x08, 0x61, 0x70, 0x70, 0x2E, 0x70, 0x75, 0x6C, 0x74,
            0x32, 0x03, 0x31, 0x2E, 0x30
        ])
    )
}

@Test
func textIsUnsupportedForNow() {
    #expect(throws: RemoteMessageCodecError.unsupportedCommand) {
        _ = try codec.encode(.text("hi"))
    }
}

@Test
func decodesIncomingMessages() throws {
    #expect(try codec.decode(Data([0x0A, 0x02, 0x08, 0x01])) == .configure)
    #expect(try codec.decode(Data([0x12, 0x00])) == .setActive)
    #expect(try codec.decode(Data([0x42, 0x02, 0x08, 0x2A])) == .pingRequest(42))
    #expect(try codec.decode(Data([0xC2, 0x02, 0x02, 0x08, 0x01])) == .started(true))
    #expect(
        try codec.decode(Data([0x92, 0x03, 0x06, 0x30, 0x64, 0x38, 0x19, 0x40, 0x01]))
            == .volume(level: 25, maximum: 100, muted: true)
    )
}
