import Foundation
import SwiftUI
import PultCore
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
                tone: .error
            )
        }
    }

    private var scanButtonTitle: String {
        if isScanning {
            return "Scanning"
        }
        return hasStartedScan ? "Retry Scan" : "Scan Nearby TVs"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PultSheetHero(
                        systemImage: "tv.and.mediabox",
                        title: "Add a Google TV",
                        subtitle: "Scan nearby devices first, then fall back to a host or IP address when the network is quiet."
                    )
                    nearbySection
                    manualIPSection
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .background { RemoteBackground() }
            .navigationTitle("Add TV")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
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

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PultSheetSectionHeader(
                title: "Nearby TVs",
                detail: "Bonjour discovery probes the command port as devices appear."
            )
            DiscoveryStatusRow(status: discoveryStatus)

            ForEach(model.discovery.discoveredDevices) { device in
                let savedDevice = savedRecord(for: device)
                let readiness = readiness(for: device, savedDevice: savedDevice)
                Button {
                    addDiscoveredDevice(device)
                } label: {
                    DiscoveredDeviceRow(
                        device: device,
                        readiness: readiness
                    )
                    .padding(12)
                    .pultContentSurface(
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                        tint: readiness.color
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(readiness.actionHint)
            }

            DiscoveryActionRow(
                scanTitle: scanButtonTitle,
                isScanning: isScanning,
                startScan: startScan,
                focusManualIP: focusManualIP
            )

            Text("If a TV disappears from discovery, Manual IP is the reliable fallback.")
                .font(PultTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .pultContentSurface(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            tint: .pultAccent,
            isProminent: true
        )
    }

    private var manualIPSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PultSheetSectionHeader(
                title: "Manual IP",
                detail: "Use this for routers, sleeping TVs, or Local Network permission gaps."
            )
            ManualIPGuidanceRow()

            textFieldRow(systemImage: "tv") {
                TextField("Living Room TV", text: $name)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .host }
                    .accessibilityLabel("TV name")
                    .accessibilityHint("Optional. Leave blank to use the host as the device name.")
            }

            textFieldRow(systemImage: "network") {
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

            if let feedback = hostValidation.feedback {
                Label(feedback.message, systemImage: feedback.systemImage)
                    .font(PultTypography.captionStrong)
                    .foregroundStyle(feedback.color)
                    .lineLimit(2)
            }

            Button("Add TV", systemImage: "plus", action: addDevice)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 48)
                .disabled(!canAddDevice)
                .accessibilityHint(addButtonAccessibilityHint)

            Text("Find the TV's IP address under Settings > Network & Internet on the TV. Local hostnames like Android.local are also OK when your router resolves them.")
                .font(PultTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(16)
        .pultContentSurface(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            isProminent: true
        )
    }

    private func textFieldRow<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            content()
                .font(PultTypography.body)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PultDesign.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PultDesign.hairline, lineWidth: 1)
        }
    }

    private var appSettingsAction: (() -> Void)? {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return nil }
        return { _ = openURL(url) }
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
        dismiss()
    }

    private func addDiscoveredDevice(_ device: DiscoveredDevice) {
        model.addDiscoveredDevice(device)
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
            case .success: .green
            case .warning: PultDesign.warning
            case .error: .red
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
        color: .green
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
        color: .green
    )

    static func unavailable(_ message: String) -> Self {
        Self(
            title: "Unavailable",
            detail: message,
            systemImage: "exclamationmark.triangle.fill",
            color: .red
        )
    }
}

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

private struct DiscoveryActionRow: View {
    let scanTitle: String
    let isScanning: Bool
    var startScan: () -> Void
    var focusManualIP: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                scanButton
                manualIPButton
            }

            VStack(alignment: .leading, spacing: 8) {
                scanButton
                manualIPButton
            }
        }
    }

    private var scanButton: some View {
        Button(scanTitle, systemImage: isScanning ? "antenna.radiowaves.left.and.right" : "arrow.clockwise") {
            startScan()
        }
        .buttonStyle(.glassProminent)
        .controlSize(.regular)
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(isScanning)
        .accessibilityHint(isScanning ? "A local network scan is already running." : "Search again for nearby Google TVs.")
    }

    private var manualIPButton: some View {
        Button("Enter IP", systemImage: "keyboard") {
            focusManualIP()
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityHint("Moves focus to manual address entry.")
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
                Button("Open Settings", systemImage: "gear") {
                    openSettings()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityHint("Opens Pult in iOS Settings so you can turn on Local Network access.")
            }
        }
        .accessibilityElement(children: status.openSettingsAction == nil ? .combine : .contain)
    }
}

private struct ManualIPGuidanceRow: View {
    var body: some View {
        Label {
            Text("On the TV, open Settings > Network & Internet and enter the active network IP address here. Local hostnames like Android.local are also OK when your router resolves them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.pultAccent)
        }
        .accessibilityElement(children: .combine)
    }
}
