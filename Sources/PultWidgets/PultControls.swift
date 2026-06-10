import AppIntents
import SwiftUI
import WidgetKit

/// The hero control for a Lock Screen slot or the Action button: one press
/// connects to the selected TV and summons the Live Activity remote.
struct RemoteSessionControl: ControlWidget {
    static let kind = "app.pult.controls.session"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartRemoteSessionIntent()) {
                Label("TV Remote", systemImage: "av.remote")
            }
        }
        .displayName("TV Remote")
        .description("Connects to your Google TV and puts the remote on the Lock Screen.")
    }
}

/// A single-command button the user configures (play/pause by default).
struct RemoteCommandControl: ControlWidget {
    static let kind = "app.pult.controls.command"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: RemoteCommandProvider()
        ) { command in
            ControlWidgetButton(action: SendRemoteKeyIntent(command: command)) {
                Label(command.displayTitle, systemImage: command.systemImage)
            }
        }
        .displayName("TV Command")
        .description("Sends one command to your Google TV.")
    }
}

struct RemoteCommandProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectRemoteCommandIntent) -> RemoteKeyOption {
        configuration.command
    }

    func currentValue(configuration: SelectRemoteCommandIntent) async throws -> RemoteKeyOption {
        configuration.command
    }
}

struct SelectRemoteCommandIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose TV Command"

    @Parameter(title: "Command", default: .playPause)
    var command: RemoteKeyOption

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Opens the full app (touchpad, pairing). Requires unlock, by design.
struct OpenRemoteControl: ControlWidget {
    static let kind = "app.pult.controls.open"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenRemoteIntent()) {
                Label("Open Pult", systemImage: "appletvremote.gen4.fill")
            }
        }
        .displayName("Open Pult")
        .description("Opens the full remote.")
    }
}
