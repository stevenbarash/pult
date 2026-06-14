import SwiftUI
import PultCore

struct VolumeMuteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 56)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mute")
        .accessibilityHint("Toggles mute on the selected TV")
    }
}

struct RemoteCommandEcho: Identifiable {
    let id = UUID()
    var title: String
    var systemImage: String
    var tint: Color
}

struct RemoteCommandEchoView: View {
    let echo: RemoteCommandEcho

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: echo.systemImage)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(echo.tint)
                .frame(width: 16)
            Text(echo.title)
                .font(PultTypography.captionStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule()
                .stroke(echo.tint.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(echo.title)
        .allowsHitTesting(false)
    }
}

struct CommandFailureBanner: View {
    var failure: RemoteCommandFailure
    var onRetryCommand: () -> Void
    var onRetryConnect: () -> Void
    var onPair: () -> Void
    var onManualIP: () -> Void

    var body: some View {
        let tint = PultDesign.danger
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(failure.message)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                    Text(failure.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    recoveryButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        retryButton
                        reconnectButton
                    }
                    HStack(spacing: 8) {
                        pairButton
                        manualIPButton
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .pultContentSurface(in: shape, tint: tint, isProminent: true)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var recoveryButtons: some View {
        retryButton
        reconnectButton
        pairButton
        manualIPButton
    }

    private var retryButton: some View {
        Button("Retry", systemImage: "arrow.clockwise", action: onRetryCommand)
            .buttonStyle(.borderedProminent)
            .tint(PultDesign.danger)
            .frame(minHeight: 44)
    }

    private var reconnectButton: some View {
        Button("Reconnect", systemImage: "antenna.radiowaves.left.and.right", action: onRetryConnect)
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }

    private var pairButton: some View {
        Button("Pair Again", systemImage: "link", action: onPair)
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }

    private var manualIPButton: some View {
        Button("Manual IP", systemImage: "network", action: onManualIP)
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }
}

struct StatusBanner: View {
    var systemImage: String
    var message: String
    var tint: Color
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(message)
                .font(PultTypography.bodySmall)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .tint(tint)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .pultContentSurface(in: shape, tint: tint, isProminent: true)
        .accessibilityElement(children: .contain)
    }
}

struct ConnectingBanner: View {
    var message: String

    var body: some View {
        let tint = PultDesign.accent
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(PultTypography.bodySmall)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .pultContentSurface(in: shape, tint: tint, isProminent: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// A minimal one-line connection status indicator — a quiet dot + label.
/// The TV name lives in the navigation bar; no IP/host, no validation, no
/// signal bars. This intentionally mirrors the calm chrome of Apple's Control
/// Center remote.
struct RemoteStatusHeader: View {
    let device: DeviceRecord?
    let state: ConnectionState
    let isPaired: Bool
    let validationClaimState: DeviceValidationClaimState   // accepted but not rendered here

    var body: some View {
        let presentation = RemoteConnectionPresentation(state: state, isPaired: isPaired)

        HStack(spacing: 5) {
            Circle()
                .fill(presentation.tint)
                .frame(width: 6, height: 6)
            Text(presentation.title)
                .font(PultTypography.captionStrong)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(presentation.title)")
    }
}

private struct RemoteConnectionPresentation {
    var state: ConnectionState
    var isPaired: Bool

    var tint: Color {
        if !isPaired {
            return PultDesign.warning
        }
        switch state {
        case .connected:
            return PultDesign.connected
        case .connecting:
            return PultDesign.warning
        case .failed:
            return PultDesign.danger
        case .disconnected:
            return .pultAccent
        }
    }

    var title: String {
        if !isPaired {
            return "Pair Required"
        }
        switch state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .failed:
            return "Needs Attention"
        case .disconnected:
            return "Disconnected"
        }
    }

    var systemImage: String {
        if !isPaired {
            return "link.badge.plus"
        }
        switch state {
        case .connected:
            return "tv"
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .failed:
            return "wifi.exclamationmark"
        case .disconnected:
            return "powerplug"
        }
    }

    var isActive: Bool {
        isPaired && state == .connected
    }

    var isAnimating: Bool {
        isPaired && state == .connecting
    }

    func detail(host: String?) -> String {
        let location = host ?? "No host"
        if !isPaired {
            return "Pair to control - \(location)"
        }
        switch state {
        case .connected:
            return "Now controlling - \(location)"
        case .connecting:
            return "Tuning in - \(location)"
        case .failed:
            return "Needs attention - \(location)"
        case .disconnected:
            return "Ready to connect - \(location)"
        }
    }
}

