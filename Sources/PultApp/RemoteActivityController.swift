#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation
import OSLog
import PultCore

private let logger = Logger(subsystem: "app.pult", category: "live-activity")

/// Owns the lock-screen remote Live Activity. Lives in the app process only;
/// intents and the UI both run there, so every update flows through here.
@MainActor
final class RemoteActivityController {
    static let shared = RemoteActivityController()

    private let layoutStore: RemoteActivityLayoutStore

    private init(layoutStore: RemoteActivityLayoutStore = RemoteActivityLayoutStore()) {
        self.layoutStore = layoutStore
    }

    func startOrUpdate(for device: DeviceRecord, state: ConnectionState, message: String? = nil) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.error("startOrUpdate skipped: Live Activities are disabled for the app")
            return
        }
        let content = content(for: state, message: message)
        if let activity = Self.activity(for: device.id) {
            await activity.update(content)
            return
        }
        // One remote on the lock screen at a time: switching TVs replaces it.
        for stale in Activity<RemoteSessionAttributes>.activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }
        do {
            _ = try Activity<RemoteSessionAttributes>.request(
                attributes: RemoteSessionAttributes(deviceID: device.id, deviceName: device.name),
                content: content
            )
        } catch {
            // Diagnosable on device via Console (subsystem app.pult). A
            // request can fail when the system denies a background start —
            // worth knowing rather than silently showing nothing.
            logger.error("Activity.request failed in \(ProcessInfo.processInfo.processName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func noteOutcome(_ outcome: HeadlessCommandOutcome, device: DeviceRecord, state: ConnectionState) async {
        guard let activity = Self.activity(for: device.id) else { return }
        let message: String? = if case let .failed(text) = outcome { text } else { nil }
        await activity.update(content(for: state, message: message))
    }

    func refreshLayout() async {
        let layout = layoutStore.load()
        for activity in Activity<RemoteSessionAttributes>.activities {
            let state = activity.content.state
            await activity.update(Self.content(
                status: state.status,
                message: state.message,
                layout: layout
            ))
        }
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

    private func content(for state: ConnectionState, message: String?) -> ActivityContent<RemoteSessionAttributes.ContentState> {
        let layout = layoutStore.load()
        let contentState: RemoteSessionAttributes.ContentState = switch state {
        case .connected: .init(status: .connected, message: message, layout: layout)
        case .connecting: .init(status: .connecting, message: message, layout: layout)
        case .disconnected: .init(status: .failed, message: message ?? "Disconnected", layout: layout)
        case let .failed(text): .init(status: .failed, message: message ?? text, layout: layout)
        }
        return Self.content(state: contentState)
    }

    private static func content(
        status: RemoteSessionAttributes.Status,
        message: String?,
        layout: RemoteActivityLayout
    ) -> ActivityContent<RemoteSessionAttributes.ContentState> {
        content(state: .init(status: status, message: message, layout: layout))
    }

    private static func content(
        state: RemoteSessionAttributes.ContentState
    ) -> ActivityContent<RemoteSessionAttributes.ContentState> {
        // Without presses for a long stretch the remote is probably done;
        // let the system render it stale rather than confidently live.
        ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 4 * 60 * 60))
    }
}
#endif
