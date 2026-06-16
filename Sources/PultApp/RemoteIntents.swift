import AppIntents
import CoreSpotlight
import Foundation
import OSLog
import PultCore
import UniformTypeIdentifiers
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

private let intentLogger = Logger(subsystem: "app.pult", category: "intents")

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
    case back, home, voiceSearch
    case search
    case power
    case volumeUp, volumeDown, mute
    case playPause, rewind, fastForward

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Remote Command",
        synonyms: ["TV command", "remote button", "remote key"]
    )

    static let caseDisplayRepresentations: [RemoteKeyOption: DisplayRepresentation] = [
        .up: DisplayRepresentation(title: "Up", synonyms: ["D-pad up", "Move up"]),
        .down: DisplayRepresentation(title: "Down", synonyms: ["D-pad down", "Move down"]),
        .left: DisplayRepresentation(title: "Left", synonyms: ["D-pad left", "Move left"]),
        .right: DisplayRepresentation(title: "Right", synonyms: ["D-pad right", "Move right"]),
        .select: DisplayRepresentation(title: "Select", synonyms: ["OK", "Enter", "Choose"]),
        .back: DisplayRepresentation(title: "Back", synonyms: ["Return", "Previous"]),
        .home: DisplayRepresentation(title: "Home", synonyms: ["Home screen"]),
        .voiceSearch: DisplayRepresentation(title: "Voice Search", synonyms: ["Google Assistant", "Microphone", "Search by voice"]),
        .search: DisplayRepresentation(title: "Search", synonyms: ["Text search", "Find"]),
        .power: DisplayRepresentation(title: "Power", synonyms: ["Turn TV on", "Turn TV off"]),
        .volumeUp: DisplayRepresentation(title: "Volume Up", synonyms: ["Louder", "Raise volume"]),
        .volumeDown: DisplayRepresentation(title: "Volume Down", synonyms: ["Quieter", "Lower volume"]),
        .mute: DisplayRepresentation(title: "Mute", synonyms: ["Mute sound", "Silence TV"]),
        .playPause: DisplayRepresentation(title: "Play or Pause", synonyms: ["Play", "Pause"]),
        .rewind: DisplayRepresentation(title: "Rewind", synonyms: ["Skip back"]),
        .fastForward: DisplayRepresentation(title: "Fast Forward", synonyms: ["Skip forward"])
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
        case .voiceSearch: .voiceSearch
        case .search: .search
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
        case .voiceSearch: "Voice Search"
        case .search: "Search"
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
        case .voiceSearch: "mic.fill"
        case .search: "magnifyingglass"
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

struct RemoteDeviceEntity: AppEntity, IndexedEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "TV",
        synonyms: ["Google TV", "Android TV", "television"]
    )
    static let defaultQuery = RemoteDeviceQuery()

    let id: String
    let name: String
    let host: String
    let isPaired: Bool

    init(device: DeviceRecord) {
        self.id = device.id.uuidString
        self.name = device.name
        self.host = device.host
        self.isPaired = device.isPaired
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: isPaired ? "Ready at \(host)" : "Pair in Pult - \(host)",
            synonyms: ["Google TV", "remote"]
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = name
        attributes.contentDescription = isPaired
            ? "Paired Google TV at \(host)"
            : "Unpaired Google TV at \(host)"
        attributes.keywords = [
            "Pult",
            "Google TV",
            "Android TV",
            "remote",
            "remote control",
            "TV",
            "television",
            "Siri",
            "Shortcuts",
            "Spotlight",
            "Control Center",
            "Lock Screen",
            "Live Activity",
            isPaired ? "paired" : "pairing",
            name,
            host
        ]
        return attributes
    }
}

struct RemoteDeviceQuery: EntityStringQuery {
    func entities(for identifiers: [RemoteDeviceEntity.ID]) async throws -> [RemoteDeviceEntity] {
        let identifierSet = Set(identifiers)
        return Self.storedDevices()
            .filter { identifierSet.contains($0.id.uuidString) }
            .map(RemoteDeviceEntity.init(device:))
    }

    func entities(matching string: String) async throws -> [RemoteDeviceEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try await suggestedEntities() }
        return Self.storedDevices()
            .filter { device in
                device.name.localizedStandardContains(query)
                    || device.host.localizedStandardContains(query)
            }
            .map(RemoteDeviceEntity.init(device:))
    }

    func suggestedEntities() async throws -> [RemoteDeviceEntity] {
        Self.storedDevices().map(RemoteDeviceEntity.init(device:))
    }

    private static func storedDevices() -> [DeviceRecord] {
        UserDefaultsDeviceStore().loadDevices()
    }
}

struct OpenRemoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Remote"
    static let description = IntentDescription(
        "Open Pult to the remote controls.",
        categoryName: "TV Remote",
        searchKeywords: ["Google TV", "remote", "television", "pairing"]
    )
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$device)")
    }

    @Parameter(
        title: "TV",
        description: "The saved Google TV to open.",
        requestValueDialog: "Which TV should Pult open?"
    )
    var device: RemoteDeviceEntity?

    init() {
        self.device = nil
    }

    init(device: RemoteDeviceEntity?) {
        self.device = device
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SharedRemote.model.selectIfAvailable(device) else {
            return .result(dialog: RemoteIntentDialogs.deviceUnavailable)
        }
        if let device = SharedRemote.model.selectedDevice {
            return .result(dialog: IntentDialog(stringLiteral: "Opening \(device.name)."))
        }
        return .result(dialog: "Opening Pult.")
    }
}

struct SendRemoteKeyIntent: HeadlessRemoteIntent {
    static let title: LocalizedStringResource = "Send Remote Command"
    static let description = IntentDescription(
        "Send a command to a Google TV without opening Pult.",
        categoryName: "TV Remote",
        searchKeywords: ["Google TV", "remote", "Siri", "Control Center", "Lock Screen"]
    )
    static let openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$command) to \(\.$device)")
    }

    @Parameter(
        title: "Command",
        description: "The remote button to press.",
        default: .playPause,
        requestValueDialog: "Which remote command should Pult send?"
    )
    var command: RemoteKeyOption

    @Parameter(
        title: "TV",
        description: "The saved Google TV to control.",
        requestValueDialog: "Which TV should Pult control?"
    )
    var device: RemoteDeviceEntity?

    init() {
        self.command = .playPause
        self.device = nil
    }

    init(command: RemoteKeyOption) {
        self.command = command
        self.device = nil
    }

    init(command: RemoteKeyOption, device: RemoteDeviceEntity?) {
        self.command = command
        self.device = device
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = ProcessClock.start
        let model = SharedRemote.model
        guard model.selectIfAvailable(device) else {
            return .result(dialog: RemoteIntentDialogs.deviceUnavailable)
        }
        guard model.selectedDevice != nil else {
            return .result(dialog: RemoteIntentDialogs.noSavedTV)
        }
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
            return .result(dialog: IntentDialog(stringLiteral: "Could not send \(command.displayTitle): \(message)"))
        }
    }
}

struct StartRemoteSessionIntent: HeadlessRemoteIntent {
    static let title: LocalizedStringResource = "Show TV Remote"
    static let description = IntentDescription(
        "Connect to a Google TV and put the remote on the Lock Screen.",
        categoryName: "TV Remote",
        searchKeywords: ["Google TV", "Live Activity", "Lock Screen", "Control Center", "Action button"]
    )
    static let openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Show remote for \(\.$device)")
    }

    @Parameter(
        title: "TV",
        description: "The saved Google TV to show on the Lock Screen.",
        requestValueDialog: "Which TV should Pult show on the Lock Screen?"
    )
    var device: RemoteDeviceEntity?

    init() {
        self.device = nil
    }

    init(device: RemoteDeviceEntity?) {
        self.device = device
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = ProcessClock.start
        // The process name tells us whether the system honored the
        // LiveActivityIntent app-process routing (it must say "Pult", not
        // "PultWidgets") — the key diagnostic for control presses.
        intentLogger.debug("StartRemoteSessionIntent in \(ProcessInfo.processInfo.processName, privacy: .public)")
        let model = SharedRemote.model
        guard model.selectIfAvailable(device) else {
            return .result(dialog: RemoteIntentDialogs.deviceUnavailable)
        }
        guard let device = model.selectedDevice else {
            return .result(dialog: RemoteIntentDialogs.noSavedTV)
        }
        guard device.isPaired else {
            return .result(dialog: IntentDialog(stringLiteral: "Open Pult and pair \(device.name) first."))
        }
        // The remote appears on the lock screen immediately, in "connecting"
        // state, BEFORE the dial: instant feedback for the Control Center /
        // Action button press, and the status updates once the dial settles.
        #if canImport(ActivityKit) && os(iOS)
        await RemoteActivityController.shared.startOrUpdate(for: device, state: .connecting)
        #endif
        await model.ensureConnected()
        #if canImport(ActivityKit) && os(iOS)
        await RemoteActivityController.shared.startOrUpdate(
            for: device, state: model.session.connectionState
        )
        if !ActivityAuthorizationInfo().areActivitiesEnabled,
           model.session.connectionState == .connected {
            return .result(dialog: IntentDialog(stringLiteral:
                "Connected to \(device.name). Enable Live Activities in Settings to get the Lock Screen remote."
            ))
        }
        #endif
        if case let .failed(message) = model.session.connectionState {
            return .result(dialog: IntentDialog(stringLiteral: "Could not show the remote for \(device.name): \(message)"))
        }
        return .result(dialog: IntentDialog(stringLiteral: "Remote ready for \(device.name)."))
    }
}

struct EndRemoteSessionIntent: HeadlessRemoteIntent {
    static let title: LocalizedStringResource = "Hide TV Remote"
    static let description = IntentDescription(
        "Disconnect and remove the remote from the Lock Screen.",
        categoryName: "TV Remote",
        searchKeywords: ["Google TV", "Live Activity", "Lock Screen", "remote"]
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedRemote.model.session.disconnect()
        #if canImport(ActivityKit) && os(iOS)
        await RemoteActivityController.shared.endAll()
        #endif
        return .result(dialog: "TV remote hidden.")
    }
}

enum RemoteIntentIndex {
    @MainActor
    static func refreshDevices(_ devices: [DeviceRecord]) async {
        let entities = devices.map(RemoteDeviceEntity.init(device:))
        do {
            let index = CSSearchableIndex.default()
            try await index.deleteAppEntities(ofType: RemoteDeviceEntity.self)
            if !entities.isEmpty {
                try await index.indexAppEntities(entities)
            }
        } catch {
            intentLogger.debug("Remote device indexing failed: \(String(describing: error), privacy: .public)")
        }
    }

    @MainActor
    static func donateSelectedDeviceShortcuts(for device: DeviceRecord?) async {
        guard let device else { return }
        let entity = RemoteDeviceEntity(device: device)
        do {
            try await IntentDonationManager.shared.donate(intent: OpenRemoteIntent(device: entity))
            try await IntentDonationManager.shared.donate(intent: StartRemoteSessionIntent(device: entity))
            try await IntentDonationManager.shared.donate(
                intent: SendRemoteKeyIntent(command: .playPause, device: entity)
            )
        } catch {
            intentLogger.debug("Remote intent donation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

struct SelectRemoteDeviceIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose TV"
    static let description = IntentDescription(
        "Choose the saved Google TV for a Pult control.",
        categoryName: "TV Remote",
        searchKeywords: ["Google TV", "Control Center", "remote"]
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Use \(\.$device)")
    }

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

struct PultShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRemoteIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open remote in \(.applicationName)",
                "Open my TV remote in \(.applicationName)",
                "Open \(\.$device) in \(.applicationName)",
                "Open \(\.$device) remote in \(.applicationName)"
            ],
            shortTitle: "Open Remote",
            systemImageName: "av.remote"
        )

        AppShortcut(
            intent: StartRemoteSessionIntent(),
            phrases: [
                "Show my TV remote with \(.applicationName)",
                "\(.applicationName) remote",
                "Show the Lock Screen remote with \(.applicationName)",
                "Show \(\.$device) remote with \(.applicationName)",
                "Put \(\.$device) remote on the Lock Screen with \(.applicationName)"
            ],
            shortTitle: "TV Remote",
            systemImageName: "av.remote"
        )

        AppShortcut(
            intent: SendRemoteKeyIntent(),
            phrases: [
                "\(\.$command) the TV with \(.applicationName)",
                "\(\.$command) with \(.applicationName)",
                "Send \(\.$command) to the TV with \(.applicationName)",
                "Send a command to \(\.$device) with \(.applicationName)",
                "Send TV command with \(.applicationName)"
            ],
            shortTitle: "Send Command",
            systemImageName: "tv"
        )
    }
}

private enum RemoteIntentDialogs {
    static let deviceUnavailable: IntentDialog =
        "That TV is no longer saved in Pult. Open Pult to choose another TV."
    static let noSavedTV: IntentDialog =
        "Open Pult and add a Google TV first."
}

private extension RemoteControlModel {
    @discardableResult
    func selectIfAvailable(_ entity: RemoteDeviceEntity?) -> Bool {
        guard let entity else { return true }
        guard let id = UUID(uuidString: entity.id),
              let device = discovery.devices.first(where: { $0.id == id }) else {
            return false
        }
        select(device)
        return true
    }
}
