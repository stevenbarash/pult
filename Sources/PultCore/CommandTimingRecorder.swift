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
            "\(timing.key, privacy: .public) \(timing.classification, privacy: .public) \(Int(timing.totalMs.rounded()), privacy: .public)ms"
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

public enum AppTelemetryCategory: String, Sendable {
    case appLifecycle = "app-lifecycle"
    case command
    case diagnostics
    case discovery
    case favoriteApps = "favorite-apps"
    case keyboard
    case pairing
    case reachability
    case remoteSession = "remote-session"
}

public enum AppTelemetryOutcome: String, Sendable {
    case cancelled
    case failed
    case skipped
    case started
    case succeeded
    case unavailable
}

public enum AppTelemetryValue: Equatable, Sendable {
    case `public`(String)
    case `private`(String)

    var publicDescription: String? {
        switch self {
        case let .public(value):
            value.isEmpty ? nil : value
        case .private:
            nil
        }
    }
}

public struct AppTelemetryEvent: Equatable, Sendable {
    public var category: AppTelemetryCategory
    public var action: String
    public var outcome: AppTelemetryOutcome
    public var durationMilliseconds: Double?
    public var metadata: [String: AppTelemetryValue]

    public init(
        category: AppTelemetryCategory,
        action: String,
        outcome: AppTelemetryOutcome,
        durationMilliseconds: Double? = nil,
        metadata: [String: AppTelemetryValue] = [:]
    ) {
        self.category = category
        self.action = action
        self.outcome = outcome
        self.durationMilliseconds = durationMilliseconds
        self.metadata = metadata
    }

    public var logMetadataDescription: String {
        metadata
            .sorted { $0.key < $1.key }
            .compactMap { key, value -> String? in
                guard let publicValue = value.publicDescription else { return nil }
                return "\(key)=\(publicValue)"
            }
            .joined(separator: " ")
    }
}

public protocol AppTelemetryRecording: Sendable {
    func record(_ event: AppTelemetryEvent)
}

public struct NullAppTelemetryRecorder: AppTelemetryRecording {
    public init() {}
    public func record(_ event: AppTelemetryEvent) {}
}

public struct OSLogAppTelemetryRecorder: AppTelemetryRecording {
    private let subsystem: String

    public init(subsystem: String = "app.pult", category: AppTelemetryCategory) {
        self.subsystem = subsystem
    }

    public func record(_ event: AppTelemetryEvent) {
        let logger = Logger(subsystem: subsystem, category: event.category.rawValue)
        let action = event.action
        let outcome = event.outcome.rawValue
        let duration = event.durationMilliseconds.map { "\(Int($0.rounded()))" } ?? "-"
        let metadata = event.logMetadataDescription

        switch event.outcome {
        case .failed:
            logger.error(
                "action=\(action, privacy: .public) outcome=\(outcome, privacy: .public) duration_ms=\(duration, privacy: .public) \(metadata, privacy: .public)"
            )
        case .started:
            logger.debug(
                "action=\(action, privacy: .public) outcome=\(outcome, privacy: .public) duration_ms=\(duration, privacy: .public) \(metadata, privacy: .public)"
            )
        default:
            logger.info(
                "action=\(action, privacy: .public) outcome=\(outcome, privacy: .public) duration_ms=\(duration, privacy: .public) \(metadata, privacy: .public)"
            )
        }
    }
}
