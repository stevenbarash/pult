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

public struct ProtocolEvidenceQuestion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var manualAction: String

    public init(id: String, title: String, manualAction: String) {
        self.id = id
        self.title = title
        self.manualAction = manualAction
    }
}

public enum ProtocolEvidenceAnswerStatus: String, Codable, Equatable, Sendable {
    case captured
    case notObserved
    case manualEvidenceRequired

    public var label: String {
        switch self {
        case .captured:
            "Captured"
        case .notObserved:
            "Not Observed"
        case .manualEvidenceRequired:
            "Manual Evidence Required"
        }
    }
}

public struct ProtocolEvidenceQuestionAnswer: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var status: ProtocolEvidenceAnswerStatus
    public var answer: String
    public var nextAction: String

    public init(
        id: String,
        title: String,
        status: ProtocolEvidenceAnswerStatus,
        answer: String,
        nextAction: String
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.answer = answer
        self.nextAction = nextAction
    }
}

public struct ProtocolEvidenceObservation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var value: String
    public var source: String
    public var observedAt: Date?
    public var deviceID: UUID?
    public var connectionAttempt: Int?
    public var note: String

    public init(
        id: String,
        title: String,
        value: String,
        source: String = "",
        observedAt: Date? = nil,
        deviceID: UUID? = nil,
        connectionAttempt: Int? = nil,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.source = source
        self.observedAt = observedAt
        self.deviceID = deviceID
        self.connectionAttempt = connectionAttempt
        self.note = note
    }
}

public struct ProtocolEvidenceReport: Codable, Equatable, Sendable {
    public static let stage2Questions: [ProtocolEvidenceQuestion] = [
        ProtocolEvidenceQuestion(
            id: "remote-start-arrival",
            title: "remote_start arrival",
            manualAction: "Run repeated fresh connects while the TV is awake."
        ),
        ProtocolEvidenceQuestion(
            id: "remote-start-false",
            title: "remote_start false/meaning",
            manualAction: "Manual TV-state comparison required."
        ),
        ProtocolEvidenceQuestion(
            id: "ime-app-scope",
            title: "IME app scope",
            manualAction: "Switch apps and enter text to learn whether app info is IME-scoped."
        ),
        ProtocolEvidenceQuestion(
            id: "feature-mask-values",
            title: "feature mask values",
            manualAction: "Record raw configure and set-active masks across sessions."
        ),
        ProtocolEvidenceQuestion(
            id: "dynamic-negotiation-safety",
            title: "dynamic negotiation safety",
            manualAction: "Keep client responses fixed until repeated captures prove a negotiated mask is safe."
        )
    ]

    public var capturedAt: Date
    public var deviceID: UUID?
    public var deviceName: String
    public var host: String
    public var connectionState: String
    public var observations: [ProtocolEvidenceObservation]
    public var questionAnswers: [ProtocolEvidenceQuestionAnswer]

    public init(
        capturedAt: Date = .now,
        deviceID: UUID?,
        deviceName: String,
        host: String,
        connectionState: String,
        observations: [ProtocolEvidenceObservation],
        questionAnswers: [ProtocolEvidenceQuestionAnswer]? = nil
    ) {
        self.capturedAt = capturedAt
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.host = host
        self.connectionState = connectionState
        self.observations = observations
        self.questionAnswers = questionAnswers ?? Self.makeUnansweredQuestionAnswers()
    }

    public init(
        device: DeviceRecord?,
        connectionState: ConnectionState,
        protocolState: RemoteSessionProtocolState,
        capturedAt: Date = .now
    ) {
        let observations = Self.makeObservations(from: protocolState)
        self.init(
            capturedAt: capturedAt,
            deviceID: device?.id,
            deviceName: device?.name ?? "No TV Selected",
            host: device?.host ?? "None",
            connectionState: connectionState.evidenceLabel,
            observations: observations,
            questionAnswers: Self.makeQuestionAnswers(from: protocolState)
        )
    }

    public var questions: [ProtocolEvidenceQuestion] {
        Self.stage2Questions
    }

    public var isValidationEvidence: Bool {
        false
    }

    public func observation(named id: String) -> ProtocolEvidenceObservation? {
        observations.first { $0.id == id }
    }

    public var copyLines: [String] {
        var lines = [
            "Protocol Evidence Capture (not validation evidence)",
            "Captured: \(Self.format(capturedAt))",
            "TV: \(deviceName)",
            "Host: \(host)",
            "Connection: \(connectionState)",
            "Observations:"
        ]
        lines.append(contentsOf: observations.map { observation in
            let provenance = Self.provenanceText(for: observation)
            let note = observation.note.isEmpty ? "" : " - \(observation.note)"
            return "- \(observation.title): \(observation.value)\(provenance)\(note)"
        })
        lines.append("Stage 2 Question Status:")
        lines.append(contentsOf: questionAnswers.map { answer in
            "- \(answer.title): \(answer.status.label) - \(answer.answer) Next: \(answer.nextAction)"
        })
        lines.append("Protocol evidence is diagnostic context only. It does not validate foreground app, power state, now-playing, or negotiated feature behavior by itself.")
        return lines
    }

    private static func makeObservations(from state: RemoteSessionProtocolState) -> [ProtocolEvidenceObservation] {
        [
            makeObservation(
                id: "remote-start",
                title: "remote_start",
                value: state.remoteStart.map { "observed started=\($0.value)" } ?? "not observed",
                observation: state.remoteStart,
                note: "Observed start flag only; not power state."
            ),
            makeObservation(
                id: "ime-app",
                title: "IME app info",
                value: state.imeApp.map { appInfoText($0.value) } ?? "not observed",
                observation: state.imeApp,
                note: "IME-scoped unless repeated captures prove otherwise."
            ),
            ProtocolEvidenceObservation(
                id: "feature-mask-values",
                title: "Feature mask values",
                value: featureMaskText(state.negotiation),
                note: "Summary only; use the raw mask rows for per-capture provenance."
            ),
            makeObservation(
                id: "configure-mask-from-tv",
                title: "Configure mask from TV",
                value: protocolCodeText(state.negotiation.inboundConfigureCode?.value),
                observation: state.negotiation.inboundConfigureCode,
                note: "Raw TV-advertised configure mask."
            ),
            makeObservation(
                id: "configure-mask-response",
                title: "Configure mask response",
                value: protocolCodeText(state.negotiation.outboundConfigureCode?.value),
                observation: state.negotiation.outboundConfigureCode,
                note: "Raw client configure response; current compatibility path should remain fixed."
            ),
            makeObservation(
                id: "set-active-mask-from-tv",
                title: "Set-active mask from TV",
                value: setActiveText(state.negotiation.inboundSetActiveCode?.value),
                observation: state.negotiation.inboundSetActiveCode,
                note: "Raw TV-advertised set-active mask, if present."
            ),
            makeObservation(
                id: "set-active-mask-response",
                title: "Set-active mask response",
                value: protocolCodeText(state.negotiation.outboundSetActiveCode?.value),
                observation: state.negotiation.outboundSetActiveCode,
                note: "Raw client set-active response; current compatibility path should remain fixed."
            ),
            ProtocolEvidenceObservation(
                id: "dynamic-negotiation",
                title: "Dynamic negotiation",
                value: dynamicNegotiationText(state.negotiation),
                note: "Preserve fixed client responses until physical captures prove a change is safe."
            ),
            makeObservation(
                id: "device-info",
                title: "Configure device info",
                value: state.deviceInfo.map { deviceInfoText($0.value) } ?? "not observed",
                observation: state.deviceInfo,
                note: "Local diagnostics only."
            ),
            makeObservation(
                id: "ime-batch",
                title: "Last IME batch",
                value: state.lastImeBatchEdit.map { imeBatchText($0.value) } ?? "not observed",
                observation: state.lastImeBatchEdit,
                note: "Counter/edit ordering evidence for text-entry behavior."
            )
        ]
    }

    private static func makeQuestionAnswers(from state: RemoteSessionProtocolState) -> [ProtocolEvidenceQuestionAnswer] {
        [
            remoteStartArrivalAnswer(state.remoteStart),
            remoteStartFalseAnswer(state.remoteStart),
            imeAppScopeAnswer(state.imeApp),
            featureMaskValuesAnswer(state.negotiation),
            dynamicNegotiationSafetyAnswer(state.negotiation)
        ]
    }

    private static func makeUnansweredQuestionAnswers() -> [ProtocolEvidenceQuestionAnswer] {
        stage2Questions.map { question in
            ProtocolEvidenceQuestionAnswer(
                id: question.id,
                title: question.title,
                status: .notObserved,
                answer: "No protocol evidence was captured for this question.",
                nextAction: question.manualAction
            )
        }
    }

    private static func makeObservation<Value: Equatable & Sendable>(
        id: String,
        title: String,
        value: String,
        observation: RemoteProtocolObservation<Value>?,
        note: String
    ) -> ProtocolEvidenceObservation {
        ProtocolEvidenceObservation(
            id: id,
            title: title,
            value: value,
            source: observation?.source ?? "",
            observedAt: observation?.observedAt,
            deviceID: observation?.deviceID,
            connectionAttempt: observation?.connectionAttempt,
            note: note
        )
    }

    private static func remoteStartArrivalAnswer(_ observation: RemoteProtocolObservation<Bool>?) -> ProtocolEvidenceQuestionAnswer {
        guard let observation else {
            return answer(
                "remote-start-arrival",
                status: .notObserved,
                answer: "remote_start did not arrive in this captured session."
            )
        }
        return answer(
            "remote-start-arrival",
            status: .captured,
            answer: "remote_start arrived with started=\(observation.value) at \(format(observation.observedAt)) on attempt \(observation.connectionAttempt).",
            nextAction: "Repeat fresh connects while the TV is awake to learn arrival frequency."
        )
    }

    private static func remoteStartFalseAnswer(_ observation: RemoteProtocolObservation<Bool>?) -> ProtocolEvidenceQuestionAnswer {
        guard let observation else {
            return answer(
                "remote-start-false",
                status: .notObserved,
                answer: "No remote_start value was captured, so false meaning remains unanswered."
            )
        }
        if observation.value {
            return answer(
                "remote-start-false",
                status: .manualEvidenceRequired,
                answer: "Only started=true was captured; started=false meaning remains unanswered.",
                nextAction: "Capture a started=false session with simultaneous TV state notes."
            )
        }
        return answer(
            "remote-start-false",
            status: .manualEvidenceRequired,
            answer: "started=false was captured, but its meaning is unknown without simultaneous TV state notes.",
            nextAction: "Record TV wake/sleep and app state at the same time as the capture."
        )
    }

    private static func imeAppScopeAnswer(_ observation: RemoteProtocolObservation<RemoteAppInfo>?) -> ProtocolEvidenceQuestionAnswer {
        guard let observation else {
            return answer(
                "ime-app-scope",
                status: .notObserved,
                answer: "No IME app info was captured."
            )
        }
        return answer(
            "ime-app-scope",
            status: .manualEvidenceRequired,
            answer: "Captured \(appInfoText(observation.value)); scope remains unproven until app-switch captures compare values.",
            nextAction: "Switch TV apps, focus text fields, and save one report per app."
        )
    }

    private static func featureMaskValuesAnswer(_ negotiation: RemoteProtocolNegotiation) -> ProtocolEvidenceQuestionAnswer {
        guard hasAnyNegotiationObservation(negotiation) else {
            return answer(
                "feature-mask-values",
                status: .notObserved,
                answer: "No configure or set-active masks were captured."
            )
        }
        return answer(
            "feature-mask-values",
            status: .captured,
            answer: featureMaskText(negotiation),
            nextAction: "Compare repeated saved reports across fresh sessions before changing negotiation behavior."
        )
    }

    private static func dynamicNegotiationSafetyAnswer(_ negotiation: RemoteProtocolNegotiation) -> ProtocolEvidenceQuestionAnswer {
        guard negotiation.outboundConfigureCode != nil || negotiation.outboundSetActiveCode != nil else {
            return answer(
                "dynamic-negotiation-safety",
                status: .notObserved,
                answer: "No client negotiation response was captured."
            )
        }
        return answer(
            "dynamic-negotiation-safety",
            status: .manualEvidenceRequired,
            answer: "\(dynamicNegotiationText(negotiation)); dynamic negotiation is not proven safe.",
            nextAction: "Keep fixed client responses until repeated physical captures prove a negotiated mask works."
        )
    }

    private static func answer(
        _ id: String,
        status: ProtocolEvidenceAnswerStatus,
        answer: String,
        nextAction: String? = nil
    ) -> ProtocolEvidenceQuestionAnswer {
        let question = stage2Questions.first { $0.id == id }
        return ProtocolEvidenceQuestionAnswer(
            id: id,
            title: question?.title ?? id,
            status: status,
            answer: answer,
            nextAction: nextAction ?? question?.manualAction ?? "Capture more physical-device evidence."
        )
    }

    private static func featureMaskText(_ negotiation: RemoteProtocolNegotiation) -> String {
        [
            "configure from TV \(protocolCodeText(negotiation.inboundConfigureCode?.value))",
            "set-active from TV \(setActiveText(negotiation.inboundSetActiveCode?.value))",
            "configure response \(protocolCodeText(negotiation.outboundConfigureCode?.value))",
            "set-active response \(protocolCodeText(negotiation.outboundSetActiveCode?.value))"
        ].joined(separator: "; ")
    }

    private static func dynamicNegotiationText(_ negotiation: RemoteProtocolNegotiation) -> String {
        let configureResponse = negotiation.outboundConfigureCode?.value.rawValue
        let setActiveResponse = negotiation.outboundSetActiveCode?.value.rawValue
        let configureFromTV = negotiation.inboundConfigureCode?.value.rawValue
        let setActiveFromTV = negotiation.inboundSetActiveCode?.value?.rawValue

        guard configureResponse != nil || setActiveResponse != nil else {
            return "client response not observed"
        }

        if configureResponse == setActiveResponse,
           configureResponse == configureFromTV,
           configureResponse == setActiveFromTV {
            return "client and TV masks matched at \(configureResponse.map(String.init) ?? "unknown"); repeat before enabling dynamic negotiation"
        }

        let clientText = setActiveResponse ?? configureResponse
        return "client response remains \(clientText.map(String.init) ?? "unknown") while TV advertised configure \(configureFromTV.map(String.init) ?? "not observed") and set-active \(setActiveFromTV.map(String.init) ?? "not observed")"
    }

    private static func hasAnyNegotiationObservation(_ negotiation: RemoteProtocolNegotiation) -> Bool {
        negotiation.inboundConfigureCode != nil
            || negotiation.outboundConfigureCode != nil
            || negotiation.inboundSetActiveCode != nil
            || negotiation.outboundSetActiveCode != nil
    }

    private static func setActiveText(_ code: RemoteProtocolCode??) -> String {
        guard let observationValue = code else {
            return "not observed"
        }
        guard let active = observationValue else {
            return "observed without active field"
        }
        return protocolCodeText(active)
    }

    private static func protocolCodeText(_ code: RemoteProtocolCode?) -> String {
        guard let code else { return "not observed" }
        let labels = code.labels.isEmpty ? "no known features" : code.labels.joined(separator: ", ")
        return "\(code.rawValue) (\(labels))"
    }

    private static func appInfoText(_ appInfo: RemoteAppInfo) -> String {
        let fields = [
            labeled("label", appInfo.label),
            labeled("package", appInfo.appPackage)
        ].compactMap { $0 }
        return fields.isEmpty ? "observed without app fields" : fields.joined(separator: ", ")
    }

    private static func deviceInfoText(_ deviceInfo: RemoteDeviceInfo) -> String {
        let fields = [
            labeled("model", deviceInfo.model),
            labeled("vendor", deviceInfo.vendor),
            labeled("package", deviceInfo.packageName),
            labeled("version", deviceInfo.appVersion)
        ].compactMap { $0 }
        return fields.isEmpty ? "observed without device fields" : fields.joined(separator: ", ")
    }

    private static func imeBatchText(_ batch: RemoteImeBatchEditObservation) -> String {
        var fields = ["\(batch.edits.count) edit\(batch.edits.count == 1 ? "" : "s")"]
        if let imeCounter = batch.imeCounter {
            fields.append("ime counter \(imeCounter)")
        }
        if let fieldCounter = batch.fieldCounter {
            fields.append("field counter \(fieldCounter)")
        }
        return fields.joined(separator: ", ")
    }

    private static func labeled(_ label: String, _ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return "\(label) \(value)"
    }

    private static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func provenanceText(for observation: ProtocolEvidenceObservation) -> String {
        var components: [String] = []
        if !observation.source.isEmpty {
            components.append(observation.source)
        }
        if let observedAt = observation.observedAt {
            components.append("observed \(format(observedAt))")
        }
        if let deviceID = observation.deviceID {
            components.append("device \(deviceID.uuidString)")
        }
        if let connectionAttempt = observation.connectionAttempt {
            components.append("attempt \(connectionAttempt)")
        }
        return components.isEmpty ? "" : " [\(components.joined(separator: "; "))]"
    }
}

private extension ConnectionState {
    var evidenceLabel: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .connecting:
            "Connecting"
        case .connected:
            "Connected"
        case let .failed(message):
            "Failed: \(message)"
        }
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

    public func makeReport(
        for device: DeviceRecord?,
        updatedAt: Date = .now,
        protocolEvidence: ProtocolEvidenceReport? = nil
    ) -> ValidationReport {
        ValidationReport(
            deviceID: device?.id,
            deviceName: device?.name ?? "No TV Selected",
            host: device?.host ?? "None",
            startedAt: startedAt,
            updatedAt: updatedAt,
            items: items,
            protocolEvidence: protocolEvidence
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
    public var protocolEvidence: ProtocolEvidenceReport?

    public init(
        id: UUID = UUID(),
        deviceID: UUID?,
        deviceName: String,
        host: String,
        startedAt: Date,
        updatedAt: Date,
        items: [ValidationRunItem],
        protocolEvidence: ProtocolEvidenceReport? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.host = host
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.items = items
        self.protocolEvidence = protocolEvidence
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
