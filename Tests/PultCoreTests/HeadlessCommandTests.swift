import Foundation
import Testing
@testable import PultCore

private let framer = VarintFramer()
private let codec = AndroidTVRemoteMessageCodec()
private let tvConfigureFrame = Data([0x0A, 0x02, 0x08, 0x01])

@MainActor
private func makeModel(transport: any RemoteTransport, device: DeviceRecord) -> RemoteControlModel {
    let store = MemoryDeviceStore()
    store.records = [device]
    store.selectedID = device.id
    return RemoteControlModel(
        discovery: DeviceDiscovery(store: store),
        session: RemoteSession(transport: transport, configureTimeout: .milliseconds(200))
    )
}

@MainActor
@Test
func headlessCommandConnectsAndSendsKey() async throws {
    let transport = MockTransport()
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: true)
    let model = makeModel(transport: transport, device: device)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))

    let outcome = await model.performHeadlessCommand(.playPause)

    #expect(outcome == .sent)
    let sent = await transport.waitForSent(count: 2)
    #expect(sent.last == framer.frame(try codec.encode(.key(.playPause, .tap))))
}

@MainActor
@Test
func headlessCommandFailsWithoutPairedSelection() async {
    let transport = MockTransport()
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: false)
    let model = makeModel(transport: transport, device: device)

    let outcome = await model.performHeadlessCommand(.home)

    guard case .failed = outcome else {
        Issue.record("expected failure for unpaired device")
        return
    }
    let dialCount = await transport.connectCount
    #expect(dialCount == 0)
}

@MainActor
@Test
func headlessCommandReportsUnreachableTV() async {
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: true)
    let model = makeModel(transport: UnreachableTransport(), device: device)

    let outcome = await model.performHeadlessCommand(.home)

    guard case let .failed(message) = outcome else {
        Issue.record("expected failure")
        return
    }
    #expect(message.contains("192.168.1.10"))
}

@MainActor
@Test
func headlessCommandRedialsWhenStaleConnectionDies() async throws {
    let transport = StaleAfterConfigureTransport(
        configureFrame: framer.frame(tvConfigureFrame),
        configureResponse: framer.frame(codec.encodeConfigureResponse())
    )
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: true)
    let model = makeModel(transport: transport, device: device)

    // First call establishes the session normally.
    #expect(await model.performHeadlessCommand(.home) == .sent)
    await transport.killNextKeySend()

    // The session still reports connected, but the socket is dead: the model
    // must redial once and deliver on the fresh connection.
    let outcome = await model.performHeadlessCommand(.volumeUp)

    #expect(outcome == .sent)
    let dialCount = await transport.connectCount
    #expect(dialCount == 2)
    let keyPayloads = await transport.keyPayloads()
    #expect(keyPayloads.last == framer.frame(try codec.encode(.key(.volumeUp, .tap))))
}

private actor UnreachableTransport: RemoteTransport {
    func connect(to host: String, port: UInt16) async throws {
        throw RemoteTransportError.connectionFailed
    }
    func send(_ data: Data) async throws {}
    func receive() async throws -> Data { throw RemoteTransportError.disconnected }
    func close() async {}
    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? { nil }
}

/// Answers the configure handshake on every dial; key sends can be made to
/// fail exactly once to simulate a connection that died while the app was
/// suspended.
private actor StaleAfterConfigureTransport: RemoteTransport {
    private let configureFrame: Data
    private let configureResponse: Data
    private(set) var connectCount = 0
    private var incoming: [Data] = []
    private var keys: [Data] = []
    private var failNextKeySend = false
    private var closed = false

    init(configureFrame: Data, configureResponse: Data) {
        self.configureFrame = configureFrame
        self.configureResponse = configureResponse
    }

    func killNextKeySend() { failNextKeySend = true }

    func keyPayloads() -> [Data] { keys }

    func connect(to host: String, port: UInt16) async throws {
        connectCount += 1
        closed = false
        incoming = [configureFrame]
    }

    func send(_ data: Data) async throws {
        if data == configureResponse { return }
        if failNextKeySend {
            failNextKeySend = false
            throw RemoteTransportError.disconnected
        }
        keys.append(data)
    }

    func receive() async throws -> Data {
        while incoming.isEmpty {
            if closed { throw RemoteTransportError.disconnected }
            try await Task.sleep(for: .milliseconds(1))
        }
        return incoming.removeFirst()
    }

    func close() async { closed = true }

    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? { nil }
}
