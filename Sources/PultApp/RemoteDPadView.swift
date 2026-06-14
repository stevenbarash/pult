import Foundation
import SwiftUI
import PultCore

struct DPadRing: View {
    let isActive: Bool
    let send: (RemoteKey) -> Void
    let sendKeyAction: (RemoteKey, KeyAction) -> Void

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
                DPadDial(side: side)
                ForEach(Self.directions, id: \.key) { direction in
                    DPadWedgeButton(direction: direction, side: side, send: send)
                }
                DPadCenterButton(
                    side: side,
                    isActive: isActive,
                    send: send,
                    sendKeyAction: sendKeyAction
                )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct DPadDial: View {
    let side: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Material base + white overlay so the d-pad ring reads as
            // clearly lighter than the near-black canvas — consistent
            // lightness with the touchpad hero surface.
            // Reduce-transparency fallback: opaque brighter fill.
            if reduceTransparency {
                Circle()
                    .fill(Color.white.opacity(0.18))
            } else {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                    Circle()
                        .fill(Color.white.opacity(0.12))
                }
            }
            Circle()
                .stroke(PultDesign.hairlineStrong, lineWidth: 1)
            // Subtle inner guide ring to orient the eye toward the center.
            Circle()
                .stroke(PultDesign.hairline, lineWidth: 1)
                .frame(width: side * 0.70, height: side * 0.70)
        }
        .padding(side * 0.03)
        .accessibilityHidden(true)
    }
}

private struct DPadCenterButton: View {
    let side: CGFloat
    let isActive: Bool
    let send: (RemoteKey) -> Void
    let sendKeyAction: (RemoteKey, KeyAction) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    @State private var longPressDidStart = false
    @State private var longPressTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Visible center disc — slightly raised surface so it reads
            // clearly as a distinct button, not a decoration.
            Circle()
                .fill(PultDesign.surfaceStrong)
                .frame(width: side * 0.36, height: side * 0.36)
            Circle()
                .stroke(PultDesign.hairlineStrong, lineWidth: 1)
                .frame(width: side * 0.36, height: side * 0.36)
        }
        .frame(width: side * 0.36, height: side * 0.36)
        .contentShape(.circle)
        .scaleEffect(isPressed ? 0.90 : 1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: isPressed)
        .gesture(pressGesture)
        .onDisappear(perform: cancelInteraction)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                cancelInteraction()
            }
        }
        .onChange(of: isActive) { _, isActive in
            if !isActive {
                cancelInteraction()
            }
        }
        .glassEffect(.regular.tint(PultDesign.accent.opacity(0.18)).interactive(), in: .circle)
        .pultGlassFallback(in: Circle(), tint: PultDesign.accent, isProminent: true)
        .accessibilityLabel("Select")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to select. Touch and hold for OK long press.")
        .accessibilityAction { send(.select) }
        .accessibilityAction(named: "Long press") {
            performAccessibilityLongPress()
        }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                startInteractionIfNeeded()
            }
            .onEnded { _ in
                finishInteraction()
            }
    }

    private func startInteractionIfNeeded() {
        guard !isPressed else { return }
        isPressed = true
        longPressDidStart = false
        longPressTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(450))
                guard isPressed, !Task.isCancelled else { return }
                longPressDidStart = true
                sendKeyAction(.select, .press)
            } catch {}
        }
    }

    private func finishInteraction() {
        let didStartLongPress = longPressDidStart
        resetInteraction()
        if didStartLongPress {
            sendKeyAction(.select, .release)
        } else {
            send(.select)
        }
    }

    private func cancelInteraction() {
        let didStartLongPress = longPressDidStart
        resetInteraction()
        if didStartLongPress {
            sendKeyAction(.select, .release)
        }
    }

    private func resetInteraction() {
        isPressed = false
        longPressDidStart = false
        longPressTask?.cancel()
        longPressTask = nil
    }

    private func performAccessibilityLongPress() {
        Task { @MainActor in
            sendKeyAction(.select, .press)
            try? await Task.sleep(for: .milliseconds(500))
            sendKeyAction(.select, .release)
        }
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
                        .foregroundStyle(.primary)
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
