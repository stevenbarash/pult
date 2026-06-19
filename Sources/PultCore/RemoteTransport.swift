import Foundation
import Darwin
import Network
import Security

public protocol RemoteTransport: Sendable {
    func connect(to host: String, port: UInt16) async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
    /// RSA parameters of the certificate the peer presented during the TLS
    /// handshake; nil before a connection is established.
    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters?
}

public enum RemoteTransportError: Error, Equatable {
    case connectionFailed
    case connectionFailedWithReason(String)
    case disconnected
    case invalidPort
    case identityUnavailable
}

/// TLS transport for the Android TV Remote Service. The service requires
/// mutual TLS: the client presents the persistent identity created at pairing
/// time, and the TV presents a self-signed certificate whose trust is
/// established by the pairing secret rather than a CA chain.
public actor NetworkRemoteTransport: RemoteTransport {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "app.pult.remote-transport", qos: .userInitiated)
    private let identityProvider: (any ClientIdentityProviding)?
    private let peerCertificate = PeerCertificateBox()
    private let connectTimeout: Duration

    public init(
        identityProvider: (any ClientIdentityProviding)? = KeychainClientIdentityStore.shared,
        connectTimeout: Duration = .seconds(8)
    ) {
        self.identityProvider = identityProvider
        self.connectTimeout = connectTimeout
    }

    public func connect(to host: String, port: UInt16) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw RemoteTransportError.invalidPort
        }

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)

        if let identityProvider {
            let identity = try identityProvider.identity()
            guard let secIdentity = sec_identity_create(identity) else {
                throw RemoteTransportError.identityUnavailable
            }
            sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
        }

        let peerCertificate = peerCertificate
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, trust, complete in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                if let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                   let leaf = chain.first {
                    peerCertificate.store(leaf)
                }
                // The TV's certificate is self-signed; authenticity is proven
                // by the pairing secret, not a CA chain.
                complete(true)
            },
            queue
        )

        let parameters = NWParameters(tls: tlsOptions)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        self.connection = connection

        let queue = self.queue
        let connectTimeout = self.connectTimeout
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    // The continuation isn't cancellation-aware, so on task
                    // cancellation (timeout, or an external close racing the
                    // handshake) we cancel the NWConnection; its `.cancelled`
                    // state then resumes the continuation below. Without this
                    // the task group would deadlock awaiting a child that never
                    // finishes.
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            let gate = ContinuationGate()
                            connection.stateUpdateHandler = { state in
                                switch state {
                                case .ready:
                                    gate.resume { continuation.resume() }
                                case let .failed(error):
                                    gate.resume {
                                        continuation.resume(throwing: RemoteTransportError.connectionFailedWithReason(Self.describe(error)))
                                    }
                                case .cancelled:
                                    // `.cancelled` happens when disconnect()/device
                                    // switch closes the socket mid-handshake; resume
                                    // so connect() can't hang forever.
                                    gate.resume {
                                        continuation.resume(throwing: RemoteTransportError.connectionFailed)
                                    }
                                case let .waiting(error):
                                    // Refused, unreachable, and policy-denied dials all
                                    // land here, and NWConnection then retries until the
                                    // network changes. For a LAN remote that means "the
                                    // TV is not reachable right now": fail fast so callers
                                    // (lock-screen intents especially) never suspend
                                    // indefinitely; retry policy lives in the session
                                    // layer above.
                                    gate.resume {
                                        connection.cancel()
                                        continuation.resume(throwing: RemoteTransportError.connectionFailedWithReason(Self.describe(error)))
                                    }
                                default:
                                    break
                                }
                            }
                            connection.start(queue: queue)
                        }
                    } onCancel: {
                        connection.cancel()
                    }
                }
                group.addTask {
                    // Hard ceiling: a handshake stalled in `.preparing` never
                    // fires .ready/.failed/.waiting, so without this it could
                    // hang past the session's configure timeout.
                    try await Task.sleep(for: connectTimeout)
                    throw RemoteTransportError.connectionFailedWithReason("Timed out.")
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        } catch {
            connection.cancel()
            throw error
        }
    }

    public func send(_ data: Data) async throws {
        guard let connection else { throw RemoteTransportError.disconnected }

        let operation = NetworkOperationContinuation<Void>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.set(continuation)
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        operation.resume(throwing: error)
                    } else {
                        operation.resume(returning: ())
                    }
                })
            }
        } onCancel: {
            operation.cancel()
            connection.cancel()
        }
    }

    public func receive() async throws -> Data {
        guard let connection else { throw RemoteTransportError.disconnected }

        let operation = NetworkOperationContinuation<Data>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.set(continuation)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error {
                        operation.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        operation.resume(returning: data)
                    } else if isComplete {
                        operation.resume(throwing: RemoteTransportError.disconnected)
                    } else {
                        operation.resume(returning: Data())
                    }
                }
            }
        } onCancel: {
            operation.cancel()
            connection.cancel()
        }
    }

    public func close() async {
        connection?.cancel()
        connection = nil
        peerCertificate.store(nil)
    }

    public func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? {
        guard let certificate = peerCertificate.current,
              let key = SecCertificateCopyKey(certificate),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return nil
        }
        return try RSAPublicKeyParameters(pkcs1: keyData)
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case let .posix(code):
            return String(cString: strerror(code.rawValue))
        case .dns:
            return "DNS lookup failed."
        case .tls:
            return "TLS setup failed."
        case .wifiAware:
            return "Wi-Fi Aware connection failed."
        @unknown default:
            return "Network connection failed."
        }
    }
}

private final class PeerCertificateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var certificate: SecCertificate?

    var current: SecCertificate? {
        lock.lock()
        defer { lock.unlock() }
        return certificate
    }

    func store(_ certificate: SecCertificate?) {
        lock.lock()
        defer { lock.unlock() }
        self.certificate = certificate
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        body()
    }
}

final class NetworkOperationContinuation<Value: Sendable>: @unchecked Sendable {
    private enum State {
        case pending
        case waiting(CheckedContinuation<Value, Error>)
        case resumed
    }

    private let lock = NSLock()
    private var state: State = .pending

    func set(_ continuation: CheckedContinuation<Value, Error>) {
        let shouldCancel: Bool
        lock.lock()
        switch state {
        case .pending:
            state = .waiting(continuation)
            shouldCancel = false
        case .resumed:
            shouldCancel = true
        case .waiting:
            preconditionFailure("Network operation continuation was set more than once")
        }
        lock.unlock()

        if shouldCancel {
            continuation.resume(throwing: CancellationError())
        }
    }

    func cancel() {
        resume(throwing: CancellationError())
    }

    func resume(returning value: Value) {
        resume { continuation in
            continuation.resume(returning: value)
        }
    }

    func resume(throwing error: Error) {
        resume { continuation in
            continuation.resume(throwing: error)
        }
    }

    private func resume(_ body: (CheckedContinuation<Value, Error>) -> Void) {
        let continuation: CheckedContinuation<Value, Error>?
        lock.lock()
        switch state {
        case .pending:
            state = .resumed
            continuation = nil
        case let .waiting(current):
            state = .resumed
            continuation = current
        case .resumed:
            continuation = nil
        }
        lock.unlock()

        if let continuation {
            body(continuation)
        }
    }
}
