import Testing
@testable import PultCore

@Test
func backsOffExponentiallyAndResets() {
    var backoff = ReconnectionBackoff()

    #expect(backoff.nextDelay() == .milliseconds(400))
    #expect(backoff.nextDelay() == .milliseconds(800))
    #expect(backoff.nextDelay() == .milliseconds(1_600))

    backoff.reset()
    #expect(backoff.nextDelay() == .milliseconds(400))
}
