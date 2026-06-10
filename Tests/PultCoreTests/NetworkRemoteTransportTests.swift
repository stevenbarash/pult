import Foundation
import Testing
@testable import PultCore

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
        #expect(thrown as? RemoteTransportError == .connectionFailed)
    }
    attempt.cancel()
}
