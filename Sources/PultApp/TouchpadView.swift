import SwiftUI
import PultCore

/// A swipe surface in the style of the Apple TV remote: directional swipes
/// send d-pad keys, a tap sends select. Visual and haptic feedback echo
/// each recognized gesture.
struct TouchpadView: View {
    let send: (RemoteKey) -> Void

    @State private var feedback: TouchFeedback?
    @State private var gestureCount = 0
    @AppStorage("touchpadGestureCount") private var lifetimeGestureCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let swipeThreshold: CGFloat = 24

    var body: some View {
        ZStack {
            touchpadTexture
            edgeHints
            tapPulse
            swipeFlash
            hintLabel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect(cornerRadius: RemoteMetrics.surfaceCornerRadius))
        .gesture(touchGesture)
        .accessibilityElement()
        .accessibilityLabel("Touchpad")
        .accessibilityValue(feedback.map { "Last command: \($0.key.accessibilityLabel)" } ?? "Ready")
        .accessibilityHint("Swipe to move and tap to select. VoiceOver users can choose remote commands from Actions.")
        .accessibilityInputLabels(["Touchpad", "Remote touchpad", "TV touchpad"])
        .accessibilityActions {
            Button("Move Up") { send(.up) }
            Button("Move Down") { send(.down) }
            Button("Move Left") { send(.left) }
            Button("Move Right") { send(.right) }
            Button("Select") { send(.select) }
        }
    }

    // MARK: Gesture

    private var touchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if hypot(dx, dy) < swipeThreshold {
                    recognize(.select, tapLocation: value.startLocation)
                } else if abs(dx) > abs(dy) {
                    recognize(dx > 0 ? .right : .left, tapLocation: nil)
                } else {
                    recognize(dy > 0 ? .down : .up, tapLocation: nil)
                }
            }
    }

    private func recognize(_ key: RemoteKey, tapLocation: CGPoint?) {
        send(key)
        gestureCount += 1
        if lifetimeGestureCount < 5 {
            lifetimeGestureCount += 1
        }

        let event = TouchFeedback(id: gestureCount, key: key, location: tapLocation)
        updateFeedback(event, animation: .snappy(duration: 0.12))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            if feedback?.id == event.id {
                updateFeedback(nil, animation: .smooth(duration: 0.3))
            }
        }
    }

    private func updateFeedback(_ newFeedback: TouchFeedback?, animation: Animation?) {
        if reduceMotion {
            feedback = newFeedback
        } else {
            withAnimation(animation) {
                feedback = newFeedback
            }
        }
    }

    // MARK: Feedback layers

    @ViewBuilder
    private var tapPulse: some View {
        if let feedback, feedback.key == .select, let location = feedback.location {
            Circle()
                .fill(PultDesign.accent.opacity(colorSchemeContrast == .increased ? 0.42 : 0.26))
                .frame(width: 56, height: 56)
                .position(location)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var swipeFlash: some View {
        if let feedback, let alignment = feedback.key.edgeAlignment {
            Image(systemName: feedback.key.chevronName)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(PultDesign.accent.opacity(colorSchemeContrast == .increased ? 0.96 : 0.78))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(22)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
        }
    }

    private var touchpadTexture: some View {
        ZStack {
            // White overlay reinforces the lightness set by the material
            // backing in touchpadSurface — the inner layer cooperates with
            // the outer background to produce the visible lift.
            RoundedRectangle(cornerRadius: RemoteMetrics.surfaceCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
            // Single inner accent ring to signal the interactive zone.
            RoundedRectangle(cornerRadius: RemoteMetrics.surfaceCornerRadius - 10, style: .continuous)
                .stroke(PultDesign.accent.opacity(0.14), lineWidth: 1)
                .padding(20)
        }
        .accessibilityHidden(true)
    }

    private var edgeHints: some View {
        ForEach(TouchpadEdge.allCases, id: \.self) { edge in
            Image(systemName: edge.chevronName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary.opacity(edgeHintOpacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.alignment)
                .padding(16)
        }
    }

    @ViewBuilder
    private var hintLabel: some View {
        if lifetimeGestureCount < 5 {
            Text("Swipe to move · Tap to select")
                .font(PultTypography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 24)
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 30 : 48)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .smooth, value: lifetimeGestureCount)
        }
    }

    private var edgeHintOpacity: Double {
        colorSchemeContrast == .increased ? 0.48 : 0.22
    }
}

private struct TouchFeedback {
    var id: Int
    var key: RemoteKey
    var location: CGPoint?
}

private enum TouchpadEdge: CaseIterable {
    case up, down, left, right

    var alignment: Alignment {
        switch self {
        case .up: .top
        case .down: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    var chevronName: String {
        switch self {
        case .up: "chevron.compact.up"
        case .down: "chevron.compact.down"
        case .left: "chevron.compact.left"
        case .right: "chevron.compact.right"
        }
    }
}

private extension RemoteKey {
    var edgeAlignment: Alignment? {
        switch self {
        case .up: .top
        case .down: .bottom
        case .left: .leading
        case .right: .trailing
        default: nil
        }
    }

    var chevronName: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        default: "chevron.right"
        }
    }
}
