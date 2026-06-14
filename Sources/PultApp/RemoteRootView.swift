import Foundation
import SwiftUI
import PultCore

struct RemoteRootView: View {
    @Bindable var model: RemoteControlModel
    @State private var presentedSheet: RemoteSheet?
    @State private var selectedValidationClaimState: DeviceValidationClaimState = .unvalidated
    @State private var lastCommandFailure: RemoteCommandFailure?
    @State private var lastCommandKey: RemoteKey?

    private let validationReportStore = UserDefaultsValidationReportStore()

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
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Command", systemImage: "command") {
                            presentCommandPalette()
                        }
                        .keyboardShortcut("k", modifiers: [.command])
                        .accessibilityHint("Search Pult actions and remote commands.")
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button("Command", systemImage: "command") {
                            presentCommandPalette()
                        }
                        .keyboardShortcut("k", modifiers: [.command])
                        .accessibilityHint("Search Pult actions and remote commands.")
                    }
                    #endif
                    if let device = model.selectedDevice {
                        ToolbarItem(placement: .primaryAction) {
                            ConnectionStatusControl(
                                state: model.session.connectionState,
                                isPaired: device.isPaired,
                                onConnect: connectSelectedDevice,
                                onPair: presentPairing
                            )
                        }
                        // Power lives here — Apple's Control Center remote
                        // places the power button in the top-right corner of
                        // the remote UI. Rightmost trailing item.
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                send(.power)
                            } label: {
                                Image(systemName: "power")
                            }
                            .accessibilityLabel("Power")
                            .accessibilityHint("Sends the power command to the selected TV.")
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .task(id: model.selectedDevice?.id) {
            loadSelectedValidationState()
            lastCommandFailure = nil
            lastCommandKey = nil
            await autoConnectIfNeeded()
        }
        .task(id: model.discovery.devices) {
            await RemoteIntentIndex.refreshDevices(model.discovery.devices)
        }
        .sheet(item: $presentedSheet, onDismiss: {
            // Pairing marks the device as paired; pick up the connection
            // without requiring a manual connect tap.
            loadSelectedValidationState()
            Task { await autoConnectIfNeeded() }
        }, content: sheetContent)
    }

    @ViewBuilder
    private var content: some View {
        if model.discovery.devices.isEmpty {
            PultWelcomeEmptyState(onAddTV: presentAddDevice)
        } else {
            RemoteControlSurface(
                device: model.selectedDevice,
                connectionState: model.session.connectionState,
                isPaired: model.selectedDevice?.isPaired ?? false,
                validationClaimState: selectedValidationClaimState,
                commandFailure: lastCommandFailure,
                send: send,
                sendKeyAction: send,
                onTextEntry: presentTextEntry,
                onFavoriteApps: presentFavoriteApps,
                onRetryCommand: retryLastCommand,
                onRetryConnect: connectSelectedDevice,
                onPair: presentPairing,
                onManualIP: presentAddDevice
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
            Button("Favorite Apps…", systemImage: "square.grid.2x2", action: presentFavoriteApps)
            Button("Diagnostics…", systemImage: "stethoscope", action: presentDiagnostics)
            Button("Pair Again…", systemImage: "link", action: presentPairing)
        }
        if !model.discovery.devices.isEmpty {
            Button("Manage TVs…", systemImage: "list.bullet", action: presentManageDevices)
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
        case manageDevices
        case favoriteApps
        case diagnostics
        case commandPalette

        var id: Self { self }
    }

    @ViewBuilder
    private func sheetContent(for sheet: RemoteSheet) -> some View {
        switch sheet {
        case .addDevice:
            AddDeviceView(model: model)
                .presentationSizing(.form)
        case .textEntry:
            TextEntryView(model: model)
                .presentationSizing(.form)
        case .pairing:
            PairingView(model: model, onManualIP: presentAddDevice)
                .presentationSizing(.page)
        case .manageDevices:
            ManageDevicesView(model: model)
                .presentationSizing(.form)
        case .favoriteApps:
            FavoriteAppLauncherView(model: model)
                .presentationSizing(.page)
        case .diagnostics:
            DiagnosticsAndValidationView(model: model)
                .presentationSizing(.page)
        case .commandPalette:
            CommandPaletteView(
                device: model.selectedDevice,
                connectionState: model.session.connectionState,
                onCommand: runPaletteCommand
            )
            .presentationSizing(.page)
        }
    }

    private func presentCommandPalette() {
        presentedSheet = .commandPalette
    }

    private func presentAddDevice() {
        lastCommandFailure = nil
        presentedSheet = .addDevice
    }

    private func presentTextEntry() {
        presentedSheet = .textEntry
    }

    private func presentPairing() {
        lastCommandFailure = nil
        presentedSheet = .pairing
    }

    private func presentManageDevices() {
        presentedSheet = .manageDevices
    }

    private func presentFavoriteApps() {
        presentedSheet = .favoriteApps
    }

    private func presentDiagnostics() {
        presentedSheet = .diagnostics
    }

    private func runPaletteCommand(_ command: RemoteQuickCommand) {
        presentedSheet = nil
        switch command.action {
        case let .key(key):
            send(key)
        case .addDevice:
            presentSheetAfterDismiss(.addDevice)
        case .textEntry:
            presentSheetAfterDismiss(.textEntry)
        case .pairing:
            presentSheetAfterDismiss(.pairing)
        case .manageDevices:
            presentSheetAfterDismiss(.manageDevices)
        case .favoriteApps:
            presentSheetAfterDismiss(.favoriteApps)
        case .diagnostics:
            presentSheetAfterDismiss(.diagnostics)
        case .connect:
            connectSelectedDevice()
        }
    }

    private func presentSheetAfterDismiss(_ sheet: RemoteSheet) {
        Task { @MainActor in
            await Task.yield()
            presentedSheet = sheet
        }
    }

    private func connectSelectedDevice() {
        lastCommandFailure = nil
        Task { await autoConnectIfNeeded() }
    }

    private func send(_ key: RemoteKey) {
        send(key, action: .tap)
    }

    private func send(_ key: RemoteKey, action: KeyAction) {
        lastCommandKey = key
        Task { @MainActor in
            let outcome = await model.sendKey(key, action: action)
            switch outcome {
            case .sent:
                if lastCommandKey == key {
                    lastCommandFailure = nil
                }
            case let .failed(message):
                lastCommandFailure = RemoteCommandFailure(message: message)
            }
        }
    }

    private func retryLastCommand() {
        guard let lastCommandKey else {
            connectSelectedDevice()
            return
        }
        send(lastCommandKey)
    }

    private func loadSelectedValidationState() {
        selectedValidationClaimState = validationReportStore.validationClaimState(for: model.selectedDevice?.id)
    }

    @MainActor
    private func autoConnectIfNeeded() async {
        await model.ensureConnected()
        await RemoteIntentIndex.donateSelectedDeviceShortcuts(for: model.selectedDevice)
        #if canImport(ActivityKit) && os(iOS)
        if let device = model.selectedDevice {
            await RemoteActivityController.shared.endActivities(notMatching: device.id)
        }
        if let device = model.selectedDevice, model.session.connectionState == .connected {
            await RemoteActivityController.shared.startOrUpdate(for: device, state: .connected)
        }
        #endif
    }
}
