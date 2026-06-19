import Foundation
import SwiftUI
import PultCore
#if canImport(PostHog)
import PostHog
#endif
#if os(iOS)
import UIKit
#endif

struct AddDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Bindable var model: RemoteControlModel
    @State private var name = ""
    @State private var host = ""
    @State private var hasStartedScan = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case host
    }

    private var hostValidation: HostInputValidation {
        HostInputValidation(rawValue: host)
    }

    private var canAddDevice: Bool {
        hostValidation.isValid
    }

    private var isScanning: Bool {
        model.discovery.discoveryState == .scanning
    }

    private var discoveryStatus: DiscoveryStatusPresentation {
        switch model.discovery.discoveryState {
        case .idle:
            if model.discovery.discoveredDevices.isEmpty {
                DiscoveryStatusPresentation(
                    title: hasStartedScan ? "Ready to scan again" : "Find nearby TVs",
                    message: "Automatic discovery uses Local Network access. Allow it when iOS asks, or add the TV by IP address below.",
                    systemImage: "network",
                    tone: .neutral
                )
            } else {
                DiscoveryStatusPresentation(
                    title: "Scan complete",
                    message: "Tap a TV below to add it. If the right device is missing, enter its IP address manually.",
                    systemImage: "checkmark.circle",
                    tone: .success
                )
            }
        case .scanning:
            DiscoveryStatusPresentation(
                title: model.discovery.discoveredDevices.isEmpty ? "Looking for Google TVs" : "Still scanning",
                message: model.discovery.discoveredDevices.isEmpty
                    ? "Keep the TV awake and on the same Wi-Fi network."
                    : "Tap a TV below, or keep scanning for another device.",
                systemImage: "dot.radiowaves.left.and.right",
                tone: .neutral,
                isScanning: true
            )
        case .manualOnly:
            DiscoveryStatusPresentation(
                title: "No nearby TVs found",
                message: "Two common causes: Local Network permission is off (if you tapped Don't Allow, Pult can't see your TV), or the TV is asleep or on a different Wi-Fi network.",
                systemImage: "exclamationmark.magnifyingglass",
                tone: .warning,
                openSettingsAction: appSettingsAction
            )
        case let .failed(message):
            DiscoveryStatusPresentation(
                title: "Scan unavailable",
                message: "\(message) Check Local Network access in Settings if this keeps happening, or add the TV by IP address below.",
                systemImage: "exclamationmark.triangle",
                tone: .error,
                openSettingsAction: appSettingsAction
            )
        }
    }

    private var scanButtonTitle: String {
        if isScanning {
            return "Scanning…"
        }
        return hasStartedScan ? "Retry Scan" : "Scan Nearby TVs"
    }

    var body: some View {
        NavigationStack {
            List {
                nearbySection
                manualIPSection
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .background { RemoteBackground() }
            .navigationTitle("Add TV")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addDevice)
                        .disabled(!canAddDevice)
                        .accessibilityHint(addButtonAccessibilityHint)
                }
            }
            .onDisappear { model.discovery.stopScanning() }
            .task {
                await startScanIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Nearby Section

    @ViewBuilder
    private var nearbySection: some View {
        Section {
            // Discovery status row
            DiscoveryStatusRow(status: discoveryStatus)

            // Discovered devices
            ForEach(model.discovery.discoveredDevices) { device in
                let savedDevice = savedRecord(for: device)
                let readiness = readiness(for: device, savedDevice: savedDevice)
                Button {
                    addDiscoveredDevice(device)
                } label: {
                    DiscoveredDeviceRow(device: device, readiness: readiness)
                }
                .accessibilityHint(readiness.actionHint)
            }

            // Scan action buttons
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    scanButton
                    enterIPButton
                }

                VStack(spacing: 10) {
                    scanButton
                    enterIPButton
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        } header: {
            Text("Nearby TVs")
        } footer: {
            Text("If a TV disappears from discovery, Manual IP below is the reliable fallback.")
        }
    }

    private var scanButton: some View {
        Button {
            startScan()
        } label: {
            Label(scanButtonTitle,
                  systemImage: isScanning ? "antenna.radiowaves.left.and.right" : "arrow.clockwise")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isScanning)
        .accessibilityHint(isScanning ? "A local network scan is already running." : "Search again for nearby Google TVs.")
    }

    private var enterIPButton: some View {
        Button {
            focusManualIP()
        } label: {
            Label("Enter IP", systemImage: "keyboard")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Moves focus to manual address entry.")
    }

    // MARK: - Manual IP Section

    @ViewBuilder
    private var manualIPSection: some View {
        Section {
            // Name field
            HStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                TextField("Living Room TV", text: $name)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .host }
                    .accessibilityLabel("TV name")
                    .accessibilityHint("Optional. Leave blank to use the host as the device name.")
            }
            .frame(minHeight: 44)

            // Host field
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                TextField("192.168.1.42", text: $host)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .textContentType(.URL)
                    #endif
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .host)
                    .submitLabel(.done)
                    .onSubmit(addDeviceIfPossible)
                    .accessibilityLabel("IP address or hostname")
                    .accessibilityHint("Enter the TV address, such as 192.168.1.42 or Android.local.")
            }
            .frame(minHeight: 44)

            // Inline validation feedback
            if let feedback = hostValidation.feedback {
                Label(feedback.message, systemImage: feedback.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(feedback.color)
                    .lineLimit(2)
                    .listRowBackground(Color.clear)
            }

            // Add TV primary button
            Button(action: addDevice) {
                Label("Add TV", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAddDevice)
            .accessibilityHint(addButtonAccessibilityHint)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("Manual IP")
        } footer: {
            Text("Find the TV's IP address under Settings > Network & Internet on the TV. Local hostnames like Android.local are also OK when your router resolves them.")
        }
    }

    // MARK: - Helpers

    private var appSettingsAction: (() -> Void)? {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return nil }
        returnpo { _ = openURL(url) }
        #else
        return nil
        #endif
    }

    private var addButtonAccessibilityHint: String {
        guard canAddDevice else {
            return "Enter an IP address or local hostname first."
        }
        return "Adds \(hostValidation.normalizedHost) and selects it for pairing."
    }

    private func addDeviceIfPossible() {
        if canAddDevice {
            addDevice()
        }
    }

    private func addDevice() {
        model.addManualDevice(name: name, host: hostValidation.normalizedHost)
        #if canImport(PostHog)
        PostHogSDK.shared.capture("tv_added", properties: [
            "method": "manual",
        ])
        #endif
        dismiss()
    }

    private func addDiscoveredDevice(_ device: DiscoveredDevice) {
        model.addDiscoveredDevice(device)
        #if canImport(PostHog)
        PostHogSDK.shared.capture("tv_added", properties: [
            "method": "discovery",
        ])
        #endif
        dismiss()
    }

    private func savedRecord(for device: DiscoveredDevice) -> DeviceRecord? {
        model.discovery.devices.first {
            $0.host.caseInsensitiveCompare(device.host) == .orderedSame
                && $0.commandPort == device.commandPort
        }
    }

    private func readiness(for device: DiscoveredDevice, savedDevice: DeviceRecord?) -> DeviceReadinessPresentation {
        if savedDevice?.isPaired == true {
            return .paired
        }

        let reachability = model.discovery.reachability(for: device)
        if savedDevice != nil, reachability.isReachable {
            return .pairingRequired
        }

        switch reachability {
        case .unknown:
            return savedDevice == nil ? .found : .pairingRequired
        case .checking:
            return .checking
        case .reachable:
            return .reachable
        case let .unreachable(message, _):
            return .unavailable(message)
        }
    }

    private func startScan() {
        hasStartedScan = true
        Task { await model.discovery.refresh() }
    }

    private func focusManualIP() {
        focusedField = .host
    }

    private func startScanIfNeeded() async {
        guard !hasStartedScan else { return }
        hasStartedScan = true
        await model.discovery.refresh()
    }
}

// MARK: - Supporting types (unchanged logic)

private struct HostInputValidation {
    var normalizedHost: String
    var feedback: HostInputFeedback?

    var isValid: Bool {
        feedback?.isBlocking != true && !normalizedHost.isEmpty
    }

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalizedHost(from: trimmed)
        normalizedHost = normalized

        if trimmed.isEmpty {
            feedback = nil
        } else if normalized.isEmpty
            || normalized.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            || normalized.contains("/") {
            feedback = .error("Use an IP address or local hostname without spaces.")
        } else if normalized != trimmed {
            feedback = .info("The app will connect to \(normalized).")
        } else {
            feedback = nil
        }
    }

    private static func normalizedHost(from value: String) -> String {
        guard !value.isEmpty else { return "" }
        let candidate = value.contains("://") ? value : "http://\(value)"

        if let components = URLComponents(string: candidate),
           let host = components.host,
           !host.isEmpty {
            return host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }

        if value.contains("://") {
            return ""
        }

        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct HostInputFeedback {
    var message: String
    var systemImage: String
    var color: Color
    var isBlocking: Bool

    static func info(_ message: String) -> Self {
        Self(message: message, systemImage: "checkmark.circle", color: .secondary, isBlocking: false)
    }

    static func error(_ message: String) -> Self {
        Self(message: message, systemImage: "exclamationmark.triangle", color: PultDesign.warning, isBlocking: true)
    }
}

private struct DiscoveryStatusPresentation {
    enum Tone {
        case neutral
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .neutral: .secondary
            case .success: PultDesign.connected
            case .warning: PultDesign.warning
            case .error: PultDesign.danger
            }
        }
    }

    var title: String
    var message: String
    var systemImage: String
    var tone: Tone
    var isScanning = false
    var openSettingsAction: (() -> Void)? = nil
}

private struct DeviceReadinessPresentation {
    var title: String
    var detail: String?
    var systemImage: String
    var color: Color
    var isChecking = false

    var actionHint: String {
        if title == Self.paired.title {
            return "Adds and selects this already paired TV."
        } else if title == Self.pairingRequired.title {
            return "Selects this TV so you can pair it again if needed."
        } else if title == Self.reachable.title {
            return "Adds and selects this reachable TV for pairing."
        } else if title == Self.checking.title {
            return "Adds and selects this TV while reachability is still being checked."
        } else if title == Self.found.title {
            return "Adds and selects this TV. Pult will pair before sending commands."
        } else {
            return "Adds this TV anyway. If pairing cannot reach it, use Manual IP."
        }
    }

    static let found = Self(
        title: "Found",
        detail: nil,
        systemImage: "dot.radiowaves.left.and.right",
        color: .secondary
    )

    static let checking = Self(
        title: "Checking",
        detail: nil,
        systemImage: "clock.arrow.circlepath",
        color: PultDesign.warning,
        isChecking: true
    )

    static let reachable = Self(
        title: "Reachable",
        detail: nil,
        systemImage: "checkmark.circle.fill",
        color: PultDesign.connected
    )

    static let pairingRequired = Self(
        title: "Pairing Required",
        detail: nil,
        systemImage: "link.badge.plus",
        color: PultDesign.warning
    )

    static let paired = Self(
        title: "Paired",
        detail: nil,
        systemImage: "checkmark.seal.fill",
        color: PultDesign.connected
    )

    static func unavailable(_ message: String) -> Self {
        Self(
            title: "Unavailable",
            detail: message,
            systemImage: "exclamationmark.triangle.fill",
            color: PultDesign.danger
        )
    }
}

// MARK: - Row Views

private struct DiscoveredDeviceRow: View {
    let device: DiscoveredDevice
    let readiness: DeviceReadinessPresentation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv.badge.wifi")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(device.host):\(device.commandPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = readiness.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                if readiness.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: readiness.systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(readiness.title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(readiness.color)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [
            device.name,
            "\(device.host), port \(device.commandPort)",
            readiness.title
        ]
        if let detail = readiness.detail {
            parts.append(detail)
        }
        return parts.joined(separator: ", ")
    }
}

private struct DiscoveryStatusRow: View {
    let status: DiscoveryStatusPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if status.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 2)
                } else {
                    Image(systemName: status.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(status.tone.color)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(status.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let openSettings = status.openSettingsAction {
                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens Pult in iOS Settings so you can turn on Local Network access.")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: status.openSettingsAction == nil ? .combine : .contain)
    }
}
