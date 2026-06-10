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

    private let identityProvider: any ClientIdentityProviding
    private let makePairingTransport: @Sendable () -> any RemoteTransport
    private var pairingSession: PairingSession?
    private var headlessTask: Task<HeadlessCommandOutcome, Never>?

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

    public func select(_ device: DeviceRecord) {
        selectedDevice = device
        discovery.selectedDeviceID = device.id
    }

    public func connectSelectedDevice() async {
        guard let selectedDevice else { return }
        await session.connect(to: selectedDevice)
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
        guard let selectedDevice, selectedDevice.isPaired else {
            return .failed("Open Pult and pair a TV first.")
        }

        await ensureConnected()
        if session.connectionState == .connected {
            await session.press(key)
            if session.connectionState == .connected {
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
        await session.press(key)
        guard session.connectionState == .connected else {
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

    public func beginPairing() async {
        guard let selectedDevice else { return }
        await pairingSession?.cancel()

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
            if let selectedDevice {
                discovery.markPaired(selectedDevice)
                self.selectedDevice = discovery.devices.first(where: { $0.id == selectedDevice.id }) ?? selectedDevice
            }
        } catch {
            pairingState = .failed(Self.describe(error))
            await pairing.cancel()
        }
    }

    public func cancelPairing() async {
        await pairingSession?.cancel()
        pairingSession = nil
        pairingState = .idle
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
}
