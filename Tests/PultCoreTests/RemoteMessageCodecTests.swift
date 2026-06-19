import Foundation
import Testing
@testable import PultCore

private let codec = AndroidTVRemoteMessageCodec()

@Test
func encodesShortKeyInject() throws {
    #expect(try codec.encode(.key(.home, .tap)) == Data([0x52, 0x04, 0x08, 0x03, 0x10, 0x03]))
    #expect(try codec.encode(.key(.voiceSearch, .tap)) == Data([0x52, 0x05, 0x08, 0xE7, 0x01, 0x10, 0x03]))
    #expect(try codec.encode(.key(.search, .tap)) == Data([0x52, 0x04, 0x08, 0x54, 0x10, 0x03]))
}

@Test
func encodesLongKeyInjectActions() throws {
    #expect(try codec.encode(.key(.select, .press)) == Data([0x52, 0x04, 0x08, 0x17, 0x10, 0x01]))
    #expect(try codec.encode(.key(.select, .release)) == Data([0x52, 0x04, 0x08, 0x17, 0x10, 0x02]))
}

@Test
func encodesAppLinkLaunch() throws {
    let encoded = try codec.encode(.appLink(URL(string: "https://x")!))
    #expect(encoded == Data([0xD2, 0x05, 0x0B, 0x0A, 0x09]) + Data("https://x".utf8))
}

@Test
func encodesTextBatchEdit() throws {
    let encoded = try codec.encode(.text(RemoteTextEdit(imeCounter: 1, fieldCounter: 7, text: "A")))
    #expect(
        encoded == Data([
            0xAA, 0x01, 0x11,
            0x08, 0x01,
            0x10, 0x07,
            0x1A, 0x0B,
            0x08, 0x01,
            0x12, 0x07,
            0x08, 0x00,
            0x10, 0x00,
            0x1A, 0x01, 0x41
        ])
    )
}

@Test
func encodesVoiceMessages() throws {
    #expect(try codec.encode(.voiceBegin(sessionID: 42)) == Data([0xF2, 0x01, 0x02, 0x08, 0x2A]))
    #expect(
        try codec.encode(.voicePayload(sessionID: 42, samples: Data([0x01, 0x02])))
            == Data([0xFA, 0x01, 0x06, 0x08, 0x2A, 0x12, 0x02, 0x01, 0x02])
    )
    #expect(try codec.encode(.voiceEnd(sessionID: 42)) == Data([0x82, 0x02, 0x02, 0x08, 0x2A]))
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
func decodesIncomingMessages() throws {
    #expect(try codec.decode(Data([0x0A, 0x02, 0x08, 0x01])) == .configure)
    #expect(try codec.decode(Data([0x12, 0x00])) == .setActive)
    #expect(try codec.decode(Data([0x42, 0x02, 0x08, 0x2A])) == .pingRequest(42))
    #expect(try codec.decode(Data([0xC2, 0x02, 0x02, 0x08, 0x01])) == .started(true))
    #expect(
        try codec.decode(Data([0x92, 0x03, 0x06, 0x30, 0x64, 0x38, 0x19, 0x40, 0x01]))
            == .volume(level: 25, maximum: 100, muted: true)
    )
    #expect(
        try codec.decode(remoteImeShowRequestFrame())
            == .textFieldStatus(
                RemoteTextFieldStatus(
                    imeCounter: 1,
                    counter: 7,
                    value: "ab",
                    selectionStart: 1,
                    selectionEnd: 2,
                    label: "Search"
                )
            )
    )
    #expect(
        try codec.decode(remoteImeBatchEditFrame())
            == .textFieldStatus(
                RemoteTextFieldStatus(
                    imeCounter: 3,
                    counter: 9,
                    value: "hey",
                    selectionStart: 2,
                    selectionEnd: 2
                )
            )
    )
    #expect(try codec.decode(remoteVoiceBeginFrame(sessionID: 42)) == .voiceBegin(sessionID: 42))
}

private func remoteImeShowRequestFrame() -> Data {
    var status = ProtobufEncoder()
    status.appendVarint(field: 1, 7)
    status.appendString(field: 2, "ab")
    status.appendVarint(field: 3, 1)
    status.appendVarint(field: 4, 2)
    status.appendVarint(field: 5, 0)
    status.appendString(field: 6, "Search")

    var showRequest = ProtobufEncoder()
    showRequest.appendMessage(field: 2, status.data)

    var message = ProtobufEncoder()
    message.appendMessage(field: 22, showRequest.data)
    return message.data
}

private func remoteImeBatchEditFrame() -> Data {
    var object = ProtobufEncoder()
    object.appendVarint(field: 1, 2)
    object.appendVarint(field: 2, 2)
    object.appendString(field: 3, "hey")

    var editInfo = ProtobufEncoder()
    editInfo.appendVarint(field: 1, 1)
    editInfo.appendMessage(field: 2, object.data)

    var batchEdit = ProtobufEncoder()
    batchEdit.appendVarint(field: 1, 3)
    batchEdit.appendVarint(field: 2, 9)
    batchEdit.appendMessage(field: 3, editInfo.data)

    var message = ProtobufEncoder()
    message.appendMessage(field: 21, batchEdit.data)
    return message.data
}

private func remoteVoiceBeginFrame(sessionID: Int) -> Data {
    var voiceBegin = ProtobufEncoder()
    voiceBegin.appendVarint(field: 1, UInt64(sessionID))

    var message = ProtobufEncoder()
    message.appendMessage(field: 30, voiceBegin.data)
    return message.data
}
