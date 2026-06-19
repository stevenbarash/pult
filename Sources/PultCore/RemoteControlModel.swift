import Foundation
import Observation

public enum HeadlessCommandOutcome: Equatable, Sendable {
    case sent
    case failed(String)
}

public enum TextEntryPreparationResult: Equatable, Sendable {
    case ready
    case waitingForFocusedField
    case failed(String)
}

@MainActor
public protocol HeadlessWarmWindowMaintaining {
    func extend()
    func end()
}

public struct NoopHeadlessWarmWindow: HeadlessWarmWindowMaintaining {
    public init() {}
    public func extend() {}
    public func end() {}
}

@MainActor
@Observable
public final class RemoteControlModel {
    public let discovery: DeviceDiscovery
    public let session: RemoteSession
    public private(set) var selectedDevice: DeviceRecord?
    public private(set) var pairingState: PairingState = .idle

    /// Non-nil while the user is on the code-entry screen after a bad code.
    /// Cleared when re-establish pairing fails (the failure screen takes over)
    /// or when the user starts fresh code entry.
    public private(set) var pairingCodeError: String?

    private let identityProvider: any ClientIdentityProviding
    private let makePairingTransport: @Sendable () -> any RemoteTransport
    private var pairingSession: PairingSession?
    private var headlessTask: Task<HeadlessCommandOutcome, Never>?
    private let headlessWarmWindow: any HeadlessWarmWindowMaintaining
    private let timingRecorder: any CommandTimingRecording
    private let telemetryRecorder: any AppTelemetryRecording

    private enum RemoteAction: Equatable, Sendable {
        case key(RemoteKey, KeyAction)
        case appLink(URL)

        var timingKey: String {
            switch self {
            case let .key(key, _): key.rawValue
            case .appLink: "appLink"
            }
        }

        var telemetryAction: String {
            switch self {
            case .key: "send_key"
            case .appLink: "open_app_link"
            }
        }

        var telemetryMetadata: [String: AppTelemetryValue] {
            switch self {
            case let .key(key, action):
                [
                    "key": .public(key.rawValue),
                    "key_action": .public(String(action.rawValue))
                ]
            case .appLink:
                [
                    "target": .public("app_link")
                ]
            }
        }
    }

    /// Reference flag the inner command body flips when it dials, so the
    /// measurement wrapper can classify WARM vs COLD without changing control
    /// flow. MainActor-isolated, single-threaded use.
    private final class DialFlag {
        var dialed: Bool
        init(_ dialed: Bool) { self.dialed = dialed }
    }

    public init(
        discovery: DeviceDiscovery = DeviceDiscovery(),
        session: RemoteSession = RemoteSession(),
        identityProvider: any ClientIdentityProviding = KeychainClientIdentityStore.shared,
        makePairingTransport: @escaping @Sendable () -> any RemoteTransport = { NetworkRemoteTransport() },
        headlessWarmWindow: any HeadlessWarmWindowMaintaining = NoopHeadlessWarmWindow(),
        timingRecorder: any CommandTimingRecording = CommandTimingRecorder(),
        telemetryRecorder: any AppTelemetryRecording = OSLogAppTelemetryRecorder(category: .command)
    ) {
        self.discovery = discovery
        self.session = session
        self.identityProvider = identityProvider
        self.makePairingTransport = makePairingTransport
        self.headlessWarmWindow = headlessWarmWindow
        self.timingRecorder = timingRecorder
        self.telemetryRecorder = telemetryRecorder
        self.selectedDevice = discovery.devices.first(where: { $0.id == discovery.selectedDeviceID })
            ?? discovery.devices.first
        discovery.selectedDeviceID = selectedDevice?.id
    }

    public func addManualDevice(name: String, host: String) {
        guard let record = discovery.addManualDevice(name: name, host: host) else { return }
        selectedDevice = record
        discovery.selectedDeviceID = record.id
    }

    public func addDiscoveredDevice(_ device: DiscoveredDevice) {
        guard let record = discovery.addDiscoveredDevice(device) else { return }
        selectedDevice = record
        discovery.selectedDeviceID = record.id
    }

    public func select(_ device: DeviceRecord) {
        selectedDevice = device
        discovery.selectedDeviceID = device.id
    }

    public func moveDevices(fromOffsets source: IndexSet, toOffset destination: Int) {
        discovery.moveDevices(fromOffsets: source, toOffset: destination)
    }

    public func deleteDevices(atOffsets offsets: IndexSet) {
        let removed = discovery.deleteDevices(atOffsets: offsets)
        guard removed.contains(where: { $0.id == selectedDevice?.id }) else { return }
        session.disconnect()
        selectedDevice = discovery.devices.first(where: { $0.id == discovery.selectedDeviceID })
            ?? discovery.devices.first
        discovery.selectedDeviceID = selectedDevice?.id
    }

    @discardableResult
    public func recordSuccessfulValidation(from report: ValidationReport) -> PhysicalDeviceValidationRecord? {
        guard let validation = discovery.recordSuccessfulValidation(from: report) else { return nil }
        if selectedDevice?.id == validation.deviceID {
            selectedDevice = discovery.devices.first(where: { $0.id == validation.deviceID }) ?? selectedDevice
        }
        return validation
    }

    public func connectSelectedDevice() async {
        guard let selectedDevice else { return }
        await session.connect(to: selectedDevice)
    }

    public func markConnectionPossiblyStale() {
        session.markConnectionPossiblyStale()
    }

    public func sendKey(
        _ key: RemoteKey,
        action: KeyAction = .tap,
        staleAfter idleTimeout: TimeInterval = 90
    ) async -> HeadlessCommandOutcome {
        await executeRemoteAction(.key(key, action), staleAfter: idleTimeout)
    }

    public func openAppLink(_ url: URL, staleAfter idleTimeout: TimeInterval = 90) async -> HeadlessCommandOutcome {
        await executeRemoteAction(.appLink(url), staleAfter: idleTimeout)
    }

    /// Sends a key without any UI in the loop — the path used by App Intents
    /// fired from the Lock Screen, Control Center, and Siri. Calls are
    /// serialized: rapid taps queue up rather than interleaving their
    /// connect/press/redial sequences and tearing down each other's sockets.
    public func performHeadlessCommand(_ key: RemoteKey) async -> HeadlessCommandOutcome {
        headlessWarmWindow.extend()
        let previous = headlessTask
        let task = Task { () -> HeadlessCommandOutcome in
            _ = await previous?.value
            return await self.executeHeadlessCommand(key)
        }
        headlessTask = task
        return await task.value
    }

    public func extendHeadlessWarmWindow() {
        headlessWarmWindow.extend()
    }

    public func endHeadlessWarmWindow() {
        headlessWarmWindow.end()
    }

    @discardableResult
    public func prepareTextEntry(timeout: Duration = .seconds(2)) async -> TextEntryPreparationResult {
        guard selectedDevice != nil else {
            return .failed("Add or choose a TV before typing.")
        }

        await ensureConnected(staleAfter: 30)
        guard session.connectionState == .connected else {
            return .failed(session.lastError ?? "Connect to the TV before typing.")
        }
        if session.textFieldStatus != nil {
            return .ready
        }

        let searchOutcome = await sendKey(.search)
        guard searchOutcome == .sent else {
            if case let .failed(message) = searchOutcome {
                return .failed(message)
            }
            return .failed(session.lastError ?? "Could not open TV search.")
        }

        if await session.waitForTextFieldStatus(timeout: timeout) {
            return .ready
        }
        return .waitingForFocusedField
    }

    /// Reuses a live session when possible and redials once when a connection
    /// that still claims to be connected turns out dead (typical after the app
    /// spent time suspended in the background).
    private func executeHeadlessCommand(_ key: RemoteKey) async -> HeadlessCommandOutcome {
        await executeRemoteAction(.key(key, .tap), staleAfter: 30)
    }

    /// Measurement wrapper around the command body. When timing is disabled it
    /// calls straight through with zero added work. When enabled it records one
    /// `CommandTiming` per command, classifying WARM vs COLD. It never changes
    /// the command result or control flow.
    private func executeRemoteAction(
        _ action: RemoteAction,
        staleAfter idleTimeout: TimeInterval
    ) async -> HeadlessCommandOutcome {
        let telemetryStart = ContinuousClock.now
        guard timingRecorder.isEnabled else {
            let outcome = await runRemoteAction(action, staleAfter: idleTimeout, dialFlag: nil)
            recordRemoteActionTelemetry(
                action,
                outcome: outcome,
                startedAt: telemetryStart,
                dialed: nil
            )
            return outcome
        }

        let willDial = selectedDevice.map {
            session.needsConnectionRefresh(for: $0, idleTimeout: idleTimeout)
        } ?? true
        let flag = DialFlag(willDial)
        let startedAt = Date()
        let clockStart = ContinuousClock.now

        let outcome = await runRemoteAction(action, staleAfter: idleTimeout, dialFlag: flag)

        let totalMs = clockStart.duration(to: .now).millisecondsValue
        timingRecorder.record(
            CommandTiming(
                key: action.timingKey,
                startedAt: startedAt,
                totalMs: totalMs,
                dialed: flag.dialed,
                tcpTlsMs: flag.dialed ? session.lastTCPTLSMilliseconds : nil,
                configureMs: flag.dialed ? session.lastConfigureMilliseconds : nil,
                processAgeMs: ProcessClock.ageMilliseconds,
                succeeded: outcome == .sent
            )
        )
        recordRemoteActionTelemetry(
            action,
            outcome: outcome,
            startedAt: telemetryStart,
            dialed: flag.dialed
        )
        return outcome
    }

    private func recordRemoteActionTelemetry(
        _ action: RemoteAction,
        outcome: HeadlessCommandOutcome,
        startedAt: ContinuousClock.Instant,
        dialed: Bool?
    ) {
        var metadata = action.telemetryMetadata
        if let dialed {
            metadata["dialed"] = .public(dialed ? "true" : "false")
        }
        telemetryRecorder.record(
            AppTelemetryEvent(
                category: .command,
                action: action.telemetryAction,
                outcome: outcome == .sent ? .succeeded : .failed,
                durationMilliseconds: startedAt.duration(to: .now).millisecondsValue,
                metadata: metadata
            )
        )
    }

    /// Ensures a fresh connection, sends once, then redials and retries once
    /// when a connected-looking session fails during the send. The retry limit
    /// prevents Lock Screen / Control Center commands from looping forever
    /// against a TV that is asleep or on another network.
    private func runRemoteAction(
        _ action: RemoteAction,
        staleAfter idleTimeout: TimeInterval,
        dialFlag: DialFlag?
    ) async -> HeadlessCommandOutcome {
        guard let selectedDevice, selectedDevice.isPaired else {
            return .failed("Open Pult and pair a TV first.")
        }

        await ensureFreshConnection(staleAfter: idleTimeout)
        var attemptedSend = false
        if session.connectionState == .connected {
            attemptedSend = true
            let sent = await send(action)
            if sent, session.connectionState == .connected {
                return .sent
            }
        }

        guard attemptedSend else {
            return .failed("Could not reach \(selectedDevice.name).")
        }

        // Fresh dial: the press above killed a stale connection.
        //
        // A send that fails on a dead socket almost certainly never reached the
        // TV, so resending on the fresh connection is safe for the common case.
        // In the rare window where delivery succeeded but the read loop flagged
        // death concurrently, a duplicated d-pad/volume key is harmless.
        await session.connect(to: selectedDevice)
        dialFlag?.dialed = true
        guard session.connectionState == .connected else {
            return .failed("Could not reach \(selectedDevice.name).")
        }
        let sent = await send(action)
        guard sent, session.connectionState == .connected else {
            return .failed("Lost the connection to \(selectedDevice.name).")
        }
        return .sent
    }

    /// Connects the selected device when needed: a no-op when the session is
    /// already connected to it within the requested freshness window, and
    /// never dials an unpaired device, whose mutual-TLS connection the TV
    /// would reject.
    public func ensureConnected(staleAfter idleTimeout: TimeInterval = .infinity) async {
        guard let selectedDevice, selectedDevice.isPaired else { return }
        if !session.needsConnectionRefresh(for: selectedDevice, idleTimeout: idleTimeout) {
            return
        }
        await session.connect(to: selectedDevice)
    }

    @discardableResult
    public func ensureFreshConnection(staleAfter idleTimeout: TimeInterval = 90) async -> Bool {
        guard let selectedDevice, selectedDevice.isPaired else { return false }
        await ensureConnected(staleAfter: idleTimeout)
        return session.connectionState == .connected
    }

    public func beginPairing() async {
        guard let selectedDevice else { return }
        let telemetryStart = ContinuousClock.now
        recordPairingTelemetry(
            action: "begin",
            outcome: .started,
            startedAt: telemetryStart
        )
        await pairingSession?.cancel()
        pairingCodeError = nil
        pairingState = .connecting
        let pairing = PairingSession(transport: makePairingTransport())
        pairingSession = pairing

        do {
            let provider = identityProvider
            // Key generation on first run is slow; keep it off the main actor.
            let parameters = try await Task.detached {
                try provider.publicKeyParameters()
            }.value
            try await pairing.start(for: selectedDevice, clientParameters: parameters)
            pairingState = .waitingForCode
            recordPairingTelemetry(
                action: "begin",
                outcome: .succeeded,
                startedAt: telemetryStart,
                metadata: ["phase": .public("waiting_for_code")]
            )
        } catch {
            pairingState = .failed(Self.describe(error))
            await pairing.cancel()
            recordPairingTelemetry(
                action: "begin",
                outcome: .failed,
                startedAt: telemetryStart,
                metadata: ["reason": .public(Self.telemetryReason(for: error))]
            )
        }
    }

    public func submitPairingCode(_ rawCode: String) async {
        // Only one submission per code-entry phase; re-entry (double-tap,
        // duplicated UI callbacks) would re-run the handshake on a transport
        // the first submission already consumed.
        guard let pairing = pairingSession, pairingState == .waitingForCode else { return }
        guard let code = PairingCode(rawValue: rawCode) else {
            pairingState = .failed("Enter the \(PairingCode.length)-character code shown on the TV.")
            recordPairingTelemetry(
                action: "submit_code",
                outcome: .failed,
                startedAt: ContinuousClock.now,
                metadata: ["reason": .public("invalid_format")]
            )
            return
        }

        let telemetryStart = ContinuousClock.now
        pairingState = .verifying
        do {
            try await pairing.submit(code: code)
            pairingState = .paired
            pairingCodeError = nil
            if let selectedDevice {
                discovery.markPaired(selectedDevice)
                self.selectedDevice = discovery.devices.first(where: { $0.id == selectedDevice.id }) ?? selectedDevice
            }
            recordPairingTelemetry(
                action: "submit_code",
                outcome: .succeeded,
                startedAt: telemetryStart
            )
        } catch {
            await pairing.cancel()
            if Self.isBadCodeError(error) {
                // The TV aborted the session and will now show a fresh code.
                // Stay in the code-entry experience: show an inline error and
                // transparently re-establish pairing so the new code is live.
                let inlineMessage = "Incorrect code — enter the new code shown on your TV."
                await beginPairing()
                // beginPairing() either landed in .waitingForCode (success) or
                // .failed (TV unreachable). Only surface the inline error in the
                // success case; the failure screen handles the rest.
                if pairingState == .waitingForCode {
                    pairingCodeError = inlineMessage
                } else {
                    pairingCodeError = nil
                }
            } else {
                pairingCodeError = nil
                pairingState = .failed(Self.describe(error))
            }
            recordPairingTelemetry(
                action: "submit_code",
                outcome: .failed,
                startedAt: telemetryStart,
                metadata: ["reason": .public(Self.telemetryReason(for: error))]
            )
        }
    }

    private func recordPairingTelemetry(
        action: String,
        outcome: AppTelemetryOutcome,
        startedAt: ContinuousClock.Instant,
        metadata: [String: AppTelemetryValue] = [:]
    ) {
        telemetryRecorder.record(
            AppTelemetryEvent(
                category: .pairing,
                action: action,
                outcome: outcome,
                durationMilliseconds: startedAt.duration(to: .now).millisecondsValue,
                metadata: metadata
            )
        )
    }

    /// Returns true for errors that mean the user entered the wrong code and
    /// the TV has aborted the session. Both cases are recoverable by starting
    /// a fresh pairing session.
    ///
    /// - `PairingSecretError.checkByteMismatch`: local validation — the first
    ///   two hex digits of the entered code must equal the first byte of the
    ///   SHA-256 secret; if they don't, the code is obviously wrong and nothing
    ///   was sent to the TV.
    /// - `PairingSessionError.rejected(.badSecret)`: the TV received the secret
    ///   and returned status 402, meaning it considers the code wrong. The TV
    ///   will abort and display a new code.
    private static func isBadCodeError(_ error: Error) -> Bool {
        switch error {
        case PairingSecretError.checkByteMismatch:
            return true
        case PairingSessionError.rejected(let status) where status == .badSecret:
            return true
        default:
            return false
        }
    }

    public func cancelPairing() async {
        await pairingSession?.cancel()
        pairingSession = nil
        pairingState = .idle
        pairingCodeError = nil
    }

    /// Clears the inline bad-code error message, called when the user starts
    /// editing a new code after a wrong-code rejection.
    public func clearPairingCodeError() {
        pairingCodeError = nil
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case PairingSecretError.checkByteMismatch:
            "That code doesn't match what the TV expected. Check the code on screen and pair again."
        case let PairingSessionError.rejected(status):
            status == .badSecret
                ? "The TV rejected the code. Start pairing again and retype the code."
                : "The TV rejected the pairing request."
        case PairingSessionError.missingPeerCertificate:
            "The TV's certificate was not available. Reconnect and try again."
        case RemoteTransportError.connectionFailed:
            "Could not reach the TV's pairing service. Make sure the TV is on and on the same network."
        case let RemoteTransportError.connectionFailedWithReason(reason):
            "Could not reach the TV's pairing service. \(reason)"
        default:
            error.localizedDescription
        }
    }

    private static func telemetryReason(for error: Error) -> String {
        switch error {
        case PairingSecretError.checkByteMismatch:
            "bad_code"
        case PairingSessionError.rejected(let status) where status == .badSecret:
            "bad_code"
        case PairingSessionError.rejected:
            "rejected"
        case PairingSessionError.missingPeerCertificate:
            "missing_peer_certificate"
        case RemoteTransportError.connectionFailed, RemoteTransportError.connectionFailedWithReason:
            "transport_failed"
        default:
            "unknown"
        }
    }

    private func send(_ action: RemoteAction) async -> Bool {
        switch action {
        case let .key(key, keyAction):
            await session.sendKey(key, action: keyAction)
        case let .appLink(url):
            await session.openAppLink(url)
        }
    }
}
