import SwiftUI
import PultCore

enum ControlMode: String, CaseIterable {
    case touchpad
    case dpad

    var label: String {
        switch self {
        case .touchpad: "Touchpad"
        case .dpad: "D-pad"
        }
    }

    var systemImage: String {
        switch self {
        case .touchpad: "hand.draw"
        case .dpad: "dpad"
        }
    }
}

struct RemoteControlSurface: View {
    let connectionState: ConnectionState
    let isPaired: Bool
    let send: (RemoteKey) -> Void
    let onTextEntry: () -> Void
    let onRetryConnect: () -> Void
    let onPair: () -> Void

    @AppStorage("controlMode") private var controlMode: ControlMode = .touchpad
    @State private var keyPressCount = 0
    @Namespace private var glassNamespace

    var body: some View {
        VStack(spacing: 16) {
            banner

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 16) {
                    navigationSurface
                    modeToggle
                }
            }

            GlassEffectContainer(spacing: 10) {
                VStack(spacing: RemoteMetrics.clusterSpacing) {
                    utilityRow
                    mediaRow
                }
            }

            volumeBar
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .animation(.spring(duration: 0.4), value: bannerKind)
        .sensoryFeedback(.impact(weight: .light), trigger: keyPressCount)
    }

    /// All key sends funnel through here so every control shares one
    /// press-haptic trigger instead of each owning a counter.
    private func sendKey(_ key: RemoteKey) {
        keyPressCount += 1
        send(key)
    }

    // MARK: Status banner

    private enum BannerKind: Equatable {
        case failure(String)
        case unpaired
    }

    private var bannerKind: BannerKind? {
        // Unpaired wins: until the TV is paired, connecting is guaranteed to
        // fail, so "Pair" is the only actionable advice.
        if !isPaired {
            return .unpaired
        }
        if case let .failed(message) = connectionState {
            return .failure(message)
        }
        return nil
    }

    @ViewBuilder
    private var banner: some View {
        switch bannerKind {
        case let .failure(message):
            StatusBanner(
                systemImage: "wifi.exclamationmark",
                message: message,
                tint: .red,
                actionTitle: "Retry",
                action: onRetryConnect
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        case .unpaired:
            StatusBanner(
                systemImage: "link.badge.plus",
                message: "This TV isn't paired yet. Pair once to start controlling it.",
                tint: .orange,
                actionTitle: "Pair",
                action: onPair
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        case nil:
            EmptyView()
        }
    }

    // MARK: Navigation surface

    @ViewBuilder
    private var navigationSurface: some View {
        Group {
            switch controlMode {
            case .touchpad:
                TouchpadView(send: sendKey)
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: RemoteMetrics.surfaceCornerRadius)
                    )
                    .glassEffectID("navigation", in: glassNamespace)
            case .dpad:
                DPadRing(send: sendKey, namespace: glassNamespace)
            }
        }
        .frame(maxWidth: RemoteMetrics.maxControlWidth, maxHeight: .infinity)
        .frame(minHeight: 240)
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(ControlMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.smooth(duration: 0.45)) {
                        controlMode = mode
                    }
                } label: {
                    Label(mode.label, systemImage: mode.systemImage)
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.iconOnly)
                        .frame(width: 52, height: 30)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(controlMode == mode ? Color.primary : Color.secondary)
                .background {
                    if controlMode == mode {
                        Capsule()
                            .fill(.white.opacity(0.16))
                            .matchedGeometryEffect(id: "modeSelection", in: glassNamespace)
                    }
                }
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(controlMode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: Key clusters

    private var utilityRow: some View {
        HStack(spacing: RemoteMetrics.clusterSpacing) {
            RemoteCircleButton(systemImage: "arrow.uturn.backward", label: "Back") { sendKey(.back) }
            RemoteCircleButton(systemImage: "house", label: "Home") { sendKey(.home) }
            RemoteCircleButton(systemImage: "keyboard", label: "Text input", action: onTextEntry)
            RemoteCircleButton(systemImage: "power", label: "Power", iconColor: .red) { sendKey(.power) }
        }
    }

    private var mediaRow: some View {
        HStack(spacing: RemoteMetrics.clusterSpacing) {
            RemoteCircleButton(systemImage: "backward.fill", label: "Rewind") { sendKey(.rewind) }
            RemoteCircleButton(systemImage: "playpause.fill", label: "Play or pause") { sendKey(.playPause) }
            RemoteCircleButton(systemImage: "forward.fill", label: "Fast forward") { sendKey(.fastForward) }
        }
    }

    private var volumeBar: some View {
        HStack(spacing: 0) {
            HoldRepeatKeyZone(key: .volumeDown, systemImage: "speaker.minus.fill", send: sendKey)
            VolumeMuteButton { sendKey(.mute) }
            HoldRepeatKeyZone(key: .volumeUp, systemImage: "speaker.plus.fill", send: sendKey)
        }
        .frame(maxWidth: RemoteMetrics.maxControlWidth)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

private struct VolumeMuteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 72, height: 56)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mute")
    }
}

private struct StatusBanner: View {
    var systemImage: String
    var message: String
    var tint: Color
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.footnote)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .tint(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(tint.opacity(0.18)), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - D-pad

private struct DPadRing: View {
    let send: (RemoteKey) -> Void
    let namespace: Namespace.ID

    private static let directions: [DPadDirection] = [
        DPadDirection(key: .up, angle: .degrees(-90), systemImage: "chevron.up"),
        DPadDirection(key: .right, angle: .degrees(0), systemImage: "chevron.right"),
        DPadDirection(key: .down, angle: .degrees(90), systemImage: "chevron.down"),
        DPadDirection(key: .left, angle: .degrees(180), systemImage: "chevron.left")
    ]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                ForEach(Self.directions, id: \.key) { direction in
                    DPadWedgeButton(direction: direction, side: side, send: send)
                }
                DPadCenterButton(side: side, namespace: namespace, send: send)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct DPadCenterButton: View {
    let side: CGFloat
    let namespace: Namespace.ID
    let send: (RemoteKey) -> Void

    var body: some View {
        Button {
            send(.select)
        } label: {
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: side * 0.36, height: side * 0.36)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.accentColor.opacity(0.45)).interactive(), in: .circle)
        .glassEffectID("navigation", in: namespace)
        .accessibilityLabel("Select")
    }
}

private struct DPadDirection: Hashable {
    var key: RemoteKey
    var angle: Angle
    var systemImage: String
}

private struct DPadWedgeButton: View {
    let direction: DPadDirection
    let side: CGFloat
    let send: (RemoteKey) -> Void

    private var wedge: DPadWedge {
        DPadWedge(centerAngle: direction.angle)
    }

    var body: some View {
        Button {
            send(direction.key)
        } label: {
            Color.clear
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: direction.systemImage)
                        .font(.system(size: side * 0.07 + 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .offset(iconOffset)
                }
                .contentShape(wedge)
        }
        .buttonStyle(GlassShapeButtonStyle(shape: wedge))
        .accessibilityLabel(direction.key.accessibilityLabel)
    }

    private var iconOffset: CGSize {
        let radius = side * 0.5 * (1 + DPadWedge.innerRadiusFraction) / 2
        let radians = direction.angle.radians
        return CGSize(width: radius * cos(radians), height: radius * sin(radians))
    }
}

/// An annular sector pointing at `centerAngle`, used for d-pad direction keys.
private struct DPadWedge: Shape {
    static let innerRadiusFraction: CGFloat = 0.42

    var centerAngle: Angle
    var sweep: Angle = .degrees(80)

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * Self.innerRadiusFraction
        let start = Angle(radians: centerAngle.radians - sweep.radians / 2)
        let end = Angle(radians: centerAngle.radians + sweep.radians / 2)

        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
