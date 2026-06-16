import Foundation
import os

/// Sink for `CommandTiming` samples. Injected into `RemoteControlModel` so the
/// hot command path can skip all measurement bookkeeping when disabled, and so
/// tests can capture timings.
public protocol CommandTimingRecording: Sendable {
    /// Whether timings are currently being recorded.
    var isEnabled: Bool { get }
    func record(_ timing: CommandTiming)
}

/// Records command timings to the shared App Group log and emits an
/// `os_signpost` event per command. Gated by a runtime flag in App Group
/// defaults that the Diagnostics screen toggles, so it never writes for normal
/// TestFlight users.
public struct CommandTimingRecorder: CommandTimingRecording {
    public static let enabledDefaultsKey = "pult.measureTimings"

    private let log: CommandTimingLog?
    nonisolated(unsafe) private let defaults: UserDefaults
    private let signposter: OSSignposter

    public init(
        log: CommandTimingLog? = CommandTimingLog.appGroup(),
        defaults: UserDefaults = PultAppGroup.sharedDefaults()
    ) {
        self.log = log
        self.defaults = defaults
        self.signposter = OSSignposter(subsystem: "app.pult", category: "command-timing")
    }

    public var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    public func record(_ timing: CommandTiming) {
        guard isEnabled else { return }
        signposter.emitEvent(
            "command",
            "\(timing.key, privacy: .public) \(timing.classification, privacy: .public) \(Int(timing.totalMs.rounded()))ms"
        )
        log?.record(timing)
    }

    /// Reads the runtime flag (used by the Diagnostics toggle).
    public static func isEnabled(defaults: UserDefaults = PultAppGroup.sharedDefaults()) -> Bool {
        defaults.bool(forKey: enabledDefaultsKey)
    }

    /// Sets the runtime flag (used by the Diagnostics toggle).
    public static func setEnabled(_ enabled: Bool, defaults: UserDefaults = PultAppGroup.sharedDefaults()) {
        defaults.set(enabled, forKey: enabledDefaultsKey)
    }
}
