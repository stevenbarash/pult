import SwiftUI
import PultCore

/// Toolbar capsule showing connection state. For an unpaired TV it offers
/// pairing (connecting would be rejected); otherwise tapping it (re)connects
/// when the session is offline, and it is inert while connecting or connected.
struct ConnectionStatusControl: View {
    let state: ConnectionState
    let isPaired: Bool
    let onConnect: () -> Void
    let onPair: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: String {
        if !isPaired {
            return state == .connecting ? "Connecting" : "Pair"
        }
        switch state {
        case .disconnected: return "Connect"
        case .connecting: return "Connecting"
        case .connected: return "Online"
        case .failed: return "Retry"
        }
    }

    private var color: Color {
        if !isPaired, state != .connecting {
            return PultDesign.warning
        }
        switch state {
        case .connected: return PultDesign.connected
        case .connecting: return PultDesign.warning
        case .failed: return PultDesign.danger
        case .disconnected: return .secondary
        }
    }

    private var isActionable: Bool {
        if !isPaired {
            return state != .connecting
        }
        switch state {
        case .disconnected, .failed:
            return true
        case .connecting, .connected:
            return false
        }
    }

    var body: some View {
        Button(action: isPaired ? onConnect : onPair) {
            HStack(spacing: 6) {
                if state == .connecting {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 4)
        }
        .disabled(!isActionable)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: state)
        .accessibilityLabel(isPaired ? "Connection: \(label)" : "Pair with TV")
    }
}
