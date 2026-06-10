import Foundation

public enum RemoteKey: String, CaseIterable, Sendable, Identifiable {
    case up
    case down
    case left
    case right
    case select
    case back
    case home
    case power
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case rewind
    case fastForward

    public var id: String { rawValue }

    public var androidKeyCode: Int {
        switch self {
        case .up: 19
        case .down: 20
        case .left: 21
        case .right: 22
        case .select: 23
        case .back: 4
        case .home: 3
        case .power: 26
        case .volumeUp: 24
        case .volumeDown: 25
        case .mute: 164
        case .playPause: 85
        case .rewind: 89
        case .fastForward: 90
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .power: "Power"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        case .playPause: "Play or pause"
        case .rewind: "Rewind"
        case .fastForward: "Fast forward"
        }
    }
}

/// Raw values match the `remote.RemoteDirection` enum from
/// Docs/Protocol/remotemessage.proto.
public enum KeyAction: UInt8, Sendable {
    case press = 1
    case release = 2
    case tap = 3
}
