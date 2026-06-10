import Foundation
@testable import PultCore

final class MemoryDeviceStore: DeviceStore {
    var records: [DeviceRecord] = []
    var selectedID: UUID?

    func loadDevices() -> [DeviceRecord] { records }

    func saveDevices(_ devices: [DeviceRecord]) { records = devices }

    func loadSelectedDeviceID() -> UUID? { selectedID }

    func saveSelectedDeviceID(_ id: UUID?) { selectedID = id }
}

/// Scripted transport: incoming frames are enqueued by tests, sent frames are
/// recorded for assertions.
actor MockTransport: RemoteTransport {
    private(set) var endpoint: (host: String, port: UInt16)?
    private(set) var connectCount = 0
    private var incoming: [Data] = []
    private var sent: [Data] = []
    private var peerParameters: RSAPublicKeyParameters?
    private var closed = false

    func enqueueIncoming(_ data: Data) {
        incoming.append(data)
    }

    func setPeerParameters(_ parameters: RSAPublicKeyParameters) {
        peerParameters = parameters
    }

    func connect(to host: String, port: UInt16) async throws {
        connectCount += 1
        endpoint = (host, port)
        closed = false
    }

    func send(_ data: Data) async throws {
        sent.append(data)
    }

    func receive() async throws -> Data {
        while incoming.isEmpty {
            if closed {
                throw RemoteTransportError.disconnected
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        return incoming.removeFirst()
    }

    func close() async {
        closed = true
    }

    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? {
        peerParameters
    }

    func sentPayloads() -> [Data] {
        sent
    }

    func waitForSent(count: Int) async -> [Data] {
        var attempts = 0
        while sent.count < count, attempts < 2000 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(1))
        }
        return sent
    }
}
