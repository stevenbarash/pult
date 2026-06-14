import Foundation

public enum PairingState: Equatable, Sendable {
    case idle
    case connecting
    case waitingForCode
    case verifying
    case paired
    case failed(String)
}

public enum PairingSessionError: Error, Equatable {
    case notStarted
    case unexpectedMessage
    case rejected(PairingMessage.Status)
    case missingPeerCertificate
    case timedOut
}

/// Drives the Android TV Remote Service v2 pairing handshake on the pairing
/// port. `start` runs the exchange up to the point where the TV displays the
/// 6-digit code; `submit` finishes it with the user-entered code.
public actor PairingSession {
    private let transport: RemoteTransport
    private let framer: VarintFramer
    private let serviceName: String
    private let clientName: String
    private let receiveTimeout: Duration
    private var buffer = Data()
    private var clientParameters: RSAPublicKeyParameters?

    public init(
        transport: RemoteTransport = NetworkRemoteTransport(),
        serviceName: String = "app.pult",
        clientName: String = "Pult",
        framer: VarintFramer = VarintFramer(),
        receiveTimeout: Duration = .seconds(12)
    ) {
        self.transport = transport
        self.serviceName = serviceName
        self.clientName = clientName
        self.framer = framer
        self.receiveTimeout = receiveTimeout
    }

    public func start(for device: DeviceRecord, clientParameters: RSAPublicKeyParameters) async throws {
        self.clientParameters = clientParameters
        buffer.removeAll()

        try await transport.connect(to: device.host, port: device.pairingPort)
        try await send(PairingMessageCoder.encodeRequest(serviceName: serviceName, clientName: clientName))
        guard case .requestAck = try await receiveMessage().kind else {
            throw PairingSessionError.unexpectedMessage
        }
        try await send(PairingMessageCoder.encodeOption())
        guard case .option = try await receiveMessage().kind else {
            throw PairingSessionError.unexpectedMessage
        }
        try await send(PairingMessageCoder.encodeConfiguration())
        guard case .configurationAck = try await receiveMessage().kind else {
            throw PairingSessionError.unexpectedMessage
        }
        // The TV is now displaying the pairing code.
    }

    public func submit(code: PairingCode) async throws {
        guard let clientParameters else {
            throw PairingSessionError.notStarted
        }
        guard let serverParameters = try await transport.peerRSAPublicKeyParameters() else {
            throw PairingSessionError.missingPeerCertificate
        }

        let secret = try PairingSecretHasher.secret(
            client: clientParameters,
            server: serverParameters,
            code: code
        )
        try await send(PairingMessageCoder.encodeSecret(secret))
        guard case .secretAck = try await receiveMessage().kind else {
            throw PairingSessionError.unexpectedMessage
        }
        await transport.close()
    }

    public func cancel() async {
        await transport.close()
    }

    private func send(_ payload: Data) async throws {
        try await transport.send(framer.frame(payload))
    }

    private func receiveMessage() async throws -> PairingMessage {
        while true {
            if let frame = try framer.nextFrame(from: &buffer) {
                let message = try PairingMessageCoder.decode(frame)
                guard message.status == .ok else {
                    throw PairingSessionError.rejected(message.status)
                }
                return message
            }
            let chunk = try await receiveWithTimeout()
            if chunk.isEmpty {
                await Task.yield()
                continue
            }
            buffer.append(chunk)
        }
    }

    /// A single `transport.receive()` bounded by `receiveTimeout`. A TV that
    /// accepts the connection but never sends the expected ack (mid-reboot,
    /// wrong service, half-open socket) would otherwise suspend the handshake
    /// forever. On timeout the transport is closed so the in-flight receive
    /// unblocks (the continuation isn't cancellation-aware on its own), then we
    /// surface `.timedOut`.
    private func receiveWithTimeout() async throws -> Data {
        let transport = self.transport
        let timeout = self.receiveTimeout
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await transport.receive()
                } onCancel: {
                    Task { await transport.close() }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw PairingSessionError.timedOut
            }
            defer { group.cancelAll() }
            guard let chunk = try await group.next() else {
                throw PairingSessionError.timedOut
            }
            return chunk
        }
    }
}
