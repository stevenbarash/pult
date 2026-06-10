import Foundation
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

    public init(identityProvider: (any ClientIdentityProviding)? = KeychainClientIdentityStore.shared) {
        self.identityProvider = identityProvider
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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resume {
                        continuation.resume()
                    }
                case .failed:
                    gate.resume {
                        continuation.resume(throwing: RemoteTransportError.connectionFailed)
                    }
                case .waiting:
                    // Refused, unreachable, and policy-denied dials all land
                    // here, and NWConnection then retries until the network
                    // changes. For a LAN remote that means "the TV is not
                    // reachable right now": fail fast so callers (lock-screen
                    // intents especially) never suspend indefinitely; retry
                    // policy lives in the session layer above.
                    gate.resume {
                        connection.cancel()
                        continuation.resume(throwing: RemoteTransportError.connectionFailed)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    public func send(_ data: Data) async throws {
        guard let connection else { throw RemoteTransportError.disconnected }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func receive() async throws -> Data {
        guard let connection else { throw RemoteTransportError.disconnected }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: RemoteTransportError.disconnected)
                } else {
                    continuation.resume(returning: Data())
                }
            }
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
