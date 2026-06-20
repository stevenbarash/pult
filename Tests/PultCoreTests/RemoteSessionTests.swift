import Foundation
import Testing
@testable import PultCore

private let framer = VarintFramer()
private let codec = AndroidTVRemoteMessageCodec()
private let tvConfigureFrame = Data([0x0A, 0x02, 0x08, 0x01])

@MainActor
@Test
func connectAnswersConfigureAndBecomesConnected() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))

    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))

    let endpoint = await transport.endpoint
    #expect(endpoint?.host == "192.168.1.10")
    #expect(endpoint?.port == 6466)
    #expect(session.connectionState == .connected)
    let sent = await transport.waitForSent(count: 1)
    #expect(sent.first == framer.frame(codec.encodeConfigureResponse()))
}

@MainActor
@Test
func sessionAnswersSetActiveAndPing() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))

    await transport.enqueueIncoming(framer.frame(Data([0x12, 0x00])))
    var sent = await transport.waitForSent(count: 2)
    #expect(sent.count >= 2 && sent[1] == framer.frame(codec.encodeSetActiveResponse()))

    await transport.enqueueIncoming(framer.frame(Data([0x42, 0x02, 0x08, 0x2A])))
    sent = await transport.waitForSent(count: 3)
    #expect(sent.count >= 3 && sent[2] == framer.frame(codec.encodePingResponse(42)))
    #expect(session.lastReceivedAt != nil)
    #expect(session.lastSentAt != nil)
}

@MainActor
@Test
func sessionStoresProtocolConfigureSetActiveAndStartObservations() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    let device = DeviceRecord(name: "TV", host: "192.168.1.10")
    await transport.enqueueIncoming(framer.frame(remoteConfigureFrame(code: 64)))

    await session.connect(to: device)

    let sent = await transport.waitForSent(count: 1)
    #expect(sent.first == framer.frame(codec.encodeConfigureResponse()))
    #expect(session.protocolState.negotiation.inboundConfigureCode?.value.rawValue == 64)
    #expect(session.protocolState.negotiation.inboundConfigureCode?.source == "remote_configure.code1")
    #expect(session.protocolState.negotiation.inboundConfigureCode?.deviceID == device.id)
    #expect(session.protocolState.negotiation.outboundConfigureCode?.value.rawValue == 622)
    #expect(session.protocolState.negotiation.outboundConfigureCode?.source == "client.remote_configure.code1")
    #expect(session.protocolState.deviceInfo?.value.vendor == "Google")
    #expect(session.protocolState.deviceInfo?.value.model == "TV")
    #expect(session.protocolState.deviceInfo?.source == "remote_configure.device_info")

    await transport.enqueueIncoming(framer.frame(remoteSetActiveFrame(active: 622)))
    await transport.enqueueIncoming(framer.frame(remoteStartFrame(started: true)))
    _ = await transport.waitForSent(count: 2)
    for _ in 0..<2000 where session.protocolState.remoteStart == nil {
        try? await Task.sleep(for: .milliseconds(1))
    }

    #expect(session.protocolState.negotiation.inboundSetActiveCode?.value.rawValue == 622)
    #expect(session.protocolState.negotiation.inboundSetActiveCode?.source == "remote_set_active.active")
    #expect(session.protocolState.negotiation.outboundSetActiveCode?.value.rawValue == 622)
    #expect(session.protocolState.negotiation.outboundSetActiveCode?.source == "client.remote_set_active.active")
    #expect(session.protocolState.remoteStart?.value == true)
    #expect(session.protocolState.remoteStart?.source == "remote_start.started")
}

@MainActor
@Test
func volumeStatusTracksLatestTvUpdate() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
    _ = await transport.waitForSent(count: 1)

    await transport.enqueueIncoming(framer.frame(Data([0x92, 0x03, 0x06, 0x30, 0x64, 0x38, 0x19, 0x40, 0x01])))
    var attempts = 0
    while session.volumeStatus == nil, attempts < 2000 {
        attempts += 1
        try? await Task.sleep(for: .milliseconds(1))
    }

    #expect(session.volumeStatus == RemoteVolumeStatus(level: 25, maximum: 100, muted: true))
    #expect(session.volumeStatus?.normalizedLevel == 0.25)
}

@MainActor
@Test
func pressSendsSingleShortKeyInject() async throws {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
    _ = await transport.waitForSent(count: 1)

    await session.press(.home)

    let sent = await transport.waitForSent(count: 2)
    #expect(sent.count >= 2)
    #expect(sent[1] == framer.frame(try codec.encode(.key(.home, .tap))))
}

@MainActor
@Test
func sendKeyActionSendsLongKeyInjectFrames() async throws {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
    _ = await transport.waitForSent(count: 1)

    await session.sendKey(.select, action: .press)
    await session.sendKey(.select, action: .release)

    let sent = await transport.waitForSent(count: 3)
    #expect(sent.count >= 3)
    #expect(sent[1] == framer.frame(try codec.encode(.key(.select, .press))))
    #expect(sent[2] == framer.frame(try codec.encode(.key(.select, .release))))
}

@MainActor
@Test
func connectedSessionReportsWhenRefreshIsNeeded() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    let device = DeviceRecord(name: "TV", host: "192.168.1.10")
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: device)

    #expect(!session.needsConnectionRefresh(for: device, idleTimeout: .infinity))
    #expect(session.needsConnectionRefresh(for: device, idleTimeout: 0))
    #expect(session.needsConnectionRefresh(for: DeviceRecord(name: "Other", host: "10.0.0.2"), idleTimeout: .infinity))
}

@MainActor
@Test
func textEntryUsesLatestImeStatus() async throws {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
    _ = await transport.waitForSent(count: 1)

    await transport.enqueueIncoming(framer.frame(remoteImeShowRequestFrame(counter: 9)))
    var attempts = 0
    while session.textFieldStatus?.counter != 9, attempts < 2000 {
        attempts += 1
        try? await Task.sleep(for: .milliseconds(1))
    }

    #expect(session.textFieldStatus?.label == "Search")
    let didSend = await session.sendText("Hi")
    #expect(didSend)

    let sent = await transport.waitForSent(count: 2)
    #expect(sent.count >= 2)
    #expect(sent[1] == framer.frame(try codec.encode(.text(RemoteTextEdit(imeCounter: 1, fieldCounter: 9, text: "Hi")))))
}

@MainActor
@Test
func sessionStoresImeKeyInjectAndBatchObservations() async throws {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
    _ = await transport.waitForSent(count: 1)

    await transport.enqueueIncoming(framer.frame(remoteImeKeyInjectFrame(
        packageName: "com.netflix.ninja",
        appLabel: "Netflix",
        counter: 42,
        value: "search",
        selectionStart: 6,
        selectionEnd: 6
    )))
    for _ in 0..<2000 where session.textFieldStatus?.counter != 42 {
        try? await Task.sleep(for: .milliseconds(1))
    }

    #expect(session.textFieldStatus?.value == "search")
    #expect(session.protocolState.imeApp?.value.appPackage == "com.netflix.ninja")
    #expect(session.protocolState.imeApp?.value.label == "Netflix")
    #expect(session.protocolState.imeApp?.source == "remote_ime_key_inject.app_info")
    #expect(session.protocolState.lastImeKeyInject?.value.textFieldStatus?.counter == 42)
    #expect(session.protocolState.lastImeKeyInject?.source == "remote_ime_key_inject")

    await transport.enqueueIncoming(framer.frame(remoteImeBatchEditFrame(
        imeCounter: 3,
        fieldCounter: 43,
        edits: [
            RemoteEditFixture(insert: 1, selectionStart: 3, selectionEnd: 3, value: "sea"),
            RemoteEditFixture(insert: 1, selectionStart: 6, selectionEnd: 6, value: "search")
        ]
    )))
    for _ in 0..<2000 where session.textFieldStatus?.counter != 43 {
        try? await Task.sleep(for: .milliseconds(1))
    }

    #expect(session.textFieldStatus == RemoteTextFieldStatus(
        imeCounter: 3,
        counter: 43,
        value: "search",
        selectionStart: 6,
        selectionEnd: 6
    ))
    #expect(session.protocolState.lastImeBatchEdit?.value.imeCounter == 3)
    #expect(session.protocolState.lastImeBatchEdit?.value.fieldCounter == 43)
    #expect(session.protocolState.lastImeBatchEdit?.value.edits.count == 2)
    #expect(session.protocolState.lastImeBatchEdit?.source == "remote_ime_batch_edit")
}

@MainActor
@Test
func textEntryUsesImeBatchEditStatusAndSendsOneCurrentBatch() async throws {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
    _ = await transport.waitForSent(count: 1)

    await transport.enqueueIncoming(framer.frame(remoteImeBatchEditFrame(imeCounter: 3, fieldCounter: 9)))
    var attempts = 0
    while session.textFieldStatus?.counter != 9, attempts < 2000 {
        attempts += 1
        try? await Task.sleep(for: .milliseconds(1))
    }

    #expect(session.textFieldStatus?.imeCounter == 3)
    let didSend = await session.sendText("Hi")
    #expect(didSend)

    let sent = await transport.waitForSent(count: 2)
    #expect(sent.count >= 2)
    #expect(sent[1] == framer.frame(try codec.encode(.text(RemoteTextEdit(imeCounter: 3, fieldCounter: 9, text: "Hi")))))
}

@MainActor
@Test
func textEntryRequiresFocusedTvField() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
    _ = await transport.waitForSent(count: 1)

    let didSend = await session.sendText("Hi")

    #expect(!didSend)
    #expect(session.lastError == "Open a text field on the TV before typing.")
    let sent = await transport.sentPayloads()
    #expect(sent.count == 1)
}

@MainActor
@Test
func voiceSessionStartsAfterTvVoiceBeginAndCanSendSamples() async throws {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
    _ = await transport.waitForSent(count: 1)

    let start = Task { await session.startVoiceSession(timeout: .milliseconds(200)) }
    var sent = await transport.waitForSent(count: 2)
    #expect(sent.count >= 2)
    #expect(sent[1] == framer.frame(try codec.encode(.key(.search, .tap))))

    await transport.enqueueIncoming(framer.frame(remoteVoiceBeginFrame(sessionID: 42)))
    let startResult = await start.value
    #expect(startResult == .started(sessionID: 42))

    sent = await transport.waitForSent(count: 3)
    #expect(sent[2] == framer.frame(try codec.encode(.voiceBegin(sessionID: 42))))

    let didSendSamples = await session.sendVoiceSamples(Data([0x01, 0x02]), sessionID: 42)
    #expect(didSendSamples)
    await session.endVoiceSession(sessionID: 42)

    sent = await transport.waitForSent(count: 5)
    #expect(sent[3] == framer.frame(try codec.encode(.voicePayload(sessionID: 42, samples: Data([0x01, 0x02])))))
    #expect(sent[4] == framer.frame(try codec.encode(.voiceEnd(sessionID: 42))))
}

@MainActor
@Test
func connectFailureSurfacesErrorDetail() async {
    let session = RemoteSession(transport: FailingTransport(), configureTimeout: .milliseconds(50))

    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))

    guard case let .failed(message) = session.connectionState else {
        Issue.record("expected failed state")
        return
    }
    #expect(message.contains("192.168.1.10"))
    #expect(session.lastError != nil)
}

@MainActor
@Test
func connectFailurePreservesTransportReason() async {
    let session = RemoteSession(transport: ReasonedFailingTransport(), configureTimeout: .milliseconds(50))

    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))

    guard case let .failed(message) = session.connectionState else {
        Issue.record("expected failed state")
        return
    }
    #expect(message.contains("Software caused connection abort"))
    #expect(session.lastError == message)
}

private actor FailingTransport: RemoteTransport {
    func connect(to host: String, port: UInt16) async throws {
        throw RemoteTransportError.connectionFailed
    }

    func send(_ data: Data) async throws {}

    func receive() async throws -> Data {
        throw RemoteTransportError.disconnected
    }

    func close() async {}

    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? {
        nil
    }
}

private actor ReasonedFailingTransport: RemoteTransport {
    func connect(to host: String, port: UInt16) async throws {
        throw RemoteTransportError.connectionFailedWithReason("Software caused connection abort")
    }

    func send(_ data: Data) async throws {}

    func receive() async throws -> Data {
        throw RemoteTransportError.disconnected
    }

    func close() async {}

    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? {
        nil
    }
}

@MainActor
@Test
func overlappingConnectsToSameDeviceShareOneAttempt() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    let device = DeviceRecord(name: "TV", host: "192.168.1.10")

    let first = Task { await session.connect(to: device) }
    let second = Task { await session.connect(to: device) }
    try? await Task.sleep(for: .milliseconds(20))
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await first.value
    await second.value

    #expect(session.connectionState == .connected)
    let dialCount = await transport.connectCount
    #expect(dialCount == 1)
}

@MainActor
@Test
func overlappingConnectsToSameDeviceDoNotResetProtocolObservations() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    let device = DeviceRecord(name: "TV", host: "192.168.1.10")

    let first = Task { await session.connect(to: device) }
    try? await Task.sleep(for: .milliseconds(20))
    let second = Task { await session.connect(to: device) }
    await transport.enqueueIncoming(framer.frame(remoteConfigureFrame(code: 64)))
    await first.value
    await second.value

    #expect(session.protocolState.negotiation.inboundConfigureCode?.value.rawValue == 64)
    let dialCount = await transport.connectCount
    #expect(dialCount == 1)
}

@MainActor
@Test
func disconnectResetsProtocolObservations() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(remoteConfigureFrame(code: 64)))
    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))

    #expect(session.protocolState.negotiation.inboundConfigureCode != nil)
    session.disconnect()

    #expect(session.connectionState == .disconnected)
    #expect(session.protocolState == RemoteSessionProtocolState())
}

@MainActor
@Test
func switchingDevicesAbandonsStaleHandshake() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport, configureTimeout: .milliseconds(80))
    let deviceA = DeviceRecord(name: "A", host: "10.0.0.1")
    let deviceB = DeviceRecord(name: "B", host: "10.0.0.2")

    // A connect that never receives a configure frame.
    let staleConnect = Task { await session.connect(to: deviceA) }
    try? await Task.sleep(for: .milliseconds(20))

    let freshConnect = Task { await session.connect(to: deviceB) }
    try? await Task.sleep(for: .milliseconds(20))
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await freshConnect.value
    await staleConnect.value

    // Wait past A's configure deadline: the stale attempt must not
    // overwrite B's connected state with a timeout failure.
    try? await Task.sleep(for: .milliseconds(150))
    #expect(session.connectionState == .connected)
    #expect(session.device?.id == deviceB.id)
}

@MainActor
@Test
func connectRecordsDialPhaseDurations() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))

    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))

    #expect(session.connectionState == .connected)
    #expect(session.lastTCPTLSMilliseconds != nil)
    #expect(session.lastConfigureMilliseconds != nil)
}

@MainActor
@Test
func volumePushUpdatesCountAndTimestamp() async throws {
    let volumeFrame = Data([0x92, 0x03, 0x06, 0x30, 0x64, 0x38, 0x19, 0x40, 0x01])
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await transport.enqueueIncoming(framer.frame(volumeFrame))

    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))

    // The read loop delivers the volume frame shortly after configure.
    for _ in 0..<100 where session.volumePushCount == 0 {
        try await Task.sleep(for: .milliseconds(5))
    }

    #expect(session.volumePushCount == 1)
    #expect(session.volumeStatus?.level == 25)
    #expect(session.volumeStatus?.maximum == 100)
    #expect(session.volumeStatus?.muted == true)
    #expect(session.lastVolumePushAt != nil)
}

private func remoteImeShowRequestFrame(counter: Int) -> Data {
    var status = ProtobufEncoder()
    status.appendVarint(field: 1, UInt64(counter))
    status.appendString(field: 2, "")
    status.appendVarint(field: 3, 0)
    status.appendVarint(field: 4, 0)
    status.appendVarint(field: 5, 0)
    status.appendString(field: 6, "Search")

    var showRequest = ProtobufEncoder()
    showRequest.appendMessage(field: 2, status.data)

    var message = ProtobufEncoder()
    message.appendMessage(field: 22, showRequest.data)
    return message.data
}

private func remoteImeBatchEditFrame(imeCounter: Int, fieldCounter: Int) -> Data {
    var object = ProtobufEncoder()
    object.appendVarint(field: 1, 0)
    object.appendVarint(field: 2, 0)
    object.appendString(field: 3, "")

    var editInfo = ProtobufEncoder()
    editInfo.appendVarint(field: 1, 1)
    editInfo.appendMessage(field: 2, object.data)

    var batchEdit = ProtobufEncoder()
    batchEdit.appendVarint(field: 1, UInt64(imeCounter))
    batchEdit.appendVarint(field: 2, UInt64(fieldCounter))
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
    appVersion: String? = "5.2.473254133"
) -> Data {
    var deviceInfo = ProtobufEncoder()
    if let model {
        deviceInfo.appendString(field: 1, model)
    }
    if let vendor {
        deviceInfo.appendString(field: 2, vendor)
    }
    deviceInfo.appendVarint(field: 3, 1)
    deviceInfo.appendString(field: 4, "1")
    if let packageName {
        deviceInfo.appendString(field: 5, packageName)
    }
    if let appVersion {
        deviceInfo.appendString(field: 6, appVersion)
    }

    var configure = ProtobufEncoder()
    if let code {
        configure.appendVarint(field: 1, code)
    }
    configure.appendMessage(field: 2, deviceInfo.data)

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

private func remoteImeKeyInjectFrame(
    packageName: String?,
    appLabel: String?,
    counter: Int?,
    value: String?,
    selectionStart: Int?,
    selectionEnd: Int?
) -> Data {
    var imeKeyInject = ProtobufEncoder()
    imeKeyInject.appendMessage(
        field: 1,
        remoteAppInfoPayload(packageName: packageName, appLabel: appLabel, counter: counter)
    )
    imeKeyInject.appendMessage(
        field: 2,
        remoteTextFieldStatusPayload(
            counter: counter,
            value: value,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd
        )
    )

    var message = ProtobufEncoder()
    message.appendMessage(field: 20, imeKeyInject.data)
    return message.data
}

private func remoteImeBatchEditFrame(
    imeCounter: Int?,
    fieldCounter: Int?,
    edits: [RemoteEditFixture]
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
