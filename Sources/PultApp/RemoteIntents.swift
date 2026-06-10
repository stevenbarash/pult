import AppIntents
import Foundation
import PultCore

#if os(iOS)
/// LiveActivityIntent makes the system run perform() in the app's own
/// process — without unlocking the device and without foregrounding the app.
/// That is what lets lock-screen buttons reuse the live mTLS session.
typealias HeadlessRemoteIntent = LiveActivityIntent
#else
typealias HeadlessRemoteIntent = AppIntent
#endif

/// Process-wide model shared by the SwiftUI scene and every intent. Compiled
/// into the widget extension too (the types must exist there), but only the
/// app process ever executes perform().
@MainActor
enum SharedRemote {
    static let model = RemoteControlModel()
}

enum RemoteKeyOption: String, AppEnum {
    case up, down, left, right, select
    case back, home, power
    case volumeUp, volumeDown, mute
    case playPause, rewind, fastForward

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Remote Command")

    static let caseDisplayRepresentations: [RemoteKeyOption: DisplayRepresentation] = [
        .up: "Up", .down: "Down", .left: "Left", .right: "Right", .select: "Select",
        .back: "Back", .home: "Home", .power: "Power",
        .volumeUp: "Volume Up", .volumeDown: "Volume Down", .mute: "Mute",
        .playPause: "Play or Pause", .rewind: "Rewind", .fastForward: "Fast Forward"
    ]

    var remoteKey: RemoteKey {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .select: .select
        case .back: .back
        case .home: .home
        case .power: .power
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .mute: .mute
        case .playPause: .playPause
        case .rewind: .rewind
        case .fastForward: .fastForward
        }
    }

    var displayTitle: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .power: "Power"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .playPause: "Play or Pause"
        case .rewind: "Rewind"
        case .fastForward: "Fast Forward"
        }
    }

    var systemImage: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .select: "smallcircle.filled.circle"
        case .back: "arrow.uturn.backward"
        case .home: "house"
        case .power: "power"
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .mute: "speaker.slash"
        case .playPause: "playpause"
        case .rewind: "backward"
        case .fastForward: "forward"
        }
    }
}

struct OpenRemoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Remote"
    static let description = IntentDescription("Open Pult to the remote controls.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SendRemoteKeyIntent: HeadlessRemoteIntent {
    static let title: LocalizedStringResource = "Send Remote Command"
    static let description = IntentDescription("Send a command to the selected Google TV without opening Pult.")
    static let openAppWhenRun = false

    @Parameter(title: "Command")
    var command: RemoteKeyOption

    init() {}

    init(command: RemoteKeyOption) {
        self.command = command
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = SharedRemote.model
        let outcome = await model.performHeadlessCommand(command.remoteKey)
        #if canImport(ActivityKit) && os(iOS)
        if let device = model.selectedDevice {
            await RemoteActivityController.shared.noteOutcome(
                outcome, device: device, state: model.session.connectionState
            )
        }
        #endif
        switch outcome {
        case .sent:
            return .result(dialog: IntentDialog(stringLiteral: "Sent \(command.displayTitle)."))
        case let .failed(message):
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
    }
}

struct StartRemoteSessionIntent: HeadlessRemoteIntent {
    static let title: LocalizedStringResource = "Show TV Remote"
    static let description = IntentDescription("Connect to the selected Google TV and put the remote on the Lock Screen.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = SharedRemote.model
        guard let device = model.selectedDevice, device.isPaired else {
            return .result(dialog: "Open Pult and pair a TV first.")
        }
        await model.ensureConnected()
        #if canImport(ActivityKit) && os(iOS)
        await RemoteActivityController.shared.startOrUpdate(
            for: device, state: model.session.connectionState
        )
        #endif
        if case let .failed(message) = model.session.connectionState {
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
        return .result(dialog: IntentDialog(stringLiteral: "Remote ready for \(device.name)."))
    }
}

struct EndRemoteSessionIntent: HeadlessRemoteIntent {
    static let title: LocalizedStringResource = "Hide TV Remote"
    static let description = IntentDescription("Disconnect and remove the remote from the Lock Screen.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedRemote.model.session.disconnect()
        #if canImport(ActivityKit) && os(iOS)
        await RemoteActivityController.shared.endAll()
        #endif
        return .result()
    }
}

struct PultShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRemoteIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open remote in \(.applicationName)"
            ],
            shortTitle: "Open Remote",
            systemImageName: "av.remote"
        )

        AppShortcut(
            intent: StartRemoteSessionIntent(),
            phrases: [
                "Show my TV remote with \(.applicationName)",
                "\(.applicationName) remote"
            ],
            shortTitle: "TV Remote",
            systemImageName: "av.remote"
        )

        AppShortcut(
            intent: SendRemoteKeyIntent(),
            phrases: [
                "\(\.$command) the TV with \(.applicationName)",
                "Send TV command with \(.applicationName)"
            ],
            shortTitle: "TV Command",
            systemImageName: "tv"
        )
    }
}
