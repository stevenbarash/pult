import Foundation

/// Captures roughly when this process first touched the remote stack, used as a
/// fresh-launch heuristic in command timings. A static `let` initializes on
/// first access, so the app and the Lock Screen intent touch `start` as early
/// as possible (see PultApp / RemoteIntents). It is not an exact process age.
public enum ProcessClock {
    public static let start = ContinuousClock.now

    public static var ageMilliseconds: Double {
        start.duration(to: .now).millisecondsValue
    }
}
