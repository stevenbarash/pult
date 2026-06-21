import Foundation
import Testing
@testable import PultCore

@Test
func validationDefinitionUsesStableUniqueSteps() {
    let items = ValidationRunDefinition.makeItems()
    let ids = items.map(\.id)

    #expect(ids.count == Set(ids).count)
    #expect(ids.first == ValidationRunStepID.selectedTV)
    #expect(ids.contains(ValidationRunStepID.favoriteApp))
    #expect(items.allSatisfy { $0.status == .pending && $0.note.isEmpty && $0.updatedAt == nil })
}

@Test
func validationRunStateUpdatesSkipsAndSummarizesRows() {
    let start = Date(timeIntervalSince1970: 100)
    let updateDate = Date(timeIntervalSince1970: 200)
    var run = ValidationRunState(startedAt: start)

    let selectedTVUpdated = run.update(
        ValidationRunStepID.selectedTV,
        status: .passed,
        note: "Selected.",
        at: updateDate
    )
    let missingStepUpdated = run.update(
        "missing-step",
        status: .failed,
        note: "Nope.",
        at: updateDate
    )
    #expect(selectedTVUpdated)
    #expect(!missingStepUpdated)
    run.skipPending(reason: "Stopped early.", at: updateDate)

    #expect(run.startedAt == start)
    #expect(run.items.first { $0.id == ValidationRunStepID.selectedTV }?.status == .passed)
    #expect(run.items.first { $0.id == ValidationRunStepID.discovery }?.status == .skipped)
    #expect(run.items.allSatisfy { $0.status != .pending })
    #expect(run.summary == "1 passed, 0 failed, 0 need review, 10 skipped")
}

@Test
func validationReportCapturesDeviceAndFailureSummary() {
    var run = ValidationRunState(startedAt: Date(timeIntervalSince1970: 100))
    run.update(ValidationRunStepID.selectedTV, status: .passed, note: "Selected.", at: Date(timeIntervalSince1970: 101))
    run.update(ValidationRunStepID.reachability, status: .failed, note: "Timed out.", at: Date(timeIntervalSince1970: 102))

    let device = DeviceRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
        name: "Living Room",
        host: "10.0.0.42",
        isPaired: true
    )
    let report = run.makeReport(for: device, updatedAt: Date(timeIntervalSince1970: 200))

    #expect(report.deviceID == device.id)
    #expect(report.deviceName == "Living Room")
    #expect(report.host == "10.0.0.42")
    #expect(report.hasFailures)
    #expect(report.summary == "1 passed, 1 failed, 0 need review, 0 skipped")
    #expect(!report.isSuccessfulPhysicalValidation)
    #expect(report.physicalDeviceValidation == nil)
}

@Test
func protocolEvidenceReportCapturesStage2QuestionsWithoutValidationClaim() throws {
    let device = DeviceRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000045")!,
        name: "Living Room",
        host: "10.0.0.45",
        isPaired: true
    )
    let protocolState = RemoteSessionProtocolState(
        negotiation: RemoteProtocolNegotiation(
            inboundConfigureCode: RemoteProtocolObservation(
                value: RemoteProtocolCode(rawValue: 64),
                observedAt: Date(timeIntervalSince1970: 101),
                deviceID: device.id,
                connectionAttempt: 1,
                source: "remote_configure.code1"
            ),
            outboundConfigureCode: RemoteProtocolObservation(
                value: RemoteProtocolCode(rawValue: 622),
                observedAt: Date(timeIntervalSince1970: 102),
                deviceID: device.id,
                connectionAttempt: 1,
                source: "client.remote_configure.code1"
            ),
            inboundSetActiveCode: RemoteProtocolObservation(
                value: RemoteProtocolCode(rawValue: 64),
                observedAt: Date(timeIntervalSince1970: 103),
                deviceID: device.id,
                connectionAttempt: 1,
                source: "remote_set_active.active"
            ),
            outboundSetActiveCode: RemoteProtocolObservation(
                value: RemoteProtocolCode(rawValue: 622),
                observedAt: Date(timeIntervalSince1970: 104),
                deviceID: device.id,
                connectionAttempt: 1,
                source: "client.remote_set_active.active"
            )
        ),
        deviceInfo: RemoteProtocolObservation(
            value: RemoteDeviceInfo(
                model: "Chromecast",
                vendor: "Google",
                packageName: "com.google.android.tv.remote.service",
                appVersion: "5.2"
            ),
            observedAt: Date(timeIntervalSince1970: 105),
            deviceID: device.id,
            connectionAttempt: 1,
            source: "remote_configure.device_info"
        ),
        remoteStart: RemoteProtocolObservation(
            value: true,
            observedAt: Date(timeIntervalSince1970: 106),
            deviceID: device.id,
            connectionAttempt: 1,
            source: "remote_start.started"
        ),
        imeApp: RemoteProtocolObservation(
            value: RemoteAppInfo(label: "Netflix", appPackage: "com.netflix.ninja"),
            observedAt: Date(timeIntervalSince1970: 107),
            deviceID: device.id,
            connectionAttempt: 1,
            source: "remote_ime_key_inject.app_info"
        ),
        lastImeBatchEdit: RemoteProtocolObservation(
            value: RemoteImeBatchEditObservation(
                imeCounter: 3,
                fieldCounter: 9,
                edits: [RemoteEditInfoObservation(editType: 1)]
            ),
            observedAt: Date(timeIntervalSince1970: 108),
            deviceID: device.id,
            connectionAttempt: 1,
            source: "remote_ime_batch_edit"
        )
    )

    let evidence = ProtocolEvidenceReport(
        device: device,
        connectionState: .connected,
        protocolState: protocolState,
        capturedAt: Date(timeIntervalSince1970: 200)
    )

    #expect(!evidence.isValidationEvidence)
    #expect(evidence.questions.map(\.id) == [
        "remote-start-arrival",
        "remote-start-false",
        "ime-app-scope",
        "feature-mask-values",
        "dynamic-negotiation-safety"
    ])
    #expect(evidence.observation(named: "remote-start")?.value == "observed started=true")
    #expect(evidence.observation(named: "ime-app")?.value == "label Netflix, package com.netflix.ninja")
    #expect(evidence.observation(named: "feature-mask-values")?.value.contains("configure from TV 64") == true)
    #expect(evidence.observation(named: "configure-mask-from-tv")?.observedAt == Date(timeIntervalSince1970: 101))
    #expect(evidence.observation(named: "configure-mask-from-tv")?.deviceID == device.id)
    #expect(evidence.observation(named: "configure-mask-from-tv")?.connectionAttempt == 1)
    #expect(evidence.observation(named: "dynamic-negotiation")?.value.contains("client response remains 622") == true)
    #expect(evidence.questionAnswers.map(\.id) == [
        "remote-start-arrival",
        "remote-start-false",
        "ime-app-scope",
        "feature-mask-values",
        "dynamic-negotiation-safety"
    ])
    #expect(evidence.questionAnswers.first { $0.id == "remote-start-arrival" }?.status == .captured)
    #expect(evidence.questionAnswers.first { $0.id == "remote-start-false" }?.status == .manualEvidenceRequired)
    #expect(evidence.questionAnswers.first { $0.id == "ime-app-scope" }?.answer.contains("scope remains unproven") == true)
    #expect(evidence.questionAnswers.first { $0.id == "feature-mask-values" }?.status == .captured)
    #expect(evidence.questionAnswers.first { $0.id == "dynamic-negotiation-safety" }?.answer.contains("not proven safe") == true)
    #expect(evidence.copyLines.contains("Protocol Evidence Capture (not validation evidence)"))
    #expect(evidence.copyLines.contains("Stage 2 Question Status:"))
    #expect(evidence.copyLines.contains { $0.contains("remote_start false/meaning: Manual Evidence Required") })
}

@Test
func validationReportPersistsProtocolEvidenceWithoutCountingItAsValidation() throws {
    var run = ValidationRunState(startedAt: Date(timeIntervalSince1970: 100))
    run.update(ValidationRunStepID.selectedTV, status: .passed, note: "Selected.", at: Date(timeIntervalSince1970: 101))
    let device = DeviceRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000046")!,
        name: "Office TV",
        host: "10.0.0.46",
        isPaired: true
    )
    let evidence = ProtocolEvidenceReport(
        device: device,
        connectionState: .connected,
        protocolState: RemoteSessionProtocolState(
            remoteStart: RemoteProtocolObservation(
                value: false,
                observedAt: Date(timeIntervalSince1970: 102),
                deviceID: device.id,
                connectionAttempt: 1,
                source: "remote_start.started"
            )
        ),
        capturedAt: Date(timeIntervalSince1970: 200)
    )

    let report = run.makeReport(
        for: device,
        updatedAt: Date(timeIntervalSince1970: 300),
        protocolEvidence: evidence
    )

    #expect(report.protocolEvidence == evidence)
    #expect(!report.isSuccessfulPhysicalValidation)
    #expect(report.physicalDeviceValidation == nil)

    let data = try JSONEncoder().encode(report)
    let decoded = try JSONDecoder().decode(ValidationReport.self, from: data)
    #expect(decoded.protocolEvidence == evidence)
    #expect(decoded.protocolEvidence?.observation(named: "remote-start")?.value == "observed started=false")
    #expect(decoded.protocolEvidence?.questionAnswers.first { $0.id == "remote-start-false" }?.answer.contains("started=false was captured") == true)
    #expect(decoded.protocolEvidence?.questionAnswers.first { $0.id == "remote-start-false" }?.status == .manualEvidenceRequired)
}

@Test
func legacyValidationReportJSONWithoutProtocolEvidenceDecodesNil() throws {
    let data = """
    [
      {
        "id": "00000000-0000-0000-0000-000000000047",
        "deviceID": "00000000-0000-0000-0000-000000000048",
        "deviceName": "Legacy TV",
        "host": "10.0.0.48",
        "startedAt": 100,
        "updatedAt": 200,
        "items": [
          {
            "id": "selected-tv",
            "title": "Selected TV",
            "detail": "A saved TV is selected.",
            "status": "passed",
            "note": "Selected.",
            "updatedAt": 101
          }
        ]
      }
    ]
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode([ValidationReport].self, from: data)

    #expect(decoded.count == 1)
    #expect(decoded.first?.protocolEvidence == nil)
}

@Test
func successfulPhysicalValidationRequiresResolvedRequiredAreas() throws {
    var run = ValidationRunState(startedAt: Date(timeIntervalSince1970: 100))
    for item in run.items {
        let status: ValidationRunStatus = item.id == ValidationRunStepID.keyboard ? .skipped : .passed
        let didUpdate = run.update(item.id, status: status, note: "Checked.", at: Date(timeIntervalSince1970: 101))
        #expect(didUpdate)
    }

    let device = DeviceRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000043")!,
        name: "Office TV",
        host: "10.0.0.43",
        isPaired: true
    )
    let report = run.makeReport(for: device, updatedAt: Date(timeIntervalSince1970: 200))
    let validation = try #require(report.physicalDeviceValidation)

    #expect(report.isSuccessfulPhysicalValidation)
    #expect(validation.reportID == report.id)
    #expect(validation.deviceID == device.id)
    #expect(validation.deviceName == "Office TV")
    #expect(validation.host == "10.0.0.43")
    #expect(validation.validatedAt == Date(timeIntervalSince1970: 200))
    #expect(validation.passedAreas.map(\.id).contains(ValidationRunStepID.dpad))
    #expect(!validation.passedAreas.map(\.id).contains(ValidationRunStepID.keyboard))
}

@Test
func unresolvedManualReviewDoesNotCountAsValidated() {
    var run = ValidationRunState(startedAt: Date(timeIntervalSince1970: 100))
    for item in run.items {
        run.update(item.id, status: .passed, note: "Checked.", at: Date(timeIntervalSince1970: 101))
    }
    run.update(ValidationRunStepID.volume, status: .needsReview, note: "Confirm on TV.", at: Date(timeIntervalSince1970: 102))

    let report = run.makeReport(
        for: DeviceRecord(name: "Office TV", host: "10.0.0.43", isPaired: true),
        updatedAt: Date(timeIntervalSince1970: 200)
    )

    #expect(report.hasUnresolvedItems)
    #expect(!report.isSuccessfulPhysicalValidation)
    #expect(report.physicalDeviceValidation == nil)
}

@MainActor
@Test
func remoteValidationRunnerStopsWhenNoDeviceIsSelected() async {
    let model = RemoteControlModel(
        discovery: DeviceDiscovery(store: MemoryDeviceStore()),
        session: RemoteSession(transport: MockTransport())
    )
    let updateDate = Date(timeIntervalSince1970: 200)
    var run = ValidationRunState(startedAt: Date(timeIntervalSince1970: 100))

    await RemoteValidationRunner.run(
        model: model,
        options: RemoteValidationRunOptions(
            discoveryPresenceTimeout: .milliseconds(1),
            discoveryPollInterval: .milliseconds(1),
            favoriteAppAvailable: false
        ),
        update: { id, status, note in
            run.update(id, status: status, note: note, at: updateDate)
        },
        skipPending: { reason in
            run.skipPending(reason: reason, at: updateDate)
        }
    )

    #expect(run.items.first { $0.id == ValidationRunStepID.selectedTV }?.status == .failed)
    #expect(run.items.first { $0.id == ValidationRunStepID.discovery }?.status == .skipped)
    #expect(run.summary == "0 passed, 1 failed, 0 need review, 10 skipped")
}

@Test
func userDefaultsValidationStoresRoundTripState() throws {
    let suiteName = "app.pult.validation-tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let checklistStore = UserDefaultsValidationChecklistStore(defaults: defaults)
    checklistStore.save(["pairing", "same-wifi"])
    #expect(checklistStore.load() == Set(["pairing", "same-wifi"]))

    let reportStore = UserDefaultsValidationReportStore(defaults: defaults)
    let older = ValidationReport(
        deviceID: nil,
        deviceName: "No TV Selected",
        host: "None",
        startedAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20),
        items: []
    )
    let newer = ValidationReport(
        deviceID: nil,
        deviceName: "No TV Selected",
        host: "None",
        startedAt: Date(timeIntervalSince1970: 30),
        updatedAt: Date(timeIntervalSince1970: 40),
        items: [ValidationRunItem(id: ValidationRunStepID.selectedTV, title: "Selected TV", detail: "A saved TV is selected.", status: .failed)]
    )

    reportStore.save(older)
    reportStore.save(newer)

    #expect(reportStore.latestReport(for: nil)?.startedAt == newer.startedAt)
    #expect(reportStore.latestReport(for: nil)?.hasFailures == true)

    var successfulRun = ValidationRunState(startedAt: Date(timeIntervalSince1970: 50))
    for item in successfulRun.items {
        successfulRun.update(item.id, status: .passed, note: "Checked.", at: Date(timeIntervalSince1970: 51))
    }
    let device = DeviceRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000044")!,
        name: "Den TV",
        host: "10.0.0.44",
        isPaired: true
    )
    let successfulReport = successfulRun.makeReport(for: device, updatedAt: Date(timeIntervalSince1970: 60))
    reportStore.save(successfulReport)

    var failedRun = successfulRun
    failedRun.update(ValidationRunStepID.media, status: .failed, note: "No playback change.", at: Date(timeIntervalSince1970: 70))
    reportStore.save(failedRun.makeReport(for: device, updatedAt: Date(timeIntervalSince1970: 80)))

    #expect(reportStore.latestSuccessfulValidation(for: device.id)?.validatedAt == Date(timeIntervalSince1970: 60))
    switch reportStore.validationClaimState(for: device.id) {
    case let .needsAttention(_, lastSuccessful):
        #expect(lastSuccessful?.deviceName == "Den TV")
    default:
        Issue.record("expected failed latest report to need attention while keeping the last success")
    }
}

@Test
func validationChecklistDefinitionIsComplete() {
    #expect(ValidationChecklistSection.totalItemCount == 16)
    #expect(ValidationChecklistSection.all.map(\.title) == ["Setup", "Remote", "System Surfaces"])
}
