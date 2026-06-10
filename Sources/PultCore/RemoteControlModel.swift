import Foundation
import Observation

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
