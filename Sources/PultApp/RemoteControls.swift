import SwiftUI
import PultCore

extension Color {
    /// Brand accent, applied at the app root so sheets inherit it too.
    static let pultAccent = Color(red: 0.99, green: 0.66, blue: 0.32)
}

enum RemoteMetrics {
    static let keySize: CGFloat = 58
    static let clusterSpacing: CGFloat = 12
    static let surfaceCornerRadius: CGFloat = 34
    static let maxControlWidth: CGFloat = 430
}

/// A circular Liquid Glass remote key. Press haptics come from the surface's
/// shared key-press feedback, not from the button itself.
struct RemoteCircleButton: View {
    var systemImage: String
    var label: String
    var iconColor: Color?
    var size: CGFloat = RemoteMetrics.keySize
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor ?? .primary)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(GlassShapeButtonStyle(shape: .circle))
        .accessibilityLabel(label)
    }
}

/// Applies interactive Liquid Glass in an arbitrary shape with a press scale.
struct GlassShapeButtonStyle<S: Shape>: ButtonStyle {
    var shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.regular.interactive(), in: shape)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

/// A key zone that fires once on touch-down and auto-repeats while held.
/// Used for volume keys, where holding should keep adjusting. The repeater
/// is tied to the view's lifetime and the scene staying active, so a hold
/// interrupted by a call, backgrounding, or view removal cannot run away.
struct HoldRepeatKeyZone: View {
    let key: RemoteKey
    var systemImage: String
    let send: (RemoteKey) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var isHolding = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(.rect)
            .scaleEffect(isHolding ? 0.86 : 1)
            .opacity(isHolding ? 0.6 : 1)
            .animation(.snappy(duration: 0.16), value: isHolding)
            .gesture(holdGesture)
            .onDisappear(perform: stopHolding)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    stopHolding()
                }
            }
            .accessibilityLabel(key.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { send(key) }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isHolding else { return }
                isHolding = true
                send(key)
                repeater = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(420))
                        while true {
                            try Task.checkCancellation()
                            send(key)
                            try await Task.sleep(for: .milliseconds(180))
                        }
                    } catch {}
                }
            }
            .onEnded { _ in
                stopHolding()
            }
    }

    private func stopHolding() {
        isHolding = false
        repeater?.cancel()
        repeater = nil
    }
}

/// The cinematic backdrop behind the remote surface.
struct RemoteBackground: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.45], [0.55, 0.55], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.09),
                Color(red: 0.07, green: 0.10, blue: 0.14),
                Color(red: 0.05, green: 0.07, blue: 0.10),
                Color(red: 0.08, green: 0.11, blue: 0.13),
                Color(red: 0.10, green: 0.14, blue: 0.17),
                Color(red: 0.11, green: 0.10, blue: 0.09),
                Color(red: 0.04, green: 0.05, blue: 0.07),
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color(red: 0.07, green: 0.06, blue: 0.06)
            ]
        )
        .ignoresSafeArea()
    }
}
