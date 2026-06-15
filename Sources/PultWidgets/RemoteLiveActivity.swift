import ActivityKit
import AppIntents
import PultCore
import SwiftUI
import WidgetKit

struct RemoteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RemoteSessionAttributes.self) { context in
            LockScreenRemoteView(context: context)
                // Near-black #0A0A09 at 0.85 opacity — matches the app canvas
                // while still letting the Lock Screen blurred glass show through.
                .activityBackgroundTint(Color(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 9.0 / 255.0).opacity(0.85))
                .activitySystemActionForegroundColor(Color(red: 250.0 / 255.0, green: 250.0 / 255.0, blue: 247.0 / 255.0))
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
                    DynamicIslandCommandRow(layout: context.state.layout)
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
/// grid run nearly the full height. Promoted rows can include 48 pt hit
/// cells, so the medium layouts are budgeted around 150-152 pt with 4 pt
/// vertical padding per side, leaving a little room under the cap. The
/// status strip, power, and dismiss live in a slim flexible column between
/// them, and width soaks up the device differences: the device name truncates
/// first on compact phones.
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
        switch context.state.layout {
        case .hybrid:
            HybridRemoteLayout(context: context)
        case .media:
            MediaRemoteLayout(context: context)
        }
    }
}

private struct DynamicIslandCommandRow: View {
    let layout: RemoteActivityLayout

    private var commands: [RemoteKeyOption] {
        switch layout {
        case .hybrid:
            [.back, .volumeDown, .playPause, .mute, .volumeUp, .home]
        case .media:
            [.rewind, .volumeDown, .playPause, .mute, .volumeUp, .fastForward]
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(commands, id: \.rawValue) { command in
                KeyButton(
                    command: command,
                    size: command == .playPause || command == .mute ? 38 : 32
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HybridRemoteLayout: View {
    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            DPadCluster()

            VStack(spacing: 6) {
                RemoteActivityStatusColumn(
                    context: context,
                    showsMessage: context.state.status == .failed,
                    compact: true
                )
                KeyButton(command: .power, size: 30)
                EndActivityButton()
            }
            .frame(width: 48)

            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    KeyButton(command: .volumeDown, size: 36)
                    KeyButton(command: .playPause, size: 40)
                    KeyButton(command: .volumeUp, size: 36)
                }
                GridRow {
                    KeyButton(command: .back, size: 30)
                    KeyButton(command: .mute, size: 40)
                    KeyButton(command: .home, size: 30)
                }
                GridRow {
                    KeyButton(command: .rewind, size: 28)
                    EmptyCell()
                    KeyButton(command: .fastForward, size: 28)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
    }
}

private struct MediaRemoteLayout: View {
    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(spacing: 6) {
                RemoteActivityStatusColumn(
                    context: context,
                    showsMessage: context.state.status == .failed,
                    compact: true
                )
                HStack(spacing: 6) {
                    KeyButton(command: .power, size: 30)
                    EndActivityButton()
                }
            }
            .frame(maxWidth: .infinity)

            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    KeyButton(command: .rewind, size: 30)
                    KeyButton(command: .playPause, size: 40)
                    KeyButton(command: .fastForward, size: 30)
                }
                GridRow {
                    KeyButton(command: .volumeDown, size: 38)
                    KeyButton(command: .mute, size: 40)
                    KeyButton(command: .volumeUp, size: 38)
                }
                GridRow {
                    KeyButton(command: .back, size: 30)
                    KeyButton(command: .select, size: 30)
                    KeyButton(command: .home, size: 30)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
    }
}

private struct RemoteActivityStatusColumn: View {
    let context: ActivityViewContext<RemoteSessionAttributes>
    var showsMessage = true
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 3 : 4) {
            Text(context.attributes.deviceName)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.7 : 1)
            StatusBadge(status: context.state.status, isStale: context.isStale, compact: compact)
            if showsMessage, let message = context.state.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(compact ? 0.7 : 0.78)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct EndActivityButton: View {
    var body: some View {
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
            if compact {
                // Non-color differentiator: SF Symbol varies by state so
                // low-vision users can distinguish without relying on hue.
                Image(systemName: status.statusSymbol(isStale: isStale))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(status.tint(isStale: isStale))
            } else {
                StatusDot(status: status, isStale: isStale)
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
    /// Per-state SF Symbol for compact contexts where color alone is
    /// insufficient (lock-screen small Live Activity).
    /// connected  → checkmark.circle.fill  (filled check — clearly "good")
    /// connecting → ellipsis.circle        (progress dots — "in progress")
    /// failed     → exclamationmark.circle.fill (alert — "needs attention")
    func statusSymbol(isStale: Bool = false) -> String {
        if isStale { return "clock.badge.exclamationmark" }
        switch self {
        case .connected:  return "checkmark.circle.fill"
        case .connecting: return "ellipsis.circle"
        case .failed:     return "exclamationmark.circle.fill"
        }
    }

    func tint(isStale: Bool = false) -> Color {
        if isStale {
            return .secondary
        }
        switch self {
        case .connected: return .pultWidgetConnected
        case .connecting: return .pultWidgetWarning
        case .failed: return .pultWidgetDanger
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
