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
                            .widgetAccentedRenderingMode(.fullColor)
                        Text(context.attributes.deviceName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusBadge(status: context.state.status, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.center, priority: 1) {
                    KeyButton(command: .playPause, size: 34)
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
                    .widgetAccentedRenderingMode(.fullColor)
            } compactTrailing: {
                StatusDot(status: context.state.status, isStale: context.isStale)
            } minimal: {
                Image(systemName: "tv")
                    .widgetAccentedRenderingMode(.fullColor)
            }
            .keylineTint(context.state.status.tint())
            .contentMargins(.horizontal, 8, for: .expanded)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

/// The lock-screen mini-remote. The 160 pt system cap is the scarce
/// dimension, so there is no full-width header row: the d-pad and command
/// grid run the full height (3 rows × 44 pt hit cells = 132 + 12 padding
/// ≈ 144 pt) and the status strip, power, and dismiss live in a slim
/// flexible column between them. Width soaks up the device differences —
/// the device name truncates first on compact phones.
private struct LockScreenRemoteView: View {
    @Environment(\.activityFamily) private var activityFamily

    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        switch activityFamily {
        case .small:
            SupplementalSmallRemoteView(context: context)
        case .medium:
            SupplementalMediumRemoteView(context: context)
        @unknown default:
            SupplementalMediumRemoteView(context: context)
        }
    }
}

private struct SupplementalSmallRemoteView: View {
    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "tv")
                    .widgetAccentedRenderingMode(.fullColor)
                Text(context.attributes.deviceName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusBadge(status: context.state.status, isStale: context.isStale, compact: true)
            }
            HStack(spacing: 4) {
                KeyButton(command: .back, size: 30)
                KeyButton(command: .playPause, size: 34)
                KeyButton(command: .home, size: 30)
                KeyButton(command: .mute, size: 30)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
    }
}

private struct SupplementalMediumRemoteView: View {
    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            DPadCluster()
            VStack(spacing: 10) {
                VStack(spacing: 4) {
                    Text(context.attributes.deviceName)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                    StatusBadge(status: context.state.status, isStale: context.isStale)
                }
                if let message = context.state.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
                KeyButton(command: .power, size: 30)
                Button(intent: EndRemoteSessionIntent()) {
                    Image(systemName: "xmark")
                        .widgetAccentedRenderingMode(.fullColor)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide remote")
                .accessibilityHint("Disconnects and removes the Lock Screen remote")
            }
            .frame(maxWidth: .infinity)
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
                GridRow {
                    KeyButton(command: .rewind)
                    EmptyCell()
                    KeyButton(command: .fastForward)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
        Color.clear.frame(width: 44, height: 44)
    }
}

private struct KeyButton: View {
    let command: RemoteKeyOption
    var size: CGFloat = 36

    var body: some View {
        let hitSize = max(size + 8, 44)

        Button(intent: SendRemoteKeyIntent(command: command)) {
            Image(systemName: command.systemImage)
                .widgetAccentedRenderingMode(.fullColor)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: size, height: size)
                .background(.white.opacity(0.12), in: .circle)
                .frame(width: hitSize, height: hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(command.displayTitle))
        .accessibilityHint("Sends this command to the current TV")
    }
}

private struct StatusBadge: View {
    let status: RemoteSessionAttributes.Status
    var isStale = false
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            StatusDot(status: status, isStale: isStale)
            if !compact {
                Text(status.displayText(isStale: isStale))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, compact ? 0 : 6)
        .padding(.vertical, compact ? 0 : 3)
        .background {
            if !compact {
                Capsule().fill(status.tint(isStale: isStale).opacity(0.18))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(status.accessibilityText(isStale: isStale)))
    }
}

private struct StatusDot: View {
    let status: RemoteSessionAttributes.Status
    var isStale = false

    private var color: Color {
        status.tint(isStale: isStale)
    }

    private var label: String {
        status.accessibilityText(isStale: isStale)
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(Text(label))
    }
}

private extension RemoteSessionAttributes.Status {
    func tint(isStale: Bool = false) -> Color {
        if isStale {
            return .secondary
        }
        switch self {
        case .connected: return .green
        case .connecting: return .pultWidgetWarning
        case .failed: return .red
        }
    }

    func displayText(isStale: Bool) -> String {
        if isStale {
            return "Update delayed"
        }
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .failed: return "Needs attention"
        }
    }

    func accessibilityText(isStale: Bool) -> String {
        if isStale {
            return "Remote update delayed"
        }
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .failed: return "Connection needs attention"
        }
    }
}
