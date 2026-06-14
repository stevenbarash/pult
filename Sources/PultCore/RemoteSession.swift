import Foundation
import Observation

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

public struct RemoteVolumeStatus: Equatable, Sendable {
    public var level: UInt64
    public var maximum: UInt64
    public var muted: Bool

    public init(level: UInt64, maximum: UInt64, muted: Bool) {
        self.level = level
        self.maximum = maximum
        self.muted = muted
    }

    public var normalizedLevel: Double {
        guard maximum > 0 else { return 0 }
        return min(max(Double(level) / Double(maximum), 0), 1)
    }
}

public enum RemoteCommandSendResult: Equatable, Sendable {
    case sent
    case failed(String)
}

@MainActor
@Observable
public final class RemoteSession {
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var lastError: String?
    /// The device this session is connected or connecting to.
    public private(set) var device: DeviceRecord?
    /// Latest focused text field state published by the TV's IME channel.
    public private(set) var textFieldStatus: RemoteTextFieldStatus?
    /// Latest volume state published by the TV, when the device reports it.
    public private(set) var volumeStatus: RemoteVolumeStatus?
    /// Last time a framed protocol message arrived from the TV.
    public private(set) var lastReceivedAt: Date?
    /// Last time a framed protocol message was sent to the TV.
    public private(set) var lastSentAt: Date?

    private let transport: RemoteTransport
    private let codec: RemoteMessageCodec
    private let framer: VarintFramer
    private let configureTimeout: Duration
    private var readTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var connectAttempt = 0
    private var nextImeCounter = 0

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
        textFieldStatus = nil
        volumeStatus = nil
        lastReceivedAt = nil
        lastSentAt = nil
        nextImeCounter = 0

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
        textFieldStatus = nil
        volumeStatus = nil
        nextImeCounter = 0
        Task {
            await transport.close()
        }
    }

    public func needsConnectionRefresh(
        for device: DeviceRecord,
        idleTimeout: TimeInterval = 90,
        now: Date = .now
    ) -> Bool {
        guard connectionState == .connected, self.device?.id == device.id else {
            return true
        }
        guard idleTimeout.isFinite else {
            return false
        }
        guard let lastReceivedAt else {
            return true
        }
        return now.timeIntervalSince(lastReceivedAt) >= idleTimeout
    }

    @discardableResult
    public func press(_ key: RemoteKey) async -> Bool {
        await sendKey(key, action: .tap)
    }

    @discardableResult
    public func sendKey(_ key: RemoteKey, action: KeyAction) async -> Bool {
        await sendIgnoringErrors(.key(key, action)) == .sent
    }

    @discardableResult
    public func sendText(_ text: String) async -> Bool {
        guard !text.isEmpty else { return true }
        guard connectionState == .connected else {
            lastError = "Connect to the TV before typing."
            return false
        }
        guard let textFieldStatus else {
            lastError = "Open a text field on the TV before typing."
            return false
        }

        for scalar in text.unicodeScalars {
            nextImeCounter += 1
            let edit = RemoteTextEdit(
                imeCounter: nextImeCounter,
                fieldCounter: textFieldStatus.counter,
                insert: scalar.value
            )

            do {
                try await send(codec.encode(.text(edit)))
            } catch {
                fail(with: describe(error))
                return false
            }
        }

        lastError = nil
        return true
    }

    @discardableResult
    public func openAppLink(_ url: URL) async -> Bool {
        await sendIgnoringErrors(.appLink(url)) == .sent
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
        lastReceivedAt = .now
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
        case .started, .other:
            break
        case let .volume(level, maximum, muted):
            volumeStatus = RemoteVolumeStatus(level: level, maximum: maximum, muted: muted)
        case let .textFieldStatus(status):
            if textFieldStatus?.counter != status.counter {
                nextImeCounter = 0
            }
            textFieldStatus = status
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

    private func sendIgnoringErrors(_ command: RemoteCommand) async -> RemoteCommandSendResult {
        do {
            try await send(codec.encode(command))
            lastError = nil
            return .sent
        } catch RemoteMessageCodecError.unsupportedCommand {
            lastError = "This command isn't supported yet"
            return .failed(lastError ?? "Unsupported command")
        } catch {
            let message = describe(error)
            fail(with: message)
            return .failed(message)
        }
    }

    private func send(_ payload: Data) async throws {
        try await transport.send(framer.frame(payload))
        lastSentAt = .now
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
