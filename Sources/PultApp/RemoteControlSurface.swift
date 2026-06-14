import Foundation
import SwiftUI
import PultCore

enum ControlMode: String, CaseIterable {
    case touchpad
    case dpad

    var label: String {
        switch self {
        case .touchpad: "Touchpad"
        case .dpad: "D-pad"
        }
    }

    var systemImage: String {
        switch self {
        case .touchpad: "hand.draw"
        case .dpad: "dpad"
        }
    }
}

private enum ControlModeStorage {
    static let key = "controlMode"

    static func load() -> ControlMode {
        guard let rawMode = UserDefaults.standard.string(forKey: key),
              let mode = ControlMode(rawValue: rawMode) else {
            return .touchpad
        }
        return mode
    }
}

struct RemoteControlSurface: View {
    let device: DeviceRecord?
    let connectionState: ConnectionState
    let isPaired: Bool
    let validationClaimState: DeviceValidationClaimState
    let commandFailure: RemoteCommandFailure?
    let send: (RemoteKey) -> Void
    let sendKeyAction: (RemoteKey, KeyAction) -> Void
    let onTextEntry: () -> Void
    let onFavoriteApps: () -> Void
    let onRetryCommand: () -> Void
    let onRetryConnect: () -> Void
    let onPair: () -> Void
    let onManualIP: () -> Void

    @AppStorage(ControlModeStorage.key) private var storedControlMode: ControlMode = .touchpad
    @State private var controlMode: ControlMode = ControlModeStorage.load()
    @State private var controlModePersistenceTask: Task<Void, Never>?
    @State private var keyPressFeedback = RemoteKeyPressFeedback()
    @State private var commandEcho: RemoteCommandEcho?
    @State private var commandEchoDismissalTask: Task<Void, Never>?
    @FocusState private var acceptsHardwareKeys: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var controlsAreEnabled: Bool {
        isPaired && connectionState == .connected
    }

    var body: some View {
        let layout = RemoteSurfaceLayout(
            isWide: horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
        )

        Group {
            if layout.isWide {
                remoteScroll(layout: layout)
            } else {
                compactRemote(layout: layout)
            }
        }
        .overlay(alignment: .topTrailing) {
            commandEchoView
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, layout.verticalPadding + 48)
        }
        .background {
            hardwareInputBridge
            RemoteKeyPressFeedbackEmitter(feedback: keyPressFeedback)
        }
        .focusable()
        .focused($acceptsHardwareKeys)
        .onAppear {
            acceptsHardwareKeys = true
            controlMode = storedControlMode
        }
        .onDisappear {
            controlModePersistenceTask?.cancel()
            commandEchoDismissalTask?.cancel()
            if storedControlMode != controlMode {
                storedControlMode = controlMode
            }
        }
        .onChange(of: storedControlMode) { _, newMode in
            guard controlMode != newMode else { return }
            controlMode = newMode
        }
        .onKeyPress(phases: [.down, .repeat], action: handleKeyPress)
    }

    private func remoteScroll(layout: RemoteSurfaceLayout) -> some View {
        ScrollView(.vertical) {
            surfaceContent(layout: layout)
                .frame(maxWidth: layout.maxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.verticalPadding)
        }
        .scrollIndicators(.hidden)
    }

    private func compactRemote(layout: RemoteSurfaceLayout) -> some View {
        ViewThatFits(in: .vertical) {
            compactRemoteStack(layout: layout, includesSecondaryCluster: true)
            compactRemoteStack(layout: layout, includesSecondaryCluster: false)
        }
        .frame(maxWidth: layout.maxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
    }

    /// All key sends funnel through here so every control shares one
    /// press-haptic trigger instead of each owning a counter.
    ///
    /// Pass `hapticKind: nil` to send the key command without any haptic —
    /// used by the volume hold-repeat path to suppress machine-gun buzzing.
    /// Overload that infers haptic kind from the key (normal path).
    private func sendKey(_ key: RemoteKey) {
        sendKey(key, hapticKind: key.hapticKind)
    }

    /// Sends `key` with an explicit haptic kind, or without any haptic when
    /// `hapticKind` is nil (used by the hold-repeat path to suppress buzz).
    private func sendKey(_ key: RemoteKey, hapticKind: HapticKind?) {
        showCommandEcho(for: key)
        if let kind = hapticKind {
            keyPressFeedback.play(kind: kind)
        }
        send(key)
    }

    private func sendKeyActionWithFeedback(_ key: RemoteKey, action: KeyAction) {
        if action != .release {
            showCommandEcho(for: key, action: action)
            keyPressFeedback.play(kind: key.hapticKind)
        }
        sendKeyAction(key, action)
    }

    private func showCommandEcho(for key: RemoteKey, action: KeyAction = .tap) {
        let title = action == .press ? "Holding \(key.displayTitle)" : "Sent \(key.displayTitle)"
        let echo = RemoteCommandEcho(
            title: title,
            systemImage: key.systemImage,
            tint: tint(for: key)
        )
        if reduceMotion {
            commandEcho = echo
        } else {
            withAnimation(.snappy(duration: 0.18)) {
                commandEcho = echo
            }
        }
        commandEchoDismissalTask?.cancel()
        let echoID = echo.id
        commandEchoDismissalTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(action == .press ? 1100 : 760))
                guard commandEcho?.id == echoID else { return }
                if reduceMotion {
                    commandEcho = nil
                } else {
                    withAnimation(.smooth(duration: 0.22)) {
                        commandEcho = nil
                    }
                }
            } catch {}
        }
    }

    private func tint(for key: RemoteKey) -> Color {
        switch key {
        case .power:
            PultDesign.danger
        case .volumeUp, .volumeDown, .mute:
            PultDesign.utility
        case .voiceSearch, .search, .playPause, .rewind, .fastForward:
            PultDesign.accent
        default:
            PultDesign.warmInk
        }
    }

    @ViewBuilder
    private var hardwareInputBridge: some View {
        #if canImport(UIKit)
        HardwareKeyboardBridge(send: sendHardwareKey)
        #else
        EmptyView()
        #endif

        #if canImport(GameController)
        GameControllerBridge(send: sendHardwareKey)
        #else
        EmptyView()
        #endif
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        #if canImport(UIKit)
        return .ignored
        #else
        guard let command = RemoteHardwareCommand(keyPress: press) else {
            return .ignored
        }
        sendHardwareCommand(command)
        return .handled
        #endif
    }

    private func sendHardwareKey(_ key: RemoteKey) {
        sendHardwareCommand(RemoteHardwareCommand(key: key))
    }

    private func sendHardwareCommand(_ command: RemoteHardwareCommand) {
        if controlsAreEnabled, command.shouldSend {
            sendKey(command.key)
        }
    }

    @ViewBuilder
    private func surfaceContent(layout: RemoteSurfaceLayout) -> some View {
        if layout.isWide {
            VStack(spacing: layout.sectionSpacing) {
                statusHeader
                banner

                HStack(alignment: .center, spacing: layout.columnSpacing) {
                    navigationGroup(layout: layout)
                        .frame(width: layout.navigationWidth)
                        .disabled(!controlsAreEnabled)
                        .opacity(controlsAreEnabled ? 1 : 0.46)

                    VStack(spacing: layout.sectionSpacing) {
                        commandCluster(layout: layout)
                            .disabled(!controlsAreEnabled)
                            .opacity(controlsAreEnabled ? 1 : 0.46)
                        volumeBar(maxWidth: layout.sidebarWidth)
                            .disabled(!controlsAreEnabled)
                            .opacity(controlsAreEnabled ? 1 : 0.46)
                    }
                    .frame(width: layout.sidebarWidth)
                }
            }
        } else {
            compactSurfaceContent(layout: layout)
        }
    }

    private func compactSurfaceContent(layout: RemoteSurfaceLayout) -> some View {
        compactRemoteStack(layout: layout, includesSecondaryCluster: true)
    }

    private func compactRemoteStack(
        layout: RemoteSurfaceLayout,
        includesSecondaryCluster: Bool
    ) -> some View {
        VStack(spacing: layout.sectionSpacing) {
            statusHeader
            banner

            compactNavigationGroup(layout: layout)
                .disabled(!controlsAreEnabled)
                .opacity(controlsAreEnabled ? 1 : 0.46)

            volumeBar(maxWidth: layout.maxWidth)
                .disabled(!controlsAreEnabled)
                .opacity(controlsAreEnabled ? 1 : 0.46)

            if includesSecondaryCluster {
                compactSecondaryCluster(layout: layout)
                    .disabled(!controlsAreEnabled)
                    .opacity(controlsAreEnabled ? 1 : 0.46)
            }
        }
    }

    // MARK: Status banner

    private var statusHeader: some View {
        RemoteStatusHeader(
            device: device,
            state: connectionState,
            isPaired: isPaired,
            validationClaimState: validationClaimState
        )
    }

    private enum BannerKind: Equatable {
        case commandFailure(RemoteCommandFailure)
        case connecting(String)
        case disconnected
        case failure(String)
        case unpaired
    }

    private var bannerKind: BannerKind? {
        // Unpaired wins: until the TV is paired, connecting is guaranteed to
        // fail, so "Pair" is the only actionable advice.
        if !isPaired {
            return .unpaired
        }
        if let commandFailure {
            return .commandFailure(commandFailure)
        }
        if connectionState == .connecting {
            let name = device?.name ?? ""
            let message = name.isEmpty ? "Connecting…" : "Connecting to \(name)…"
            return .connecting(message)
        }
        if connectionState == .disconnected {
            return .disconnected
        }
        if case let .failed(message) = connectionState {
            return .failure(message)
        }
        return nil
    }

    private var statusBannerTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private var statusBannerAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22)
    }

    @ViewBuilder
    private var banner: some View {
        Group {
            switch bannerKind {
            case let .commandFailure(failure):
                CommandFailureBanner(
                    failure: failure,
                    onRetryCommand: onRetryCommand,
                    onRetryConnect: onRetryConnect,
                    onPair: onPair,
                    onManualIP: onManualIP
                )
                .transition(statusBannerTransition)
            case let .connecting(message):
                ConnectingBanner(message: message)
                    .transition(statusBannerTransition)
            case .disconnected:
                StatusBanner(
                    systemImage: "powerplug",
                    message: "Connect to this TV before sending remote commands.",
                    tint: .pultAccent,
                    actionTitle: "Connect",
                    action: onRetryConnect
                )
                .transition(statusBannerTransition)
            case let .failure(message):
                StatusBanner(
                    systemImage: "wifi.exclamationmark",
                    message: message,
                    tint: PultDesign.danger,
                    actionTitle: "Retry",
                    action: onRetryConnect
                )
                .transition(statusBannerTransition)
            case .unpaired:
                StatusBanner(
                    systemImage: "link.badge.plus",
                    message: "This TV isn't paired yet. Pair once to start controlling it.",
                    tint: PultDesign.warning,
                    actionTitle: "Pair",
                    action: onPair
                )
                .transition(statusBannerTransition)
            case nil:
                EmptyView()
            }
        }
        .animation(statusBannerAnimation, value: bannerKind)
    }

    @ViewBuilder
    private var commandEchoView: some View {
        if let commandEcho {
            RemoteCommandEchoView(echo: commandEcho)
                .transition(commandEchoTransition)
        }
    }

    private var commandEchoTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity)
    }

    // MARK: Navigation surface

    private func navigationGroup(layout: RemoteSurfaceLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: 42, style: .continuous)

        return VStack(spacing: layout.controlSpacing) {
            navigationCaption
            navigationSurface(layout: layout)
            modeToggle
        }
        .padding(12)
        .background {
            shape
                .fill(PultDesign.surface)
                .allowsHitTesting(false)
        }
        .overlay {
            shape
                .stroke(PultDesign.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func compactNavigationGroup(layout: RemoteSurfaceLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)

        return VStack(spacing: layout.controlSpacing) {
            navigationCaption
            navigationSurface(layout: layout)
            modeToggle
            utilityRow(layout: layout)
        }
        .padding(10)
        .background {
            shape
                .fill(PultDesign.surface)
                .allowsHitTesting(false)
        }
        .overlay {
            shape
                .stroke(PultDesign.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var navigationCaption: some View {
        HStack(spacing: 10) {
            Text(controlMode.label)
                .font(PultTypography.captionStrong)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(controlsAreEnabled ? "Ready" : "Standby")
                .font(PultTypography.captionStrong)
                .foregroundStyle(controlsAreEnabled ? PultDesign.connected : .secondary)
        }
    }

    @ViewBuilder
    private func navigationSurface(layout: RemoteSurfaceLayout) -> some View {
        Group {
            switch controlMode {
            case .touchpad:
                touchpadSurface

            case .dpad:
                DPadRing(
                    isActive: true,
                    send: sendKey,
                    sendKeyAction: sendKeyActionWithFeedback
                )
            }
        }
        .frame(maxWidth: layout.navigationWidth)
        .frame(height: layout.navigationHeight)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var touchpadSurface: some View {
        TouchpadView(send: sendKey)
            .glassEffect(
                .regular.tint(PultDesign.accent.opacity(0.05)).interactive(),
                in: .rect(cornerRadius: RemoteMetrics.surfaceCornerRadius)
            )
            .pultGlassFallback(
                in: RoundedRectangle(
                    cornerRadius: RemoteMetrics.surfaceCornerRadius,
                    style: .continuous
                )
            )
    }

    private var modeToggle: some View {
        HStack(spacing: 6) {
            ForEach(ControlMode.allCases, id: \.rawValue) { mode in
                modeToggleButton(for: mode)
            }
        }
        .padding(5)
        .glassEffect(.regular, in: .capsule)
        .pultGlassFallback(in: Capsule())
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func modeToggleButton(for mode: ControlMode) -> some View {
        let isSelected = controlMode == mode

        return Button {
            selectControlMode(mode)
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(mode.label, systemImage: mode.systemImage)
                    .labelStyle(.titleAndIcon)
                Image(systemName: mode.systemImage)
                    .accessibilityHidden(true)
            }
            .font(PultTypography.captionStrong)
            .symbolRenderingMode(.hierarchical)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(width: modeToggleButtonWidth)
            .frame(minHeight: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .background {
            Capsule()
                .fill(PultDesign.accent.opacity(isSelected ? 0.22 : 0))
        }
        .accessibilityLabel(mode.label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Switches the remote navigation surface.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectControlMode(_ mode: ControlMode) {
        guard controlMode != mode else { return }

        controlMode = mode
        controlModePersistenceTask?.cancel()

        guard storedControlMode != mode else { return }
        controlModePersistenceTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, storedControlMode != mode else { return }
            storedControlMode = mode
        }
    }

    private var modeToggleButtonWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 108 : 124
    }

    // MARK: Key clusters

    private func commandCluster(layout: RemoteSurfaceLayout) -> some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: RemoteMetrics.clusterSpacing) {
                utilityRow(layout: layout)
                primaryActionRow
                mediaRow(layout: layout)
            }
            .padding(12)
            .pultContentSurface(
                in: RoundedRectangle(cornerRadius: 30, style: .continuous),
                isProminent: true
            )
        }
    }

    private func compactSecondaryCluster(layout: RemoteSurfaceLayout) -> some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: RemoteMetrics.clusterSpacing) {
                primaryActionRow
                mediaRow(layout: layout)
            }
            .padding(10)
            .pultContentSurface(
                in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                isProminent: true
            )
        }
    }

    @ViewBuilder
    private var primaryActionRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                searchButton
                launcherButton
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    searchButton
                    launcherButton
                }
                VStack(spacing: 10) {
                    searchButton
                    launcherButton
                }
            }
        }
    }

    private var launcherButton: some View {
        Button(action: onFavoriteApps) {
            HStack(spacing: 10) {
                Label("Favorite Apps", systemImage: "square.grid.2x2")
                    .font(PultTypography.subhead)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(PultTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(.capsule)
        }
        .buttonStyle(GlassShapeButtonStyle(shape: Capsule()))
        .accessibilityLabel("Favorite Apps")
        .accessibilityHint("Open saved app links for this TV")
    }

    private func utilityRow(layout: RemoteSurfaceLayout) -> some View {
        let keySize = layout.isWide ? 48 : layout.keySize
        let keySpacing = layout.isWide ? 8 : layout.keySpacing

        return HStack(spacing: keySpacing) {
            RemoteCircleButton(systemImage: "arrow.uturn.backward", label: "Back", size: keySize) { sendKey(.back) }
            RemoteCircleButton(systemImage: "house", label: "Home", size: keySize) { sendKey(.home) }
            RemoteCircleButton(systemImage: "mic.fill", label: "Voice search", iconColor: PultDesign.accent, size: keySize) { sendKey(.voiceSearch) }
            RemoteCircleButton(systemImage: "keyboard", label: "Text input", size: keySize, action: onTextEntry)
            RemoteCircleButton(systemImage: "power", label: "Power", iconColor: PultDesign.danger, size: keySize) { sendKey(.power) }
        }
        .frame(maxWidth: .infinity)
    }

    private func mediaRow(layout: RemoteSurfaceLayout) -> some View {
        HStack(spacing: layout.keySpacing) {
            RemoteCircleButton(systemImage: "backward.fill", label: "Rewind", size: layout.keySize) { sendKey(.rewind) }
            RemoteCircleButton(systemImage: "playpause.fill", label: "Play or pause", iconColor: PultDesign.accent, size: layout.keySize) { sendKey(.playPause) }
            RemoteCircleButton(systemImage: "forward.fill", label: "Fast forward", size: layout.keySize) { sendKey(.fastForward) }
        }
        .frame(maxWidth: .infinity)
    }

    private var searchButton: some View {
        Button {
            sendKey(.search)
        } label: {
            HStack(spacing: 10) {
                Label("Search TV", systemImage: RemoteKey.search.systemImage)
                    .font(PultTypography.subhead)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(.capsule)
        }
        .buttonStyle(GlassShapeButtonStyle(shape: Capsule()))
        .accessibilityLabel("Search TV")
        .accessibilityHint("Opens search on the selected TV")
    }

    /// Sends `key` to the TV without triggering any haptic feedback.
    /// Used by hold-repeat zones so only the initial press produces a haptic.
    private func sendKeySilently(_ key: RemoteKey) {
        sendKey(key, hapticKind: nil)
    }

    private func volumeBar(maxWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HoldRepeatKeyZone(key: .volumeDown, systemImage: "speaker.minus.fill", send: sendKey, sendSilently: sendKeySilently)
            VolumeMuteButton { sendKey(.mute) }
            HoldRepeatKeyZone(key: .volumeUp, systemImage: "speaker.plus.fill", send: sendKey, sendSilently: sendKeySilently)
        }
        .frame(maxWidth: maxWidth)
        .background {
            Capsule()
                .fill(PultDesign.surface)
                .allowsHitTesting(false)
        }
        .glassEffect(.regular.tint(PultDesign.utility.opacity(0.08)).interactive(), in: .capsule)
        .pultGlassFallback(in: Capsule())
        .overlay {
            Capsule()
                .stroke(PultDesign.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

}

// MARK: - Haptic classification

private extension RemoteKey {
    /// Maps each key to the semantic haptic weight that best fits the gesture.
    var hapticKind: HapticKind {
        switch self {
        case .select, .enter:
            // Confirm actions deserve a heavier, more satisfying thud.
            return .select
        case .up, .down, .left, .right:
            // Directional navigation is rapid and continuous; keep it featherlight.
            return .directional
        default:
            // Back, home, media, voice, search, power, volume (single tap), mute, delete.
            return .standard
        }
    }
}

private struct RemoteSurfaceLayout {
    var isWide: Bool
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var sectionSpacing: CGFloat
    var columnSpacing: CGFloat
    var controlSpacing: CGFloat
    var keySpacing: CGFloat
    var keySize: CGFloat
    var maxWidth: CGFloat
    var navigationWidth: CGFloat
    var navigationHeight: CGFloat
    var sidebarWidth: CGFloat

    init(isWide: Bool) {
        self.isWide = isWide
        horizontalPadding = isWide ? 28 : 18
        verticalPadding = isWide ? 18 : 12
        sectionSpacing = isWide ? 18 : 14
        columnSpacing = isWide ? 20 : 0
        controlSpacing = isWide ? 12 : 10
        keySpacing = isWide ? RemoteMetrics.clusterSpacing : 12
        keySize = isWide ? RemoteMetrics.keySize : 56

        if isWide {
            sidebarWidth = 312
            navigationWidth = 396
            navigationHeight = 420
            maxWidth = navigationWidth + sidebarWidth + columnSpacing
        } else {
            sidebarWidth = RemoteMetrics.maxControlWidth
            navigationWidth = RemoteMetrics.maxControlWidth
            navigationHeight = 240
            maxWidth = RemoteMetrics.maxControlWidth
        }
    }
}
