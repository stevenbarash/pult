import SwiftUI
import PultCore

struct VolumeMuteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(PultDesign.utility)
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
                .font(.caption.weight(.bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(echo.tint)
                .frame(width: 18)
            Text(echo.title)
                .font(PultTypography.captionStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background {
            Capsule()
                .fill(PultDesign.carbonMid.opacity(0.86))
        }
        .overlay {
            Capsule()
                .stroke(echo.tint.opacity(0.36), lineWidth: 1)
        }
        .shadow(color: echo.tint.opacity(0.24), radius: 18, y: 8)
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

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
    }

    private var reconnectButton: some View {
        Button("Reconnect", systemImage: "antenna.radiowaves.left.and.right", action: onRetryConnect)
            .buttonStyle(.bordered)
    }

    private var pairButton: some View {
        Button("Pair Again", systemImage: "link", action: onPair)
            .buttonStyle(.bordered)
    }

    private var manualIPButton: some View {
        Button("Manual IP", systemImage: "network", action: onManualIP)
            .buttonStyle(.bordered)
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

        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .pultContentSurface(in: shape, tint: tint, isProminent: true)
        .accessibilityElement(children: .contain)
    }
}

struct ConnectingBanner: View {
    var message: String

    var body: some View {
        let tint = Color.pultAccent
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(spacing: 10) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .pultContentSurface(in: shape, tint: tint, isProminent: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct RemoteStatusHeader: View {
    let device: DeviceRecord?
    let state: ConnectionState
    let isPaired: Bool
    let validationClaimState: DeviceValidationClaimState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let presentation = RemoteConnectionPresentation(state: state, isPaired: isPaired)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device?.name ?? "No TV Selected")
                    .font(PultTypography.subhead)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(presentation.detail(host: device?.host))
                    .font(PultTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.82)

                if !dynamicTypeSize.isAccessibilitySize {
                    PultStatusChip(
                        title: validationPresentation.title,
                        systemImage: validationPresentation.systemImage,
                        tint: validationPresentation.tint
                    )
                    .frame(maxWidth: 190, alignment: .leading)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(presentation.tint)
                        .frame(width: 8, height: 8)
                    Text(presentation.title)
                        .font(PultTypography.captionStrong)
                        .foregroundStyle(presentation.tint)
                        .lineLimit(1)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    RemoteConnectionMeter(
                        tint: presentation.tint,
                        isActive: presentation.isActive,
                        isAnimating: presentation.isAnimating && !reduceMotion
                    )
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityValue(validationPresentation.title)
        .accessibilityElement(children: .combine)
    }

    private var validationPresentation: RemoteValidationPresentation {
        RemoteValidationPresentation(claimState: validationClaimState)
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

private struct RemoteConnectionMeter: View {
    var tint: Color
    var isActive: Bool
    var isAnimating: Bool

    @State private var pulse = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(isActive || isAnimating ? 0.90 : 0.32))
                    .frame(width: 4, height: CGFloat(9 + (index * 5)))
                    .scaleEffect(x: 1, y: barScale(index), anchor: .bottom)
            }
        }
        .frame(width: 24, height: 26)
        .accessibilityHidden(true)
        .onAppear {
            pulse = isAnimating
        }
        .onChange(of: isAnimating) { _, newValue in
            pulse = newValue
        }
        .animation(
            isAnimating ? .easeInOut(duration: 0.82).repeatForever(autoreverses: true) : .snappy(duration: 0.18),
            value: pulse
        )
    }

    private func barScale(_ index: Int) -> CGFloat {
        guard isAnimating, pulse else { return 1 }
        return max(0.48, 0.72 - (CGFloat(index) * 0.09))
    }
}
