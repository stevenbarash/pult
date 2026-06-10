import AppIntents
import PultCore

enum IntentRemoteCommand: String, AppEnum {
    case power
    case home
    case playPause
    case volumeUp
    case volumeDown

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Remote Command")

    static let caseDisplayRepresentations: [IntentRemoteCommand: DisplayRepresentation] = [
        .power: "Power",
        .home: "Home",
        .playPause: "Play or Pause",
        .volumeUp: "Volume Up",
        .volumeDown: "Volume Down"
    ]

    var remoteKey: RemoteKey {
        switch self {
        case .power: .power
        case .home: .home
        case .playPause: .playPause
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
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

struct SendRemoteCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Remote Command"
    static let description = IntentDescription("Send a quick command to the selected Google TV.")
    static let openAppWhenRun = true

    @Parameter(title: "Command")
    var command: IntentRemoteCommand

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedIntentCommandQueue.shared.enqueue(command.remoteKey)
        return .result(dialog: "Sent \(commandDisplayName).")
    }

    private var commandDisplayName: String {
        switch command {
        case .power: "Power"
        case .home: "Home"
        case .playPause: "Play or Pause"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        }
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
            intent: SendRemoteCommandIntent(),
            phrases: [
                "Send TV command with \(.applicationName)"
            ],
            shortTitle: "TV Command",
            systemImageName: "tv"
        )
    }
}
