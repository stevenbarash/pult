import SwiftUI
import PultCore

struct RemoteRootView: View {
    @Bindable var model: RemoteControlModel
    @State private var presentedSheet: RemoteSheet?

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { RemoteBackground() }
                .navigationTitle(model.selectedDevice?.name ?? "Pult")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbarTitleMenu { deviceMenu }
                .toolbar {
                    if let device = model.selectedDevice {
                        ToolbarItem(placement: .primaryAction) {
                            ConnectionStatusControl(
                                state: model.session.connectionState,
                                isPaired: device.isPaired,
                                onConnect: connectSelectedDevice,
                                onPair: presentPairing
                            )
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .task(id: model.selectedDevice?.id) {
            await autoConnectIfNeeded()
        }
        .sheet(item: $presentedSheet, onDismiss: {
            // Pairing marks the device as paired; pick up the connection
            // without requiring a manual connect tap.
            Task { await autoConnectIfNeeded() }
        }, content: sheetContent)
    }

    @ViewBuilder
    private var content: some View {
        if model.discovery.devices.isEmpty {
            ContentUnavailableView {
                Label("No TV Added", systemImage: "tv.slash")
            } description: {
                Text("Add your Google TV's IP address to start controlling it from this phone.")
            } actions: {
                Button("Add TV", systemImage: "plus", action: presentAddDevice)
                    .buttonStyle(.glassProminent)
            }
        } else {
            RemoteControlSurface(
                connectionState: model.session.connectionState,
                isPaired: model.selectedDevice?.isPaired ?? false,
                send: send,
                onTextEntry: presentTextEntry,
                onRetryConnect: connectSelectedDevice,
                onPair: presentPairing
            )
        }
    }

    @ViewBuilder
    private var deviceMenu: some View {
        Picker("TV", selection: deviceSelection) {
            ForEach(model.discovery.devices) { device in
                Label(device.name, systemImage: device.isPaired ? "tv" : "tv.slash")
                    .tag(device.id as UUID?)
            }
        }
        if model.selectedDevice != nil {
            Button("Pair Again…", systemImage: "link", action: presentPairing)
        }
        Button("Add TV…", systemImage: "plus", action: presentAddDevice)
    }

    private var deviceSelection: Binding<UUID?> {
        Binding(
            get: { model.selectedDevice?.id },
            set: { id in
                if let device = model.discovery.devices.first(where: { $0.id == id }) {
                    model.select(device)
                }
            }
        )
    }

    private enum RemoteSheet: Identifiable {
        case addDevice
        case textEntry
        case pairing

        var id: Self { self }
    }

    @ViewBuilder
    private func sheetContent(for sheet: RemoteSheet) -> some View {
        switch sheet {
        case .addDevice:
            AddDeviceView(model: model)
                .presentationDetents([.medium])
        case .textEntry:
            TextEntryView(onSubmit: sendText)
                .presentationDetents([.medium])
        case .pairing:
            PairingView(model: model)
                .presentationDetents([.medium, .large])
        }
    }

    private func presentAddDevice() {
        presentedSheet = .addDevice
    }

    private func presentTextEntry() {
        presentedSheet = .textEntry
    }

    private func presentPairing() {
        presentedSheet = .pairing
    }

    private func connectSelectedDevice() {
        Task { await model.connectSelectedDevice() }
    }

    private func send(_ key: RemoteKey) {
        Task { await model.session.press(key) }
    }

    private func sendText(_ text: String) {
        Task { await model.session.sendText(text) }
    }

    @MainActor
    private func autoConnectIfNeeded() async {
        await model.ensureConnected()
        #if canImport(ActivityKit) && os(iOS)
        if let device = model.selectedDevice, model.session.connectionState == .connected {
            await RemoteActivityController.shared.startOrUpdate(for: device, state: .connected)
        }
        #endif
    }
}

/// Toolbar capsule showing connection state. For an unpaired TV it offers
/// pairing (connecting would be rejected); otherwise tapping it (re)connects
/// when the session is offline, and it is inert while connecting or connected.
private struct ConnectionStatusControl: View {
    let state: ConnectionState
    let isPaired: Bool
    let onConnect: () -> Void
    let onPair: () -> Void

    private var label: String {
        if !isPaired {
            return state == .connecting ? "Connecting" : "Pair"
        }
        switch state {
        case .disconnected: return "Connect"
        case .connecting: return "Connecting"
        case .connected: return "Online"
        case .failed: return "Retry"
        }
    }

    private var color: Color {
        if !isPaired, state != .connecting {
            return .orange
        }
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    private var isActionable: Bool {
        switch state {
        case .disconnected, .failed: true
        case .connecting, .connected: false
        }
    }

    var body: some View {
        Button(action: isPaired ? onConnect : onPair) {
            HStack(spacing: 6) {
                if state == .connecting {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 4)
        }
        .disabled(!isActionable)
        .animation(.smooth(duration: 0.3), value: state)
        .accessibilityLabel(isPaired ? "Connection: \(label)" : "Pair with TV")
    }
}
