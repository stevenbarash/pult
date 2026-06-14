import Foundation
import Testing
@testable import PultCore

private let framer = VarintFramer()
private let client = RSAPublicKeyParameters(modulus: Data([0xC0, 0xFF, 0xEE]), exponent: Data([0x01, 0x00, 0x01]))
private let server = RSAPublicKeyParameters(modulus: Data([0xBE, 0xEF]), exponent: Data([0x01, 0x00, 0x01]))

@Test
func runsFullPairingHandshake() async throws {
    let transport = MockTransport()
    let session = PairingSession(transport: transport, serviceName: "svc", clientName: "cli")

    await transport.enqueueIncoming(framer.frame(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0x5A, 0x04, 0x0A, 0x02, 0x74, 0x76])))
    await transport.enqueueIncoming(framer.frame(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0xA2, 0x01, 0x00])))
    await transport.enqueueIncoming(framer.frame(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0xFA, 0x01, 0x00])))

    try await session.start(for: DeviceRecord(name: "TV", host: "192.168.1.10"), clientParameters: client)

    let endpoint = await transport.endpoint
    #expect(endpoint?.port == 6467)
    let sent = await transport.sentPayloads()
    #expect(sent.count == 3)
    #expect(sent[0] == framer.frame(PairingMessageCoder.encodeRequest(serviceName: "svc", clientName: "cli")))
    #expect(sent[1] == framer.frame(PairingMessageCoder.encodeOption()))
    #expect(sent[2] == framer.frame(PairingMessageCoder.encodeConfiguration()))

    await transport.setPeerParameters(server)
    await transport.enqueueIncoming(framer.frame(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0xCA, 0x02, 0x02, 0x0A, 0x00])))

    try await session.submit(code: PairingCode(rawValue: "D92B3C")!)

    let allSent = await transport.sentPayloads()
    #expect(allSent.count == 4)
    let expectedSecret = try PairingSecretHasher.secret(client: client, server: server, code: PairingCode(rawValue: "D92B3C")!)
    #expect(allSent[3] == framer.frame(PairingMessageCoder.encodeSecret(expectedSecret)))
}

@Test
func startTimesOutWhenTVNeverAcks() async {
    // MockTransport with nothing enqueued: receive() never returns, simulating a
    // TV that accepts the connection but never sends the requestAck.
    let transport = MockTransport()
    let session = PairingSession(
        transport: transport,
        serviceName: "svc",
        clientName: "cli",
        receiveTimeout: .milliseconds(150)
    )

    await #expect(throws: PairingSessionError.timedOut) {
        try await session.start(for: DeviceRecord(name: "TV", host: "192.168.1.10"), clientParameters: client)
    }
}

@Test
func surfacesTVRejection() async throws {
    let transport = MockTransport()
    let session = PairingSession(transport: transport, serviceName: "svc", clientName: "cli")

    // STATUS_ERROR (400) in response to the pairing request.
    await transport.enqueueIncoming(framer.frame(Data([0x08, 0x02, 0x10, 0x90, 0x03])))

    await #expect(throws: PairingSessionError.rejected(.error)) {
        try await session.start(for: DeviceRecord(name: "TV", host: "192.168.1.10"), clientParameters: client)
    }
}
