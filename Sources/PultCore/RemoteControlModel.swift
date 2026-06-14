import Foundation
import Observation

public enum HeadlessCommandOutcome: Equatable, Sendable {
    case sent
    case failed(String)
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

    private enum RemoteAction: Equatable, Sendable {
        case key(RemoteKey, KeyAction)
        case appLink(URL)
    }

    public init(
        discovery: DeviceDiscovery = DeviceDiscovery(),
        session: RemoteSession = RemoteSession(),
        identityProvider: any ClientIdentityProviding = KeychainClientIdentityStore.shared,
        makePairingTransport: @escaping @Sendable () -> any RemoteTransport = { NetworkRemoteTransport() }
    ) {
        self.discovery = discovery
        self.session = session
        self.identityProvider = identityProvider
        self.makePairingTransport = makePairingTransport
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
        let previous = headlessTask
        let task = Task { () -> HeadlessCommandOutcome in
            _ = await previous?.value
            return await self.executeHeadlessCommand(key)
        }
        headlessTask = task
        return await task.value
    }

    /// Reuses a live session when possible and redials once when a connection
    /// that still claims to be connected turns out dead (typical after the app
    /// spent time suspended in the background).
    private func executeHeadlessCommand(_ key: RemoteKey) async -> HeadlessCommandOutcome {
        await executeRemoteAction(.key(key, .tap), staleAfter: 30)
    }

    /// Ensures a fresh connection, sends once, then redials and retries once
    /// when a connected-looking session fails during the send. The retry limit
    /// prevents Lock Screen / Control Center commands from looping forever
    /// against a TV that is asleep or on another network.
    private func executeRemoteAction(
        _ action: RemoteAction,
        staleAfter idleTimeout: TimeInterval
    ) async -> HeadlessCommandOutcome {
        guard let selectedDevice, selectedDevice.isPaired else {
            return .failed("Open Pult and pair a TV first.")
        }

        await ensureFreshConnection(staleAfter: idleTimeout)
        if session.connectionState == .connected {
            let sent = await send(action)
            if sent, session.connectionState == .connected {
                return .sent
            }
        }

        // Fresh dial: either the first connect failed outright, or the press
        // above killed a stale connection.
        //
        // A send that fails on a dead socket almost certainly never reached the
        // TV, so resending on the fresh connection is safe for the common case.
        // In the rare window where delivery succeeded but the read loop flagged
        // death concurrently, a duplicated d-pad/volume key is harmless.
        await session.connect(to: selectedDevice)
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
    /// already connected to it, and never dials an unpaired device, whose
    /// mutual-TLS connection the TV would reject.
    public func ensureConnected() async {
        guard let selectedDevice, selectedDevice.isPaired else { return }
        if session.connectionState == .connected, session.device?.id == selectedDevice.id {
            return
        }
        await session.connect(to: selectedDevice)
    }

    @discardableResult
    public func ensureFreshConnection(staleAfter idleTimeout: TimeInterval = 90) async -> Bool {
        guard let selectedDevice, selectedDevice.isPaired else { return false }
        if !session.needsConnectionRefresh(for: selectedDevice, idleTimeout: idleTimeout) {
            return true
        }
        await session.connect(to: selectedDevice)
        return session.connectionState == .connected
    }

    public func beginPairing() async {
        guard let selectedDevice else { return }
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
        } catch {
            pairingState = .failed(Self.describe(error))
            await pairing.cancel()
        }
    }

    public func submitPairingCode(_ rawCode: String) async {
        // Only one submission per code-entry phase; re-entry (double-tap,
        // duplicated UI callbacks) would re-run the handshake on a transport
        // the first submission already consumed.
        guard let pairing = pairingSession, pairingState == .waitingForCode else { return }
        guard let code = PairingCode(rawValue: rawCode) else {
            pairingState = .failed("Enter the \(PairingCode.length)-character code shown on the TV.")
            return
        }

        pairingState = .verifying
        do {
            try await pairing.submit(code: code)
            pairingState = .paired
            pairingCodeError = nil
            if let selectedDevice {
                discovery.markPaired(selectedDevice)
                self.selectedDevice = discovery.devices.first(where: { $0.id == selectedDevice.id }) ?? selectedDevice
            }
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
        }
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
        default:
            error.localizedDescription
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
