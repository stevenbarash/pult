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

    let sent = await transport.waitForSent(count: 3)
    #expect(sent.count >= 3)
    #expect(sent[1] == framer.frame(try codec.encode(.text(RemoteTextEdit(imeCounter: 1, fieldCounter: 9, insert: 72)))))
    #expect(sent[2] == framer.frame(try codec.encode(.text(RemoteTextEdit(imeCounter: 2, fieldCounter: 9, insert: 105)))))
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
