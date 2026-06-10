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

    private let swipeThreshold: CGFloat = 24

    var body: some View {
        ZStack {
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
        .accessibilityHint("Swipe to move, tap to select")
        .accessibilityActions {
            Button("Up") { send(.up) }
            Button("Down") { send(.down) }
            Button("Left") { send(.left) }
            Button("Right") { send(.right) }
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
        if lifetimeGestureCount < 100 {
            lifetimeGestureCount += 1
        }

        let event = TouchFeedback(id: gestureCount, key: key, location: tapLocation)
        withAnimation(.snappy(duration: 0.12)) {
            feedback = event
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            if feedback?.id == event.id {
                withAnimation(.smooth(duration: 0.3)) {
                    feedback = nil
                }
            }
        }
    }

    // MARK: Feedback layers

    @ViewBuilder
    private var tapPulse: some View {
        if let feedback, feedback.key == .select, let location = feedback.location {
            Circle()
                .fill(.white.opacity(0.22))
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
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(22)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
        }
    }

    private var edgeHints: some View {
        ForEach(TouchpadEdge.allCases, id: \.self) { edge in
            Image(systemName: edge.chevronName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.alignment)
                .padding(18)
        }
    }

    @ViewBuilder
    private var hintLabel: some View {
        if lifetimeGestureCount < 5 {
            Text("Swipe to move · Tap to select")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 48)
                .transition(.opacity)
                .animation(.smooth, value: lifetimeGestureCount)
        }
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
