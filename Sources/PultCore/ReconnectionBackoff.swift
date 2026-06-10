import Foundation

public struct ReconnectionBackoff: Sendable {
    public var attempt: Int = 0
    public var baseDelay: Duration = .milliseconds(400)
    public var maxDelay: Duration = .seconds(12)

    public init() {}

    public mutating func nextDelay() -> Duration {
        let cappedAttempt = min(attempt, 6)
        attempt += 1

        let milliseconds = min(
            baseDelay.milliseconds * (1 << cappedAttempt),
            maxDelay.milliseconds
        )
        return .milliseconds(milliseconds)
    }

    public mutating func reset() {
        attempt = 0
    }
}

private extension Duration {
    var milliseconds: Int64 {
        let components = components
        let seconds = components.seconds * 1_000
        let attoseconds = components.attoseconds / 1_000_000_000_000_000
        return seconds + Int64(attoseconds)
    }
}
