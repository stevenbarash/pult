import ActivityKit
import AppIntents
import PultCore
import SwiftUI
import WidgetKit

extension Color {
    // Editorial Calm palette — sage accent on near-black canvas.
    // These mirror PultDesign tokens in the app target (which cannot be
    // imported here) so the widget surface reads as the same visual family.
    static let pultWidgetAccent = Color(red: 157.0 / 255.0, green: 179.0 / 255.0, blue: 154.0 / 255.0)   // sage  #9DB39A
    static let pultWidgetWarning = Color(red: 200.0 / 255.0, green: 169.0 / 255.0, blue: 106.0 / 255.0)  // muted gold  #C8A96A
    static let pultWidgetConnected = Color(red: 157.0 / 255.0, green: 179.0 / 255.0, blue: 154.0 / 255.0) // sage  #9DB39A
    static let pultWidgetDanger = Color(red: 217.0 / 255.0, green: 140.0 / 255.0, blue: 128.0 / 255.0)   // muted coral  #D98C80
}

/// The hero control for a Lock Screen slot or the Action button: one press
/// connects to the selected TV and summons the Live Activity remote.
struct RemoteSessionControl: ControlWidget {
    static let kind = "app.pult.controls.session"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: RemoteDeviceControlValueProvider()
        ) { value in
            ControlWidgetButton(action: StartRemoteSessionIntent(device: value.device)) {
                Label(value.sessionLabel, systemImage: value.sessionSystemImage)
                    .controlWidgetStatus(value.statusText)
                    .controlWidgetActionHint(value.sessionActionHint)
            }
            .tint(.pultWidgetAccent)
            .privacySensitive(value.device != nil)
        }
        .displayName("TV Remote")
        .description("Connects to a Google TV and puts the remote on the Lock Screen.")
        .promptsForUserConfiguration()
    }
}

/// A single-command button the user configures (play/pause by default).
struct RemoteCommandControl: ControlWidget {
    static let kind = "app.pult.controls.command"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: RemoteCommandControlValueProvider()
        ) { configuration in
            ControlWidgetButton(
                action: SendRemoteKeyIntent(
                    command: configuration.command,
                    device: configuration.device
                )
            ) {
                Label(configuration.commandLabel, systemImage: configuration.command.systemImage)
                    .controlWidgetStatus(configuration.statusText)
                    .controlWidgetActionHint(configuration.commandActionHint)
            }
            .tint(.pultWidgetAccent)
            .privacySensitive(configuration.device != nil)
        }
        .displayName("Send TV Command")
        .description("Sends a chosen command to a saved Google TV.")
        .promptsForUserConfiguration()
    }
}

struct SelectRemoteCommandIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose TV Command"
    static let description = IntentDescription(
        "Choose the TV and command for a Pult control.",
        categoryName: "TV Remote",
        searchKeywords: ["Google TV", "Control Center", "remote command"]
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$command) to \(\.$device)")
    }

    @Parameter(
        title: "Command",
        description: "The remote button this control should send.",
        default: .playPause,
        requestValueDialog: "Which command should this control send?"
    )
    var command: RemoteKeyOption

    @Parameter(
        title: "TV",
        description: "The saved Google TV this control should use.",
        requestValueDialog: "Which TV should this control use?"
    )
    var device: RemoteDeviceEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Opens the full app (touchpad, pairing). Requires unlock, by design.
struct OpenRemoteControl: ControlWidget {
    static let kind = "app.pult.controls.open"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: RemoteDeviceControlValueProvider()
        ) { value in
            ControlWidgetButton(action: OpenRemoteIntent(device: value.device)) {
                Label(value.openLabel, systemImage: value.openSystemImage)
                    .controlWidgetStatus(value.statusText)
                    .controlWidgetActionHint(value.openActionHint)
            }
            .tint(.pultWidgetAccent)
            .privacySensitive(value.device != nil)
        }
        .displayName("Open Pult Remote")
        .description("Opens the full Pult remote for a saved TV.")
        .promptsForUserConfiguration()
    }
}

private struct RemoteDeviceControlValue {
    var device: RemoteDeviceEntity?
    var activityStatus: RemoteSessionAttributes.Status?
    var hasLiveActivity: Bool

    var isPaired: Bool {
        device?.isPaired ?? false
    }

    var sessionLabel: String {
        if let device, isPaired {
            return "\(device.name) Remote"
        }
        if let device {
            return "Pair \(device.name)"
        }
        return "TV Remote"
    }

    var sessionSystemImage: String {
        guard isPaired else { return device == nil ? "av.remote" : "link.badge.plus" }
        switch activityStatus {
        case .connected: return "av.remote.fill"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .failed: return "exclamationmark.triangle"
        case nil: return "av.remote"
        }
    }

    var sessionActionHint: String {
        guard device != nil else { return "Choose a saved TV" }
        guard isPaired else { return "Pair in Pult" }
        if activityStatus == .failed { return "Retry connection" }
        return hasLiveActivity ? "Refresh remote" : "Show Lock Screen remote"
    }

    var openLabel: String {
        if let device {
            return "Open \(device.name)"
        }
        return "Open Pult"
    }

    var openSystemImage: String {
        guard device != nil else { return "appletvremote.gen4" }
        return isPaired ? "appletvremote.gen4.fill" : "link.badge.plus"
    }

    var openActionHint: String {
        guard device != nil else { return "Choose or add a TV" }
        return isPaired ? "Open full remote" : "Open pairing"
    }

    var statusText: String {
        guard let device else { return "Choose a TV" }
        guard isPaired else { return "Pair \(device.name)" }
        switch activityStatus {
        case .connected: return "Connected: \(device.name)"
        case .connecting: return "Connecting: \(device.name)"
        case .failed: return "Needs attention"
        case nil: return hasLiveActivity ? "Remote active" : "Ready: \(device.name)"
        }
    }
}

private struct RemoteCommandControlValue {
    var command: RemoteKeyOption
    var device: RemoteDeviceEntity?
    var activityStatus: RemoteSessionAttributes.Status?

    var commandLabel: String {
        return command.displayTitle
    }

    var commandActionHint: String {
        guard device != nil else { return "Choose a saved TV" }
        guard device?.isPaired == true else { return "Pair in Pult" }
        guard let device else { return "Choose a saved TV" }
        return "Send to \(device.name)"
    }

    var statusText: String {
        guard let device else { return "Choose a TV" }
        guard device.isPaired else { return "Pair \(device.name)" }
        switch activityStatus {
        case .connected: return "Connected: \(device.name)"
        case .connecting: return "Connecting: \(device.name)"
        case .failed: return "Needs attention"
        case nil: return "Ready: \(device.name)"
        }
    }
}

private struct RemoteDeviceControlValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectRemoteDeviceIntent) -> RemoteDeviceControlValue {
        RemoteDeviceControlValue(
            device: configuration.device,
            activityStatus: .connected,
            hasLiveActivity: true
        )
    }

    func currentValue(configuration: SelectRemoteDeviceIntent) async throws -> RemoteDeviceControlValue {
        let device = Self.preferredDevice(configuredDevice: configuration.device)
        let activity = Self.activity(for: device)
        return RemoteDeviceControlValue(
            device: device,
            activityStatus: activity?.content.state.status,
            hasLiveActivity: activity != nil
        )
    }
}

private struct RemoteCommandControlValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectRemoteCommandIntent) -> RemoteCommandControlValue {
        RemoteCommandControlValue(
            command: configuration.command,
            device: configuration.device,
            activityStatus: .connected
        )
    }

    func currentValue(configuration: SelectRemoteCommandIntent) async throws -> RemoteCommandControlValue {
        let device = RemoteDeviceControlValueProvider.preferredDevice(configuredDevice: configuration.device)
        return RemoteCommandControlValue(
            command: configuration.command,
            device: device,
            activityStatus: RemoteDeviceControlValueProvider.activity(for: device)?.content.state.status
        )
    }
}

private extension RemoteDeviceControlValueProvider {
    static func preferredDevice(configuredDevice: RemoteDeviceEntity?) -> RemoteDeviceEntity? {
        if let configuredDevice {
            return configuredDevice
        }

        let store = UserDefaultsDeviceStore()
        let devices = store.loadDevices()
        if let selectedID = store.loadSelectedDeviceID(),
           let selectedDevice = devices.first(where: { $0.id == selectedID }) {
            return RemoteDeviceEntity(device: selectedDevice)
        }
        return devices.first.map(RemoteDeviceEntity.init(device:))
    }

    static func activity(for device: RemoteDeviceEntity?) -> Activity<RemoteSessionAttributes>? {
        guard let device,
              let deviceID = UUID(uuidString: device.id) else {
            return Activity<RemoteSessionAttributes>.activities.first
        }
        return Activity<RemoteSessionAttributes>.activities.first {
            $0.attributes.deviceID == deviceID
        }
    }
}
