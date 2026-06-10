import Foundation
import Observation

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

@MainActor
@Observable
public final class RemoteSession {
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var lastError: String?
    /// The device this session is connected or connecting to.
    public private(set) var device: DeviceRecord?

    private let transport: RemoteTransport
    private let codec: RemoteMessageCodec
    private let framer: VarintFramer
    private let configureTimeout: Duration
    private var readTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var connectAttempt = 0

    public init(
        transport: RemoteTransport = NetworkRemoteTransport(),
        codec: RemoteMessageCodec = AndroidTVRemoteMessageCodec(),
        framer: VarintFramer = VarintFramer(),
        configureTimeout: Duration = .seconds(5)
    ) {
        self.transport = transport
        self.codec = codec
        self.framer = framer
        self.configureTimeout = configureTimeout
    }

    public func connect(to device: DeviceRecord) async {
        // Join an in-flight connect to the same device instead of restarting
        // it, so overlapping triggers don't tear down each other's handshake.
        if connectionState == .connecting, self.device?.id == device.id, let connectTask {
            await connectTask.value
            return
        }

        connectAttempt += 1
        let attempt = connectAttempt
        self.device = device
        connectionState = .connecting
        lastError = nil

        // The handshake runs in its own task so cancellation of the caller
        // (a re-fired SwiftUI .task, for example) cannot abandon it midway.
        let task = Task { await performConnect(to: device, attempt: attempt) }
        connectTask = task
        await task.value
    }

    private func performConnect(to device: DeviceRecord, attempt: Int) async {
        readTask?.cancel()
        readTask = nil
        await transport.close()
        guard attempt == connectAttempt else { return }

        do {
            try await transport.connect(to: device.host, port: device.commandPort)
        } catch {
            fail(with: "Could not reach \(device.host): \(describe(error))", attempt: attempt)
            return
        }
        guard attempt == connectAttempt else { return }

        startReadLoop(attempt: attempt)
        await waitForConfiguration(attempt: attempt)
    }

    public func disconnect() {
        connectAttempt += 1
        readTask?.cancel()
        readTask = nil
        connectionState = .disconnected
        Task {
            await transport.close()
        }
    }

    public func press(_ key: RemoteKey) async {
        await sendIgnoringErrors(.key(key, .tap))
    }

    public func sendText(_ text: String) async {
        guard !text.isEmpty else { return }
        await sendIgnoringErrors(.text(text))
    }

    public func openAppLink(_ url: URL) async {
        await sendIgnoringErrors(.appLink(url))
    }

    private func startReadLoop(attempt: Int) {
        readTask = Task { [weak self] in
            var buffer = Data()
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let chunk = try await self.transport.receive()
                    guard self.connectAttempt == attempt, !Task.isCancelled else { return }
                    if chunk.isEmpty {
                        await Task.yield()
                        continue
                    }
                    buffer.append(chunk)
                    while let frame = try self.framer.nextFrame(from: &buffer) {
                        try await self.handle(frame, attempt: attempt)
                    }
                } catch {
                    if !Task.isCancelled, self.connectAttempt == attempt {
                        self.fail(with: self.describe(error))
                    }
                    return
                }
            }
        }
    }

    private func handle(_ frame: Data, attempt: Int) async throws {
        switch try codec.decode(frame) {
        case .configure:
            try await send(codec.encodeConfigureResponse())
            if attempt == connectAttempt {
                connectionState = .connected
            }
        case .setActive:
            try await send(codec.encodeSetActiveResponse())
        case let .pingRequest(value):
            try await send(codec.encodePingResponse(value))
        case .error:
            lastError = "The TV reported a remote error"
        case .started, .volume, .other:
            break
        }
    }

    private func waitForConfiguration(attempt: Int) async {
        let deadline = ContinuousClock.now.advanced(by: configureTimeout)
        while connectionState == .connecting, connectAttempt == attempt, ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return
            }
        }
        if connectionState == .connecting, connectAttempt == attempt {
            fail(with: "The TV accepted the connection but did not complete the remote handshake. It may need pairing first.", attempt: attempt)
        }
    }

    private func sendIgnoringErrors(_ command: RemoteCommand) async {
        do {
            try await send(codec.encode(command))
        } catch RemoteMessageCodecError.unsupportedCommand {
            lastError = "This command isn't supported yet"
        } catch {
            fail(with: describe(error))
        }
    }

    private func send(_ payload: Data) async throws {
        try await transport.send(framer.frame(payload))
    }

    private func fail(with message: String, attempt: Int? = nil) {
        if let attempt, attempt != connectAttempt { return }
        lastError = message
        connectionState = .failed(message)
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case RemoteTransportError.connectionFailed:
            "TLS connection failed — check that the TV is on and paired"
        case RemoteTransportError.disconnected:
            "The TV closed the connection"
        default:
            error.localizedDescription
        }
    }
}
