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
    switch try codec.decode(remoteConfigureFrame()) {
    case let .configure(request):
        #expect(request.code?.rawValue == 64)
        #expect(request.code?.features == [.volume])
        #expect(request.deviceInfo?.vendor == "Google")
        #expect(request.deviceInfo?.model == "TV")
        #expect(request.deviceInfo?.packageName == "com.google.android.tv.remote.service")
        #expect(request.deviceInfo?.appVersion == "5.2.473254133")
    default:
        Issue.record("expected configure request")
    }
    switch try codec.decode(remoteSetActiveFrame(active: 622)) {
    case let .setActive(request):
        #expect(request.active?.rawValue == 622)
        #expect(request.active?.features.contains(.volume) == true)
        #expect(request.active?.features.contains(.appLink) == true)
    default:
        Issue.record("expected set-active request")
    }
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
    #expect(try codec.decode(remoteVoiceBeginFrame(sessionID: 42)) == .voiceBegin(sessionID: 42))
}

@Test
func protocolFeatureCodeDecoding() {
    let observed = RemoteProtocolCode(rawValue: 622)
    #expect(observed.features.contains(.key))
    #expect(observed.features.contains(.ime))
    #expect(observed.features.contains(.voice))
    #expect(!observed.features.contains(.unknown1))
    #expect(observed.features.contains(.powerCommandCapability))
    #expect(observed.features.contains(.volume))
    #expect(observed.features.contains(.appLink))
    #expect(!observed.features.contains(.ping))
    #expect(observed.unknownBits == 0)
    #expect(observed.labels == ["key", "ime", "voice", "powerCommandCapability", "volume", "appLink"])

    let unknown = RemoteProtocolCode(rawValue: 1024 + 64)
    #expect(unknown.features == [.volume])
    #expect(unknown.unknownBits == 1024)
    #expect(unknown.labels == ["volume", "unknown(1024)"])
}

@Test
func remoteStartRequiresStartedField() throws {
    #expect(try codec.decode(remoteStartFrame(started: true)) == .started(true))
    #expect(try codec.decode(remoteStartFrame(started: false)) == .started(false))
    #expect(try codec.decode(remoteStartWithoutStartedFieldFrame()) == .other)
}

@Test
func imeObservationsPreserveAppAndEdits() throws {
    let keyInject = try codec.decode(remoteImeKeyInjectFrame(
        packageName: "com.netflix.ninja",
        appLabel: "Netflix",
        counter: 42,
        value: "search",
        selectionStart: 6,
        selectionEnd: 6
    ))
    guard case let .imeKeyInject(keyObservation) = keyInject else {
        Issue.record("expected ime key inject observation")
        return
    }
    #expect(keyObservation.appInfo?.appPackage == "com.netflix.ninja")
    #expect(keyObservation.appInfo?.label == "Netflix")
    #expect(keyObservation.textFieldStatus?.counter == 42)
    #expect(keyObservation.textFieldStatus?.value == "search")
    #expect(keyObservation.textFieldStatus?.selectionStart == 6)
    #expect(keyObservation.textFieldStatus?.selectionEnd == 6)

    let batchEdit = try codec.decode(remoteImeBatchEditFrame(
        imeCounter: 3,
        fieldCounter: 43,
        edits: [
            RemoteEditFixture(insert: 1, selectionStart: 3, selectionEnd: 3, value: "sea"),
            RemoteEditFixture(insert: 1, selectionStart: 6, selectionEnd: 6, value: "search")
        ]
    ))
    guard case let .imeBatchEdit(batchObservation) = batchEdit else {
        Issue.record("expected ime batch edit observation")
        return
    }
    #expect(batchObservation.imeCounter == 3)
    #expect(batchObservation.fieldCounter == 43)
    #expect(batchObservation.edits.count == 2)
    #expect(batchObservation.edits[0].editType == 1)
    #expect(batchObservation.edits[1].editType == 1)
    #expect(batchObservation.edits[0].object?.value == "sea")
    #expect(batchObservation.edits[1].object?.value == "search")
    #expect(batchObservation.edits[1].object?.selectionStart == 6)
    #expect(batchObservation.edits[1].object?.selectionEnd == 6)
    let status = try #require(batchObservation.derivedTextFieldStatus)
    #expect(
        status == RemoteTextFieldStatus(
            imeCounter: 3,
            counter: 43,
            value: "search",
            selectionStart: 6,
            selectionEnd: 6
        )
    )
}

@Test
func missingObservationScalarsRemainAbsent() throws {
    switch try codec.decode(remoteConfigureFrame(
        code: nil,
        vendor: nil,
        model: nil,
        packageName: nil,
        appVersion: nil,
        includeDeviceInfo: true
    )) {
    case let .configure(request):
        #expect(request.code == nil)
        let deviceInfo = try #require(request.deviceInfo)
        #expect(deviceInfo.model == nil)
        #expect(deviceInfo.vendor == nil)
        #expect(deviceInfo.unknown1 == nil)
        #expect(deviceInfo.unknown2 == nil)
        #expect(deviceInfo.packageName == nil)
        #expect(deviceInfo.appVersion == nil)
    default:
        Issue.record("expected configure request")
    }

    switch try codec.decode(remoteImeKeyInjectFrame(
        packageName: nil,
        appLabel: nil,
        counter: nil,
        value: nil,
        selectionStart: nil,
        selectionEnd: nil
    )) {
    case let .imeKeyInject(observation):
        let appInfo = try #require(observation.appInfo)
        #expect(appInfo.counter == nil)
        #expect(appInfo.unknownInt2 == nil)
        #expect(appInfo.unknownInt3 == nil)
        #expect(appInfo.unknownString4 == nil)
        #expect(appInfo.unknownInt7 == nil)
        #expect(appInfo.unknownInt8 == nil)
        #expect(appInfo.label == nil)
        #expect(appInfo.appPackage == nil)
        #expect(appInfo.unknownInt13 == nil)
    default:
        Issue.record("expected IME key-inject observation")
    }

    switch try codec.decode(remoteImeBatchEditFrame(
        imeCounter: nil,
        fieldCounter: nil,
        edits: [
            RemoteEditFixture(insert: nil, selectionStart: nil, selectionEnd: nil, value: nil)
        ]
    )) {
    case let .imeBatchEdit(observation):
        #expect(observation.imeCounter == nil)
        #expect(observation.fieldCounter == nil)
        #expect(observation.edits.count == 1)
        #expect(observation.edits[0].editType == nil)
        let object = try #require(observation.edits[0].object)
        #expect(object.value == nil)
        #expect(object.selectionStart == nil)
        #expect(object.selectionEnd == nil)
        #expect(observation.derivedTextFieldStatus == nil)
    default:
        Issue.record("expected IME batch edit observation")
    }
}

@Test
func malformedOptionalNestedObservationsPreserveSiblingFields() throws {
    switch try codec.decode(remoteConfigureFrame(code: 64, deviceInfoPayload: malformedStringFieldPayload())) {
    case let .configure(request):
        #expect(request.code?.rawValue == 64)
        #expect(request.deviceInfo == nil)
    default:
        Issue.record("expected configure request")
    }

    switch try codec.decode(remoteImeKeyInjectFrame(
        appInfoPayload: malformedStringFieldPayload(),
        textFieldStatusPayload: remoteTextFieldStatusPayload(counter: 42, value: "search", selectionStart: 6, selectionEnd: 6)
    )) {
    case let .imeKeyInject(observation):
        #expect(observation.appInfo == nil)
        #expect(observation.textFieldStatus?.counter == 42)
        #expect(observation.textFieldStatus?.value == "search")
        #expect(observation.textFieldStatus?.selectionStart == 6)
        #expect(observation.textFieldStatus?.selectionEnd == 6)
    default:
        Issue.record("expected IME key-inject observation")
    }

    switch try codec.decode(remoteImeKeyInjectFrame(
        appInfoPayload: remoteAppInfoPayload(packageName: "com.netflix.ninja", appLabel: "Netflix", counter: 42),
        textFieldStatusPayload: malformedStringFieldPayload()
    )) {
    case let .imeKeyInject(observation):
        #expect(observation.appInfo?.appPackage == "com.netflix.ninja")
        #expect(observation.appInfo?.label == "Netflix")
        #expect(observation.appInfo?.counter == 42)
        #expect(observation.textFieldStatus == nil)
    default:
        Issue.record("expected IME key-inject observation")
    }
}

private struct RemoteEditFixture {
    var insert: Int?
    var selectionStart: Int?
    var selectionEnd: Int?
    var value: String?
}

private func remoteConfigureFrame(
    code: UInt64? = 64,
    vendor: String? = "Google",
    model: String? = "TV",
    packageName: String? = "com.google.android.tv.remote.service",
    appVersion: String? = "5.2.473254133",
    includeDeviceInfo: Bool = true,
    deviceInfoPayload explicitDeviceInfoPayload: Data? = nil
) -> Data {
    var configure = ProtobufEncoder()
    if let code {
        configure.appendVarint(field: 1, code)
    }
    if let explicitDeviceInfoPayload {
        configure.appendBytes(field: 2, explicitDeviceInfoPayload)
    } else if includeDeviceInfo {
        configure.appendMessage(
            field: 2,
            remoteDeviceInfoPayload(vendor: vendor, model: model, packageName: packageName, appVersion: appVersion)
        )
    }

    var message = ProtobufEncoder()
    message.appendMessage(field: 1, configure.data)
    return message.data
}

private func remoteSetActiveFrame(active: UInt64?) -> Data {
    var setActive = ProtobufEncoder()
    if let active {
        setActive.appendVarint(field: 1, active)
    }

    var message = ProtobufEncoder()
    message.appendMessage(field: 2, setActive.data)
    return message.data
}

private func remoteStartFrame(started: Bool) -> Data {
    var start = ProtobufEncoder()
    start.appendVarint(field: 1, started ? 1 : 0)

    var message = ProtobufEncoder()
    message.appendMessage(field: 40, start.data)
    return message.data
}

private func remoteStartWithoutStartedFieldFrame() -> Data {
    var start = ProtobufEncoder()
    start.appendVarint(field: 2, 1)

    var message = ProtobufEncoder()
    message.appendMessage(field: 40, start.data)
    return message.data
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

private func remoteImeKeyInjectFrame(
    packageName: String?,
    appLabel: String?,
    counter: Int?,
    value: String?,
    selectionStart: Int?,
    selectionEnd: Int?
) -> Data {
    remoteImeKeyInjectFrame(
        appInfoPayload: remoteAppInfoPayload(packageName: packageName, appLabel: appLabel, counter: counter),
        textFieldStatusPayload: remoteTextFieldStatusPayload(
            counter: counter,
            value: value,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd
        )
    )
}

private func remoteImeKeyInjectFrame(appInfoPayload: Data?, textFieldStatusPayload: Data?) -> Data {
    var keyInject = ProtobufEncoder()
    if let appInfoPayload {
        keyInject.appendBytes(field: 1, appInfoPayload)
    }
    if let textFieldStatusPayload {
        keyInject.appendBytes(field: 2, textFieldStatusPayload)
    }

    var message = ProtobufEncoder()
    message.appendMessage(field: 20, keyInject.data)
    return message.data
}

private func remoteImeBatchEditFrame(
    imeCounter: Int? = 3,
    fieldCounter: Int? = 9,
    edits: [RemoteEditFixture] = [
        RemoteEditFixture(insert: 1, selectionStart: 2, selectionEnd: 2, value: "hey")
    ]
) -> Data {
    var batchEdit = ProtobufEncoder()
    if let imeCounter {
        batchEdit.appendVarint(field: 1, UInt64(imeCounter))
    }
    if let fieldCounter {
        batchEdit.appendVarint(field: 2, UInt64(fieldCounter))
    }

    for edit in edits {
        var object = ProtobufEncoder()
        if let selectionStart = edit.selectionStart {
            object.appendVarint(field: 1, UInt64(selectionStart))
        }
        if let selectionEnd = edit.selectionEnd {
            object.appendVarint(field: 2, UInt64(selectionEnd))
        }
        if let value = edit.value {
            object.appendString(field: 3, value)
        }

        var editInfo = ProtobufEncoder()
        if let insert = edit.insert {
            editInfo.appendVarint(field: 1, UInt64(insert))
        }
        editInfo.appendMessage(field: 2, object.data)
        batchEdit.appendMessage(field: 3, editInfo.data)
    }

    var message = ProtobufEncoder()
    message.appendMessage(field: 21, batchEdit.data)
    return message.data
}

private func remoteDeviceInfoPayload(
    vendor: String?,
    model: String?,
    packageName: String?,
    appVersion: String?
) -> Data {
    var deviceInfo = ProtobufEncoder()
    if let model {
        deviceInfo.appendString(field: 1, model)
    }
    if let vendor {
        deviceInfo.appendString(field: 2, vendor)
    }
    if model != nil || vendor != nil || packageName != nil || appVersion != nil {
        deviceInfo.appendVarint(field: 3, 1)
        deviceInfo.appendString(field: 4, "1")
    }
    if let packageName {
        deviceInfo.appendString(field: 5, packageName)
    }
    if let appVersion {
        deviceInfo.appendString(field: 6, appVersion)
    }
    return deviceInfo.data
}

private func remoteAppInfoPayload(packageName: String?, appLabel: String?, counter: Int?) -> Data {
    var appInfo = ProtobufEncoder()
    if let counter {
        appInfo.appendVarint(field: 1, UInt64(counter))
    }
    if let appLabel {
        appInfo.appendString(field: 10, appLabel)
    }
    if let packageName {
        appInfo.appendString(field: 12, packageName)
    }
    return appInfo.data
}

private func remoteTextFieldStatusPayload(
    counter: Int?,
    value: String?,
    selectionStart: Int?,
    selectionEnd: Int?
) -> Data {
    var status = ProtobufEncoder()
    if let counter {
        status.appendVarint(field: 1, UInt64(counter))
    }
    if let value {
        status.appendString(field: 2, value)
    }
    if let selectionStart {
        status.appendVarint(field: 3, UInt64(selectionStart))
    }
    if let selectionEnd {
        status.appendVarint(field: 4, UInt64(selectionEnd))
    }
    return status.data
}

private func malformedStringFieldPayload() -> Data {
    Data([0x0A, 0x05, 0x54])
}

private func remoteVoiceBeginFrame(sessionID: Int) -> Data {
    var voiceBegin = ProtobufEncoder()
    voiceBegin.appendVarint(field: 1, UInt64(sessionID))

    var message = ProtobufEncoder()
    message.appendMessage(field: 30, voiceBegin.data)
    return message.data
}
