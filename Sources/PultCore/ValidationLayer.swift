import Foundation

public enum ValidationRunStepID {
    public static let selectedTV = "selected-tv"
    public static let discovery = "discovery"
    public static let reachability = "reachability"
    public static let paired = "paired"
    public static let freshConnect = "fresh-connect"
    public static let handshake = "handshake"
    public static let keyboard = "keyboard"
    public static let dpad = "dpad"
    public static let media = "media"
    public static let volume = "volume"
    public static let favoriteApp = "favorite-app"
}

public enum ValidationRunStatus: String, Codable, Equatable, Sendable {
    case pending
    case running
    case passed
    case failed
    case skipped
    case needsReview

    public var label: String {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .passed: "Passed"
        case .failed: "Failed"
        case .skipped: "Skipped"
        case .needsReview: "Review"
        }
    }
}

public struct ValidationRunItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var status: ValidationRunStatus
    public var note: String
    public var updatedAt: Date?

    public init(
        id: String,
        title: String,
        detail: String,
        status: ValidationRunStatus = .pending,
        note: String = "",
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.note = note
        self.updatedAt = updatedAt
    }
}

public enum ValidationRunDefinition {
    public static func makeItems() -> [ValidationRunItem] {
        [
            item(ValidationRunStepID.selectedTV, "Selected TV", "A saved TV is selected."),
            item(ValidationRunStepID.discovery, "Bonjour Discovery", "The selected TV appears in a nearby scan when it advertises."),
            item(ValidationRunStepID.reachability, "Command Port Reachability", "The selected TV accepts a TCP connection on the command port."),
            item(ValidationRunStepID.paired, "Pairing", "The selected TV is marked paired."),
            item(ValidationRunStepID.freshConnect, "Fresh Connection", "Reconnect if the current session is stale."),
            item(ValidationRunStepID.handshake, "Protocol Handshake", "The TV and phone exchange protocol frames."),
            item(ValidationRunStepID.keyboard, "Keyboard Readiness", "A focused TV text field is available, when applicable."),
            item(ValidationRunStepID.dpad, "D-pad Movement", "Send Up and confirm focus moves."),
            item(ValidationRunStepID.media, "Media Control", "Send Play/Pause and confirm playback changes."),
            item(ValidationRunStepID.volume, "Volume Route", "Send Volume Up and confirm the configured route changes."),
            item(ValidationRunStepID.favoriteApp, "Favorite App Link", "Send the first favorite app link and confirm the target opens.")
        ]
    }

    private static func item(_ id: String, _ title: String, _ detail: String) -> ValidationRunItem {
        ValidationRunItem(id: id, title: title, detail: detail)
    }
}

public struct ValidationRunState: Codable, Equatable, Sendable {
    public private(set) var startedAt: Date
    public private(set) var items: [ValidationRunItem]

    public init(startedAt: Date = .now, items: [ValidationRunItem] = ValidationRunDefinition.makeItems()) {
        self.startedAt = startedAt
        self.items = items
    }

    public init(report: ValidationReport) {
        self.startedAt = report.startedAt
        self.items = report.items
    }

    @discardableResult
    public mutating func update(
        _ id: String,
        status: ValidationRunStatus,
        note: String,
        at updatedAt: Date = .now
    ) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items[index].status = status
        items[index].note = note
        items[index].updatedAt = updatedAt
        return true
    }

    public mutating func skipPending(reason: String, at updatedAt: Date = .now) {
        for index in items.indices where items[index].status == .pending {
            items[index].status = .skipped
            items[index].note = reason
            items[index].updatedAt = updatedAt
        }
    }

    public var summary: String {
        Self.summary(for: items)
    }

    public func makeReport(for device: DeviceRecord?, updatedAt: Date = .now) -> ValidationReport {
        ValidationReport(
            deviceID: device?.id,
            deviceName: device?.name ?? "No TV Selected",
            host: device?.host ?? "None",
            startedAt: startedAt,
            updatedAt: updatedAt,
            items: items
        )
    }

    public static func summary(for items: [ValidationRunItem]) -> String {
        guard !items.isEmpty else { return "No validation run" }
        let passed = items.filter { $0.status == .passed }.count
        let failed = items.filter { $0.status == .failed }.count
        let needsReview = items.filter { $0.status == .needsReview }.count
        let skipped = items.filter { $0.status == .skipped }.count
        return "\(passed) passed, \(failed) failed, \(needsReview) need review, \(skipped) skipped"
    }
}

public struct PhysicalDeviceValidationArea: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct PhysicalDeviceValidationRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var reportID: UUID
    public var deviceID: UUID
    public var deviceName: String
    public var host: String
    public var validatedAt: Date
    public var passedAreas: [PhysicalDeviceValidationArea]

    public init(
        id: UUID = UUID(),
        reportID: UUID,
        deviceID: UUID,
        deviceName: String,
        host: String,
        validatedAt: Date,
        passedAreas: [PhysicalDeviceValidationArea]
    ) {
        self.id = id
        self.reportID = reportID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.host = host
        self.validatedAt = validatedAt
        self.passedAreas = passedAreas
    }
}

public enum DeviceValidationClaimState: Equatable, Sendable {
    case unvalidated
    case validated(PhysicalDeviceValidationRecord)
    case needsAttention(latestReport: ValidationReport, lastSuccessful: PhysicalDeviceValidationRecord?)

    public var label: String {
        switch self {
        case .unvalidated:
            "Unvalidated"
        case .validated:
            "Validated"
        case .needsAttention:
            "Needs Attention"
        }
    }
}

public struct ValidationReport: Codable, Equatable, Identifiable, Sendable {
    private static let requiredSuccessfulStepIDs: Set<String> = [
        ValidationRunStepID.selectedTV,
        ValidationRunStepID.reachability,
        ValidationRunStepID.paired,
        ValidationRunStepID.freshConnect,
        ValidationRunStepID.handshake,
        ValidationRunStepID.dpad,
        ValidationRunStepID.media,
        ValidationRunStepID.volume
    ]

    public var id: UUID
    public var deviceID: UUID?
    public var deviceName: String
    public var host: String
    public var startedAt: Date
    public var updatedAt: Date
    public var items: [ValidationRunItem]

    public init(
        id: UUID = UUID(),
        deviceID: UUID?,
        deviceName: String,
        host: String,
        startedAt: Date,
        updatedAt: Date,
        items: [ValidationRunItem]
    ) {
        self.id = id
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.host = host
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.items = items
    }

    public var summary: String {
        ValidationRunState.summary(for: items)
    }

    public var hasFailures: Bool {
        items.contains { $0.status == .failed }
    }

    public var hasUnresolvedItems: Bool {
        items.contains { item in
            switch item.status {
            case .pending, .running, .needsReview:
                return true
            case .passed, .failed, .skipped:
                return false
            }
        }
    }

    public var passedAreas: [PhysicalDeviceValidationArea] {
        items
            .filter { $0.status == .passed }
            .map { PhysicalDeviceValidationArea(id: $0.id, title: $0.title) }
    }

    public var isSuccessfulPhysicalValidation: Bool {
        guard deviceID != nil, !hasFailures, !hasUnresolvedItems, !passedAreas.isEmpty else { return false }
        let passedIDs = Set(items.filter { $0.status == .passed }.map(\.id))
        return Self.requiredSuccessfulStepIDs.isSubset(of: passedIDs)
    }

    public var physicalDeviceValidation: PhysicalDeviceValidationRecord? {
        guard isSuccessfulPhysicalValidation, let deviceID else { return nil }
        return PhysicalDeviceValidationRecord(
            id: id,
            reportID: id,
            deviceID: deviceID,
            deviceName: deviceName,
            host: host,
            validatedAt: updatedAt,
            passedAreas: passedAreas
        )
    }
}

public protocol ValidationReportStoring {
    func latestReport(for deviceID: UUID?) -> ValidationReport?
    func latestSuccessfulValidation(for deviceID: UUID?) -> PhysicalDeviceValidationRecord?
    func validationClaimState(for deviceID: UUID?) -> DeviceValidationClaimState
    func save(_ report: ValidationReport)
    func save(_ validation: PhysicalDeviceValidationRecord)
}

public struct UserDefaultsValidationReportStore: ValidationReportStoring {
    private let key: String
    private let successfulValidationKey: String
    private let defaults: UserDefaults

    public init(
        key: String = "pult.validationReports",
        successfulValidationKey: String = "pult.physicalDeviceValidations",
        defaults: UserDefaults = PultAppGroup.sharedDefaults()
    ) {
        self.key = key
        self.successfulValidationKey = successfulValidationKey
        self.defaults = defaults
    }

    public func latestReport(for deviceID: UUID?) -> ValidationReport? {
        let reports = load()
        guard let deviceID else {
            return reports.first { $0.deviceID == nil }
        }
        return reports.first { $0.deviceID == deviceID }
    }

    public func latestSuccessfulValidation(for deviceID: UUID?) -> PhysicalDeviceValidationRecord? {
        let validations = loadSuccessfulValidations()
        guard let deviceID else { return nil }
        return validations.first { $0.deviceID == deviceID }
    }

    public func validationClaimState(for deviceID: UUID?) -> DeviceValidationClaimState {
        let latestReport = latestReport(for: deviceID)
        let lastSuccessful = latestSuccessfulValidation(for: deviceID)
        if let latestReport, !latestReport.isSuccessfulPhysicalValidation {
            return .needsAttention(latestReport: latestReport, lastSuccessful: lastSuccessful)
        }
        if let lastSuccessful {
            return .validated(lastSuccessful)
        }
        return .unvalidated
    }

    public func save(_ report: ValidationReport) {
        var reports = load()
        if let index = reports.firstIndex(where: { $0.deviceID == report.deviceID }) {
            reports[index] = report
        } else {
            reports.append(report)
        }
        reports.sort { $0.updatedAt > $1.updatedAt }
        guard let data = try? JSONEncoder().encode(reports) else { return }
        defaults.set(data, forKey: key)
        if let validation = report.physicalDeviceValidation {
            save(validation)
        }
    }

    public func save(_ validation: PhysicalDeviceValidationRecord) {
        var validations = loadSuccessfulValidations()
        if let index = validations.firstIndex(where: { $0.deviceID == validation.deviceID }) {
            validations[index] = validation
        } else {
            validations.append(validation)
        }
        validations.sort { $0.validatedAt > $1.validatedAt }
        guard let data = try? JSONEncoder().encode(validations) else { return }
        defaults.set(data, forKey: successfulValidationKey)
    }

    private func load() -> [ValidationReport] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ValidationReport].self, from: data)) ?? []
    }

    private func loadSuccessfulValidations() -> [PhysicalDeviceValidationRecord] {
        guard let data = defaults.data(forKey: successfulValidationKey) else { return [] }
        return (try? JSONDecoder().decode([PhysicalDeviceValidationRecord].self, from: data)) ?? []
    }
}

public struct RemoteValidationRunOptions: Sendable {
    public var discoveryPresenceTimeout: Duration
    public var discoveryPollInterval: Duration
    public var favoriteAppAvailable: Bool

    public init(
        discoveryPresenceTimeout: Duration = .seconds(8),
        discoveryPollInterval: Duration = .milliseconds(250),
        favoriteAppAvailable: Bool = true
    ) {
        self.discoveryPresenceTimeout = discoveryPresenceTimeout
        self.discoveryPollInterval = discoveryPollInterval
        self.favoriteAppAvailable = favoriteAppAvailable
    }
}

@MainActor
public enum RemoteValidationRunner {
    public static func run(
        model: RemoteControlModel,
        options: RemoteValidationRunOptions = RemoteValidationRunOptions(),
        update: (_ id: String, _ status: ValidationRunStatus, _ note: String) -> Void,
        skipPending: (_ reason: String) -> Void
    ) async {
        update(ValidationRunStepID.selectedTV, .running, "Checking saved TV selection.")
        guard let device = model.selectedDevice else {
            update(ValidationRunStepID.selectedTV, .failed, "No TV is selected.")
            skipPending("Select a TV and run validation again.")
            return
        }
        update(ValidationRunStepID.selectedTV, .passed, "Selected \(device.name) at \(device.host).")

        update(ValidationRunStepID.discovery, .running, "Scanning for Bonjour advertisements.")
        await model.discovery.refresh()
        let discoveryPresence = await waitForDiscoveryPresence(
            for: device,
            model: model,
            timeout: options.discoveryPresenceTimeout,
            pollInterval: options.discoveryPollInterval
        )
        switch discoveryPresence {
        case .nearby:
            update(ValidationRunStepID.discovery, .passed, "\(device.name) appeared in the nearby scan.")
        case .manual:
            update(ValidationRunStepID.discovery, .skipped, "\(device.name) is a manual host entry; command-port reachability is the important check.")
        case .saved:
            update(ValidationRunStepID.discovery, .failed, "\(device.name) was saved from Bonjour but did not appear before the scan timeout.")
        }

        update(ValidationRunStepID.reachability, .running, "Checking \(device.host):\(device.commandPort).")
        let reachability = await model.discovery.checkReachability(for: device)
        switch reachability {
        case .reachable:
            update(ValidationRunStepID.reachability, .passed, "Command port \(device.commandPort) is reachable.")
        case let .unreachable(message, _):
            update(ValidationRunStepID.reachability, .failed, message)
        case .checking:
            update(ValidationRunStepID.reachability, .running, "Still checking reachability.")
        case .unknown:
            update(ValidationRunStepID.reachability, .failed, "Reachability was not checked.")
        }

        update(ValidationRunStepID.paired, .running, "Checking pairing state.")
        guard device.isPaired else {
            update(ValidationRunStepID.paired, .failed, "Pair \(device.name) before running command checks.")
            skipPending("Pairing is required for command validation.")
            return
        }
        update(ValidationRunStepID.paired, .passed, "\(device.name) is marked paired.")

        update(ValidationRunStepID.freshConnect, .running, "Connecting with stale-session refresh.")
        let connected = await model.ensureFreshConnection(staleAfter: 0)
        guard connected, model.session.connectionState == .connected else {
            update(ValidationRunStepID.freshConnect, .failed, model.session.lastError ?? "Connection did not complete.")
            skipPending("Connection failed.")
            return
        }
        update(ValidationRunStepID.freshConnect, .passed, "Connected to \(device.name).")

        update(ValidationRunStepID.handshake, .running, "Checking protocol traffic timestamps.")
        if model.session.lastReceivedAt != nil, model.session.lastSentAt != nil {
            update(ValidationRunStepID.handshake, .passed, "Protocol frames sent and received.")
        } else {
            update(ValidationRunStepID.handshake, .failed, "No complete protocol traffic was recorded.")
        }

        update(ValidationRunStepID.keyboard, .running, "Checking TV IME status.")
        if let textFieldStatus = model.session.textFieldStatus {
            update(ValidationRunStepID.keyboard, .passed, textFieldSummary(textFieldStatus))
        } else {
            update(ValidationRunStepID.keyboard, .skipped, "Focus a TV text field and rerun to validate keyboard input.")
        }

        update(ValidationRunStepID.dpad, .needsReview, "Send Up, then confirm focus moved on the TV.")
        update(ValidationRunStepID.media, .needsReview, "Send Play/Pause in a video app, then confirm playback changed.")
        update(ValidationRunStepID.volume, .needsReview, "Send Volume Up, then confirm the TV or CEC volume changed.")
        if options.favoriteAppAvailable {
            update(ValidationRunStepID.favoriteApp, .needsReview, "Send the first favorite app link, then confirm the TV opened the expected target.")
        } else {
            update(ValidationRunStepID.favoriteApp, .skipped, "No favorite app link is configured.")
        }
    }

    private static func waitForDiscoveryPresence(
        for device: DeviceRecord,
        model: RemoteControlModel,
        timeout: Duration,
        pollInterval: Duration
    ) async -> DevicePresence {
        if device.source == .manual {
            return model.discovery.presence(for: device)
        }

        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let presence = model.discovery.presence(for: device)
            if presence == .nearby {
                return presence
            }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return presence
            }
        }
        return model.discovery.presence(for: device)
    }

    private static func textFieldSummary(_ status: RemoteTextFieldStatus) -> String {
        let label = status.label.isEmpty ? "Focused" : status.label
        return "\(label), counter \(status.counter), selection \(status.selectionStart)-\(status.selectionEnd)"
    }
}

public struct ValidationChecklistSection: Identifiable, Sendable {
    public var id: String { title }
    public var title: String
    public var items: [ValidationChecklistItem]

    public init(title: String, items: [ValidationChecklistItem]) {
        self.title = title
        self.items = items
    }

    public static let all: [ValidationChecklistSection] = [
        ValidationChecklistSection(
            title: "Setup",
            items: [
                ValidationChecklistItem(id: "same-wifi", title: "Phone and TV on same Wi-Fi", detail: "Confirm both devices are on the intended local network."),
                ValidationChecklistItem(id: "discovery-or-manual", title: "TV saved by scan or manual IP", detail: "Bonjour scan or manual host entry reaches the expected TV."),
                ValidationChecklistItem(id: "pairing", title: "Pairing code accepted", detail: "The 6-character code completes pairing without retry."),
                ValidationChecklistItem(id: "command-channel", title: "Command channel connects", detail: "The session reaches Online after pairing.")
            ]
        ),
        ValidationChecklistSection(
            title: "Remote",
            items: [
                ValidationChecklistItem(id: "dpad", title: "D-pad and Select", detail: "Move focus in all directions and select an item."),
                ValidationChecklistItem(id: "nav-keys", title: "Back and Home", detail: "Back returns within apps and Home returns to Google TV."),
                ValidationChecklistItem(id: "media", title: "Media controls", detail: "Play/pause, rewind, and fast-forward behave in a video app."),
                ValidationChecklistItem(id: "volume", title: "Volume and mute", detail: "Volume follows the TV or CEC route configured on the device."),
                ValidationChecklistItem(id: "power", title: "Power or wake", detail: "Power behavior matches the TV model's supported sleep/wake path."),
                ValidationChecklistItem(id: "keyboard", title: "TV keyboard", detail: "Focused TV text fields accept typed text, delete, and enter."),
                ValidationChecklistItem(id: "favorite-apps", title: "Favorite app links", detail: "A saved favorite opens the intended TV app or fallback target.")
            ]
        ),
        ValidationChecklistSection(
            title: "System Surfaces",
            items: [
                ValidationChecklistItem(id: "live-activity", title: "Lock Screen remote appears", detail: "Start the remote and confirm the Live Activity is visible."),
                ValidationChecklistItem(id: "locked-command", title: "Locked command sends", detail: "With the phone locked, send a remote command from the Live Activity."),
                ValidationChecklistItem(id: "control-center", title: "Control Center command", detail: "Run the configured TV Command control."),
                ValidationChecklistItem(id: "siri-shortcuts", title: "Siri or Shortcuts command", detail: "Run a command intent for a named TV."),
                ValidationChecklistItem(id: "background-reconnect", title: "Reconnect after backgrounding", detail: "Leave Pult, return later, and confirm commands redial cleanly.")
            ]
        )
    ]

    public static var totalItemCount: Int {
        all.reduce(0) { $0 + $1.items.count }
    }
}

public struct ValidationChecklistItem: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct UserDefaultsValidationChecklistStore {
    private let key: String
    private let defaults: UserDefaults

    public init(
        key: String = "pult.validationChecklist.completedIDs",
        defaults: UserDefaults = PultAppGroup.sharedDefaults()
    ) {
        self.key = key
        self.defaults = defaults
    }

    public func load() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    public func save(_ completedIDs: Set<String>) {
        defaults.set(completedIDs.sorted(), forKey: key)
    }
}
