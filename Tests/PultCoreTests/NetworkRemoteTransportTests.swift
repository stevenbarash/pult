import Foundation
import Network
import Testing
@testable import PultCore

@Test
func networkOperationContinuationCompletesWhenCancelled() async {
    let operation = NetworkOperationContinuation<Void>()
    let task = Task {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.set(continuation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    await Task.yield()
    task.cancel()

    await #expect(throws: CancellationError.self) {
        try await task.value
    }
}

@Test
func networkOperationContinuationIgnoresLateCallbacksAfterCancellation() async {
    let operation = NetworkOperationContinuation<Void>()
    let task = Task {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.set(continuation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    await Task.yield()
    task.cancel()
    operation.resume(returning: ())

    await #expect(throws: CancellationError.self) {
        try await task.value
    }
}

/// A connection nobody answers must fail promptly. NWConnection reports
/// refused/unreachable endpoints as `.waiting` and retries forever; the
/// transport has to surface that as a failure or callers (including locked
/// screen intents, whose Control Center button stays highlighted while the
/// intent runs) suspend indefinitely.
@Test
func refusedConnectionFailsInsteadOfHangingForever() async {
    let transport = NetworkRemoteTransport(identityProvider: nil)
    // Port 1 on loopback: nothing listens there, so the TCP handshake is
    // refused immediately and NWConnection enters `.waiting`.
    nonisolated(unsafe) var finished = false
    nonisolated(unsafe) var thrown: Error?
    let attempt = Task.detached {
        do {
            try await transport.connect(to: "127.0.0.1", port: 1)
        } catch {
            thrown = error
        }
        finished = true
    }

    for _ in 0..<60 where !finished {
        try? await Task.sleep(for: .milliseconds(50))
    }

    #expect(finished, "connect() suspended past 3s for a refused connection")
    if finished {
        guard case let .connectionFailedWithReason(reason) = thrown as? RemoteTransportError else {
            Issue.record("expected reasoned connection failure")
            return
        }
        #expect(!reason.isEmpty)
    }
    attempt.cancel()
}

/// A handshake to a peer that accepts TCP but never completes TLS must fail
/// promptly (via the hard timeout, or an earlier TLS failure) rather than hang.
/// This guards the no-hang contract for a connect() that can't reach `.ready`;
/// the pure timeout path (sleeper -> cancelAll -> onCancel -> `.cancelled`
/// -> resume) is additionally covered by reasoning in the design review.
@Test
func connectTimesOutWhenHandshakeStalls() async throws {
    // Loopback TCP listener that accepts a connection and then does nothing —
    // it never responds to the TLS ClientHello, so the client parks in
    // `.preparing`.
    let listener = try NWListener(using: .tcp)
    nonisolated(unsafe) var accepted: [NWConnection] = []
    listener.newConnectionHandler = { connection in
        accepted.append(connection)
        connection.start(queue: .global())
    }
    listener.start(queue: .global())

    var resolvedPort: UInt16?
    for _ in 0..<80 where resolvedPort == nil {
        if let port = listener.port?.rawValue { resolvedPort = port }
        try? await Task.sleep(for: .milliseconds(25))
    }
    let boundPort = try #require(resolvedPort, "listener never bound a port")

    let transport = NetworkRemoteTransport(identityProvider: nil, connectTimeout: .milliseconds(300))
    let started = ContinuousClock.now
    var thrown: Error?
    do {
        try await transport.connect(to: "127.0.0.1", port: boundPort)
    } catch {
        thrown = error
    }
    let elapsed = ContinuousClock.now - started
    listener.cancel()
    await transport.close()

    switch thrown as? RemoteTransportError {
    case .connectionFailed, .connectionFailedWithReason:
        break
    default:
        Issue.record("expected connection failure")
    }
    #expect(elapsed < .seconds(3), "connect() should time out near 300ms, not hang")
}
