#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation
import PultCore

/// Owns the lock-screen remote Live Activity. Lives in the app process only;
/// intents and the UI both run there, so every update flows through here.
@MainActor
final class RemoteActivityController {
    static let shared = RemoteActivityController()

    private init() {}

    func startOrUpdate(for device: DeviceRecord, state: ConnectionState, message: String? = nil) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = Self.content(for: state, message: message)
        if let activity = Self.activity(for: device.id) {
            await activity.update(content)
            return
        }
        // One remote on the lock screen at a time: switching TVs replaces it.
        for stale in Activity<RemoteSessionAttributes>.activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }
        _ = try? Activity<RemoteSessionAttributes>.request(
            attributes: RemoteSessionAttributes(deviceID: device.id, deviceName: device.name),
            content: content
        )
    }

    func noteOutcome(_ outcome: HeadlessCommandOutcome, device: DeviceRecord, state: ConnectionState) async {
        guard let activity = Self.activity(for: device.id) else { return }
        let message: String? = if case let .failed(text) = outcome { text } else { nil }
        await activity.update(Self.content(for: state, message: message))
    }

    /// Switching TVs replaces the lock-screen remote; if the new TV never
    /// connects, the old TV's remote must still come down rather than
    /// silently driving a different device.
    func endActivities(notMatching deviceID: UUID) async {
        for activity in Activity<RemoteSessionAttributes>.activities where activity.attributes.deviceID != deviceID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func endAll() async {
        for activity in Activity<RemoteSessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private nonisolated static func activity(for deviceID: UUID) -> Activity<RemoteSessionAttributes>? {
        Activity<RemoteSessionAttributes>.activities.first { $0.attributes.deviceID == deviceID }
    }

    private static func content(for state: ConnectionState, message: String?) -> ActivityContent<RemoteSessionAttributes.ContentState> {
        let contentState: RemoteSessionAttributes.ContentState = switch state {
        case .connected: .init(status: .connected, message: message)
        case .connecting: .init(status: .connecting, message: message)
        case .disconnected: .init(status: .failed, message: message ?? "Disconnected")
        case let .failed(text): .init(status: .failed, message: message ?? text)
        }
        // Without presses for a long stretch the remote is probably done;
        // let the system render it stale rather than confidently live.
        return ActivityContent(state: contentState, staleDate: Date(timeIntervalSinceNow: 4 * 60 * 60))
    }
}
#endif
