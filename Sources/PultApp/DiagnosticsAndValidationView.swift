import Foundation
import SwiftUI
import PultCore
#if canImport(PostHog)
import PostHog
#endif
#if canImport(UIKit)
import UIKit
#endif

struct DiagnosticsAndValidationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RemoteControlModel

    @State private var completedIDs: Set<String> = []
    @State private var statusMessage: String?
    @State private var validationRun: ValidationRunState?
    @State private var latestValidationReport: ValidationReport?
    @State private var latestSuccessfulValidation: PhysicalDeviceValidationRecord?
    @State private var validationClaimState: DeviceValidationClaimState = .unvalidated
    @State private var isRunningValidation = false
    @State private var isMeasuringTimings = CommandTimingRecorder.isEnabled()
    @State private var recentTimings: [CommandTiming] = []

    private let store = UserDefaultsValidationChecklistStore()
    private let validationStore = UserDefaultsValidationReportStore()
    private let timingLog = CommandTimingLog.appGroup()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DiagnosticValueRow("TV", value: model.selectedDevice?.name ?? "None", systemImage: "tv")
                    DiagnosticValueRow("Host", value: model.selectedDevice?.host ?? "None", systemImage: "network")
                    DiagnosticValueRow("Command Port", value: selectedDevicePort(\.commandPort), systemImage: "arrow.left.arrow.right")
                    DiagnosticValueRow("Pairing Port", value: selectedDevicePort(\.pairingPort), systemImage: "link")
                    DiagnosticValueRow("Paired", value: model.selectedDevice?.isPaired == true ? "Yes" : "No", systemImage: "checkmark.seal")
                } header: {
                    Text("Selected TV")
                }

                Section {
                    DiagnosticValueRow("Connection", value: model.session.connectionState.diagnosticText, systemImage: "antenna.radiowaves.left.and.right")
                    DiagnosticValueRow("Last Sent", value: format(model.session.lastSentAt), systemImage: "paperplane")
                    DiagnosticValueRow("Last Received", value: format(model.session.lastReceivedAt), systemImage: "tray.and.arrow.down")
                    DiagnosticValueRow("Last Error", value: model.session.lastError ?? "None", systemImage: "exclamationmark.triangle")
                    if let volume = model.session.volumeStatus {
                        DiagnosticValueRow(
                            "Volume",
                            value: "\(volume.level)/\(volume.maximum)\(volume.muted ? " muted" : "")",
                            systemImage: volume.muted ? "speaker.slash" : "speaker.wave.2"
                        )
                    } else {
                        DiagnosticValueRow("Volume", value: "No TV update yet", systemImage: "speaker.wave.2")
                    }
                    if let status = model.session.textFieldStatus {
                        DiagnosticValueRow("TV Text Field", value: textFieldSummary(status), systemImage: "keyboard")
                    } else {
                        DiagnosticValueRow("TV Text Field", value: "No focused field", systemImage: "keyboard.badge.ellipsis")
                    }
                } header: {
                    Text("Session")
                }

                Section {
                    DiagnosticValueRow(
                        "Session TV",
                        value: model.session.device?.name ?? "No active session",
                        systemImage: "tv.and.mediabox"
                    )
                    ForEach(model.session.protocolState.diagnosticLines, id: \.self) { line in
                        DiagnosticValueRow(
                            lineTitle(line),
                            value: lineValue(line),
                            systemImage: "waveform.path.ecg"
                        )
                    }
                } header: {
                    Text("Protocol Observations")
                } footer: {
                    Text("Session-scoped protocol observations from the TV. These are diagnostics, not physical validation evidence.")
                }

                Section {
                    Toggle("Record Command Timing", isOn: $isMeasuringTimings)
                        .onChange(of: isMeasuringTimings) { _, enabled in
                            CommandTimingRecorder.setEnabled(enabled)
                            if enabled { statusMessage = "Recording command timing." }
                        }

                    DiagnosticValueRow(
                        "Volume Pushes",
                        value: volumePushSummary,
                        systemImage: "speaker.wave.2"
                    )

                    if recentTimings.isEmpty {
                        DiagnosticValueRow(
                            "Recent Commands",
                            value: isMeasuringTimings ? "None yet" : "Recording off",
                            systemImage: "clock"
                        )
                    } else {
                        ForEach(recentTimings) { timing in
                            CommandTimingRow(timing: timing)
                        }
                    }

                    Button("Refresh Timings", systemImage: "arrow.clockwise") {
                        reloadTimings()
                    }
                    Button("Clear Timings", systemImage: "trash", role: .destructive) {
                        timingLog?.clear()
                        recentTimings = []
                        statusMessage = "Cleared command timings."
                    }
                } header: {
                    Text("Command Timing")
                } footer: {
                    Text("Measurement only. Turn on, run the lock-screen test protocol, then read the WARM/COLD breakdown here. Turn off when done.")
                }

                Section {
                    DiagnosticValueRow("Discovery", value: model.discovery.discoveryState.diagnosticText, systemImage: "dot.radiowaves.left.and.right")
                    DiagnosticValueRow("Selected Source", value: selectedDevicePresenceText, systemImage: "tag")
                    DiagnosticValueRow("Reachability", value: selectedDeviceReachabilityText, systemImage: "checkmark.circle")
                    DiagnosticValueRow("Saved TVs", value: "\(model.discovery.devices.count)", systemImage: "list.bullet")
                    DiagnosticValueRow("Nearby TVs", value: "\(model.discovery.discoveredDevices.count)", systemImage: "magnifyingglass")
                    Button("Scan Nearby TVs", systemImage: "dot.radiowaves.left.and.right") {
                        scanNearbyTVs()
                    }
                    .disabled(model.discovery.discoveryState == .scanning)
                    Button("Check Reachability", systemImage: "network") {
                        checkSelectedReachability()
                    }
                    .disabled(model.selectedDevice == nil || selectedDeviceReachability == .checking)
                    Button("Connect or Retry", systemImage: "arrow.clockwise") {
                        connect()
                    }
                    .disabled(model.selectedDevice?.isPaired != true)
                } header: {
                    Text("Discovery")
                }

                Section {
                    DeviceValidationClaimRow(state: validationClaimState)
                    if let latestValidationReport {
                        LastValidationReportRow(report: latestValidationReport)
                    } else {
                        DiagnosticValueRow("Last Validation", value: "Not run for this TV", systemImage: "checklist")
                    }

                    Button(validationButtonTitle, systemImage: validationButtonSystemImage) {
                        runValidation()
                    }
                    .disabled(isRunningValidation)

                    if !validationResults.isEmpty {
                        ForEach(validationResults) { item in
                            ValidationRunnerRow(
                                item: item,
                                canSendAction: validationAction(for: item) != nil && !isRunningValidation,
                                onSend: { performValidationAction(for: item) },
                                onPass: { markValidation(item, status: .passed, note: "Confirmed on the TV.") },
                                onFail: { markValidation(item, status: .failed, note: "Failed during physical validation.") }
                            )
                        }
                    }
                } header: {
                    Text("Validation Runner")
                } footer: {
                    Text("Automated checks verify app state and connection health. Manual rows send a command and wait for you to confirm what happened on the TV.")
                }

                ForEach(ValidationChecklistSection.all) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button {
                                toggle(item)
                            } label: {
                                ChecklistItemRow(
                                    item: item,
                                    isComplete: completedIDs.contains(item.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(section.title)
                    }
                }

                Section {
                    #if canImport(UIKit)
                    Button("Copy Diagnostics", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = diagnosticsText
                        statusMessage = "Copied diagnostics."
                    }
                    #endif
                    Button("Reset Checklist", systemImage: "arrow.counterclockwise", role: .destructive) {
                        completedIDs.removeAll()
                        store.save(completedIDs)
                        statusMessage = "Checklist reset."
                    }
                    if !validationResults.isEmpty {
                        #if canImport(UIKit)
                        Button("Copy Validation Report", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = validationReportText
                            statusMessage = "Copied validation report."
                        }
                        #endif
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("These checks are for physical iPhone plus Google TV validation. Passing local builds alone does not prove end-to-end TV behavior.")
                }

                Section {
                    Text("Pult is not affiliated with or endorsed by Google. Google TV and Android TV are trademarks of Google LLC.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Diagnostics")
            .scrollContentBackground(.hidden)
            .background { RemoteBackground() }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: model.selectedDevice?.id) {
            loadPersistedValidationState()
            reloadTimings()
        }
    }

    private var validationResults: [ValidationRunItem] {
        validationRun?.items ?? []
    }

    private var validationRunStartedAt: Date? {
        validationRun?.startedAt ?? latestValidationReport?.startedAt
    }

    private var validationButtonTitle: String {
        if isRunningValidation {
            return "Running Validation"
        }
        return latestValidationReport == nil && validationRun == nil
            ? "Run Validation"
            : "Re-run Validation"
    }

    private var validationButtonSystemImage: String {
        isRunningValidation ? "clock.arrow.circlepath" : "arrow.clockwise.circle"
    }

    private var diagnosticsText: String {
        var lines = [
            "Pult Diagnostics",
            "TV: \(model.selectedDevice?.name ?? "None")",
            "Host: \(model.selectedDevice?.host ?? "None")",
            "Command Port: \(selectedDevicePort(\.commandPort))",
            "Pairing Port: \(selectedDevicePort(\.pairingPort))",
            "Paired: \(model.selectedDevice?.isPaired == true ? "Yes" : "No")",
            "Connection: \(model.session.connectionState.diagnosticText)",
            "Last Sent: \(format(model.session.lastSentAt))",
            "Last Received: \(format(model.session.lastReceivedAt))",
            "Last Error: \(model.session.lastError ?? "None")",
            "Volume: \(model.session.volumeStatus?.diagnosticText ?? "No TV update yet")",
            "Text Field: \(model.session.textFieldStatus.map(textFieldSummary) ?? "No focused field")",
            "Discovery: \(model.discovery.discoveryState.diagnosticText)",
            "Selected Source: \(selectedDevicePresenceText)",
            "Reachability: \(selectedDeviceReachabilityText)",
            "Saved TVs: \(model.discovery.devices.count)",
            "Nearby TVs: \(model.discovery.discoveredDevices.count)",
            "Validation State: \(validationClaimState.label)",
            "Last Successful Validation: \(latestSuccessfulValidation.map(validationSummary) ?? "None")",
            "Last Validation Report: \(latestValidationReport?.summary ?? "Not run for this TV")",
            "Checklist: \(completedIDs.count)/\(ValidationChecklistSection.totalItemCount)"
        ]
        lines.append("")
        lines.append("Protocol Observations (not validation evidence):")
        lines.append("- Session TV: \(model.session.device?.name ?? "No active session")")
        lines.append(contentsOf: model.session.protocolState.diagnosticLines.map { "- \($0)" })
        return lines.joined(separator: "\n")
    }

    private var validationReportText: String {
        let header = [
            "Pult Validation Report",
            "TV: \(model.selectedDevice?.name ?? latestValidationReport?.deviceName ?? "None")",
            "Host: \(model.selectedDevice?.host ?? latestValidationReport?.host ?? "None")",
            "Started: \(format(validationRunStartedAt ?? latestValidationReport?.startedAt))",
            "Updated: \(format(latestValidationReport?.updatedAt))",
            "Claim State: \(validationClaimState.label)",
            "Last Successful Validation: \(latestSuccessfulValidation.map(validationSummary) ?? "None")",
            "Summary: \(validationRun?.summary ?? latestValidationReport?.summary ?? "No validation run")"
        ]
        let rows = validationResults.map { item in
            "- \(item.title): \(item.status.label)\(item.note.isEmpty ? "" : " - \(item.note)")"
        }
        return (header + rows).joined(separator: "\n")
    }

    private func selectedDevicePort(_ keyPath: KeyPath<DeviceRecord, UInt16>) -> String {
        guard let selectedDevice = model.selectedDevice else { return "None" }
        return "\(selectedDevice[keyPath: keyPath])"
    }

    private var selectedDevicePresenceText: String {
        guard let selectedDevice = model.selectedDevice else { return "None" }
        return model.discovery.presence(for: selectedDevice).diagnosticText
    }

    private var selectedDeviceReachability: DeviceReachability {
        guard let selectedDevice = model.selectedDevice else { return .unknown }
        return model.discovery.reachability(for: selectedDevice)
    }

    private var selectedDeviceReachabilityText: String {
        selectedDeviceReachability.diagnosticText
    }

    private func format(_ date: Date?) -> String {
        guard let date else { return "Not yet" }
        return date.formatted(date: .omitted, time: .standard)
    }

    private var volumePushSummary: String {
        let count = model.session.volumePushCount
        guard count > 0, let volume = model.session.volumeStatus else {
            return "None yet"
        }
        return "\(count) · last \(volume.level)/\(volume.maximum)\(volume.muted ? " muted" : "")"
    }

    private func reloadTimings() {
        recentTimings = timingLog?.recent(limit: 12) ?? []
    }

    private func validationSummary(_ validation: PhysicalDeviceValidationRecord) -> String {
        let date = validation.validatedAt.formatted(date: .abbreviated, time: .shortened)
        let areas = validation.passedAreas.map(\.title).joined(separator: ", ")
        return "\(date) - \(validation.deviceName) (\(validation.host)) - \(areas)"
    }

    private func textFieldSummary(_ status: RemoteTextFieldStatus) -> String {
        let label = status.label.isEmpty ? "Focused" : status.label
        return "\(label), counter \(status.counter), selection \(status.selectionStart)-\(status.selectionEnd)"
    }

    private func lineTitle(_ line: String) -> String {
        guard let separator = line.firstIndex(of: ":") else { return line }
        return String(line[..<separator])
    }

    private func lineValue(_ line: String) -> String {
        guard let separator = line.firstIndex(of: ":") else { return "" }
        let valueStart = line.index(after: separator)
        return String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connect() {
        statusMessage = "Connecting..."
        Task {
            await model.ensureConnected(staleAfter: 0)
            statusMessage = model.session.connectionState == .connected
                ? "Connected."
                : model.session.lastError ?? "Connection did not complete."
        }
    }

    private func scanNearbyTVs() {
        statusMessage = "Scanning nearby TVs..."
        Task {
            await model.discovery.refresh()
            statusMessage = "Scan started. Found \(model.discovery.discoveredDevices.count) so far."
        }
    }

    private func checkSelectedReachability() {
        guard let device = model.selectedDevice else {
            statusMessage = "Select a TV first."
            return
        }
        statusMessage = "Checking \(device.name)..."
        Task {
            let result = await model.discovery.checkReachability(for: device)
            statusMessage = "\(device.name): \(result.diagnosticText)"
        }
    }

    private func toggle(_ item: ValidationChecklistItem) {
        if completedIDs.contains(item.id) {
            completedIDs.remove(item.id)
        } else {
            completedIDs.insert(item.id)
        }
        store.save(completedIDs)
    }

    private func loadPersistedValidationState() {
        completedIDs = store.load()
        latestValidationReport = validationStore.latestReport(for: model.selectedDevice?.id)
        latestSuccessfulValidation = validationStore.latestSuccessfulValidation(for: model.selectedDevice?.id)
        validationClaimState = validationStore.validationClaimState(for: model.selectedDevice?.id)
        validationRun = latestValidationReport.map(ValidationRunState.init(report:))
    }

    private func runValidation() {
        guard !isRunningValidation else { return }
        isRunningValidation = true
        statusMessage = latestValidationReport == nil
            ? "Running validation..."
            : "Re-running validation for \(model.selectedDevice?.name ?? "this TV")..."
        validationRun = ValidationRunState(startedAt: .now)
        Task {
            await performValidationRun()
        }
    }

    private func performValidationRun() async {
        await RemoteValidationRunner.run(
            model: model,
            options: RemoteValidationRunOptions(
                favoriteAppAvailable: FavoriteAppLinkStore().load().first?.url != nil
            ),
            update: { id, status, note in
                updateValidation(id, status: status, note: note)
            },
            skipPending: { reason in
                skipPendingValidationItems(reason: reason)
            }
        )
        finishValidation()
    }

    private func performValidationAction(for item: ValidationRunItem) {
        guard let action = validationAction(for: item) else { return }
        updateValidation(item.id, status: .running, note: "Sending command...")
        Task {
            let outcome: HeadlessCommandOutcome
            switch action {
            case let .key(key):
                outcome = await model.sendKey(key, staleAfter: 0)
            case let .appLink(url):
                outcome = await model.openAppLink(url, staleAfter: 0)
            }

            switch outcome {
            case .sent:
                updateValidation(item.id, status: .needsReview, note: "Command sent. Confirm the result on the TV.")
            case let .failed(message):
                let failure = RemoteCommandFailure(message: message)
                updateValidation(item.id, status: .failed, note: "\(failure.message) \(failure.guidance)")
            }
            saveValidationReport()
        }
    }

    private func markValidation(_ item: ValidationRunItem, status: ValidationRunStatus, note: String) {
        updateValidation(item.id, status: status, note: note)
        saveValidationReport()
    }

    private enum ValidationAction {
        case key(RemoteKey)
        case appLink(URL)
    }

    private func validationAction(for item: ValidationRunItem) -> ValidationAction? {
        switch item.id {
        case ValidationRunStepID.dpad:
            return .key(.up)
        case ValidationRunStepID.media:
            return .key(.playPause)
        case ValidationRunStepID.volume:
            return .key(.volumeUp)
        case ValidationRunStepID.favoriteApp:
            guard let url = FavoriteAppLinkStore().load().first?.url else { return nil }
            return .appLink(url)
        default:
            return nil
        }
    }

    private func updateValidation(_ id: String, status: ValidationRunStatus, note: String) {
        guard var run = validationRun else { return }
        run.update(id, status: status, note: note)
        validationRun = run
    }

    private func skipPendingValidationItems(reason: String) {
        guard var run = validationRun else { return }
        run.skipPending(reason: reason)
        validationRun = run
    }

    private func finishValidation() {
        isRunningValidation = false
        saveValidationReport()
        if case let .validated(validation) = validationClaimState {
            statusMessage = "Validated \(validation.deviceName) on a physical Google TV."
        } else {
            statusMessage = "Validation updated: \(validationRun?.summary ?? "No validation run")."
        }
        #if canImport(PostHog)
        let validationOutcome: String = {
            switch validationClaimState {
            case .validated: return "validated"
            case .needsAttention: return "needs_attention"
            case .unvalidated: return "unvalidated"
            }
        }()
        PostHogSDK.shared.capture("validation_run_completed", properties: [
            "outcome": validationOutcome,
        ])
        #endif
    }

    private func saveValidationReport() {
        guard let validationRun else { return }
        let report = validationRun.makeReport(for: model.selectedDevice)
        validationStore.save(report)
        model.recordSuccessfulValidation(from: report)
        latestValidationReport = report
        latestSuccessfulValidation = validationStore.latestSuccessfulValidation(for: model.selectedDevice?.id)
        validationClaimState = validationStore.validationClaimState(for: model.selectedDevice?.id)
    }
}

private struct DeviceValidationClaimRow: View {
    let state: DeviceValidationClaimState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.label)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var systemImage: String {
        switch state {
        case .unvalidated:
            "checklist.unchecked"
        case .validated:
            "checkmark.seal.fill"
        case .needsAttention:
            "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .unvalidated:
            .secondary
        case .validated:
            PultDesign.connected
        case .needsAttention:
            PultDesign.warning
        }
    }

    private var detail: String {
        switch state {
        case .unvalidated:
            return "No successful physical Google TV validation is recorded for this TV."
        case let .validated(validation):
            let date = validation.validatedAt.formatted(date: .abbreviated, time: .shortened)
            return "Validated on \(date) with \(validation.passedAreas.count) passed areas."
        case let .needsAttention(report, lastSuccessful):
            if let lastSuccessful {
                let date = lastSuccessful.validatedAt.formatted(date: .abbreviated, time: .shortened)
                return "Latest run needs attention: \(report.summary). Last success was \(date)."
            }
            return "Latest run needs attention: \(report.summary)."
        }
    }
}

private struct LastValidationReportRow: View {
    let report: ValidationReport

    var body: some View {
        let presentation = RemoteValidationPresentation(report: report)

        HStack(spacing: 12) {
            Image(systemName: presentation.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(presentation.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.body.weight(.semibold))
                Text("\(report.updatedAt.formatted(date: .abbreviated, time: .shortened)) - \(presentation.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ValidationRunnerRow: View {
    let item: ValidationRunItem
    let canSendAction: Bool
    let onSend: () -> Void
    let onPass: () -> Void
    let onFail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.status.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.status.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                    Text(item.note.isEmpty ? item.detail : item.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Text(item.status.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.status.color)
            }

            if item.status == .needsReview {
                HStack(spacing: 10) {
                    if canSendAction {
                        Button("Send", systemImage: "paperplane", action: onSend)
                            .buttonStyle(.bordered)
                    }
                    Button("Pass", systemImage: "checkmark", action: onPass)
                        .buttonStyle(.bordered)
                    Button("Fail", systemImage: "xmark", role: .destructive, action: onFail)
                        .buttonStyle(.bordered)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension ValidationRunStatus {
    var systemImage: String {
        switch self {
        case .pending: "circle"
        case .running: "clock.arrow.circlepath"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "minus.circle"
        case .needsReview: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: .secondary
        case .running: .pultAccent
        case .passed: PultDesign.connected
        case .failed: PultDesign.danger
        case .skipped: .secondary
        case .needsReview: PultDesign.warning
        }
    }
}

private struct DiagnosticValueRow: View {
    var title: String
    var value: String
    var systemImage: String

    init(_ title: String, value: String, systemImage: String) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CommandTimingRow: View {
    let timing: CommandTiming

    private var iconName: String {
        if !timing.succeeded { return "exclamationmark.triangle" }
        return timing.dialed ? "bolt.slash" : "bolt.fill"
    }

    private var iconColor: Color {
        if !timing.succeeded { return PultDesign.danger }
        return timing.dialed ? PultDesign.warning : PultDesign.connected
    }

    private var detail: String {
        timing.succeeded ? timing.detailLine : timing.detailLine + " · failed"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(timing.summaryLine)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timing.key), \(timing.classification), \(Int(timing.totalMs.rounded())) milliseconds\(timing.succeeded ? "" : ", failed")")
    }
}

private struct ChecklistItemRow: View {
    let item: ValidationChecklistItem
    let isComplete: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(isComplete ? PultDesign.connected : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isComplete ? "\(item.title), complete" : "\(item.title), incomplete")
    }
}
