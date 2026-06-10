import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RemoteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RemoteSessionAttributes.self) { context in
            LockScreenRemoteView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "tv")
                        Text(context.attributes.deviceName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusDot(status: context.state.status)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 18) {
                        KeyButton(command: .back)
                        KeyButton(command: .rewind)
                        KeyButton(command: .playPause)
                        KeyButton(command: .fastForward)
                        KeyButton(command: .mute)
                    }
                    .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: "tv")
            } compactTrailing: {
                StatusDot(status: context.state.status)
            } minimal: {
                Image(systemName: "tv")
            }
        }
    }
}

/// The lock-screen mini-remote. Lives inside the ~162 pt Live Activity
/// budget: one status row (~26 pt), spacing 8, d-pad 3×36 + 0 spacing = 108,
/// plus vertical padding 20 → total ≈ 162 pt.
private struct LockScreenRemoteView: View {
    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(status: context.state.status)
                Text(context.attributes.deviceName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let message = context.state.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                KeyButton(command: .power, size: 26)
                Color.clear.frame(width: 8, height: 1)
                Button(intent: EndRemoteSessionIntent()) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.12), in: .circle)
                        .padding(4)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide remote")
            }
            HStack(alignment: .center, spacing: 18) {
                DPadCluster()
                Spacer(minLength: 0)
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        KeyButton(command: .back)
                        KeyButton(command: .home)
                        KeyButton(command: .playPause)
                    }
                    GridRow {
                        KeyButton(command: .volumeDown)
                        KeyButton(command: .mute)
                        KeyButton(command: .volumeUp)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
    }
}

private struct DPadCluster: View {
    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                EmptyCell()
                KeyButton(command: .up)
                EmptyCell()
            }
            GridRow {
                KeyButton(command: .left)
                KeyButton(command: .select)
                KeyButton(command: .right)
            }
            GridRow {
                EmptyCell()
                KeyButton(command: .down)
                EmptyCell()
            }
        }
    }
}

private struct EmptyCell: View {
    var body: some View {
        Color.clear.frame(width: 36, height: 36)
    }
}

private struct KeyButton: View {
    let command: RemoteKeyOption
    var size: CGFloat = 28

    var body: some View {
        Button(intent: SendRemoteKeyIntent(command: command)) {
            Image(systemName: command.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: size, height: size)
                .background(.white.opacity(0.12), in: .circle)
                .padding(4)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(command.displayTitle))
    }
}

private struct StatusDot: View {
    let status: RemoteSessionAttributes.Status

    private var color: Color {
        switch status {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        }
    }

    private var label: String {
        switch status {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .failed: "Connection failed"
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(Text(label))
    }
}
