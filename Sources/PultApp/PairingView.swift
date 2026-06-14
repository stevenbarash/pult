import SwiftUI
import PultCore

struct PairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var model: RemoteControlModel
    var onManualIP: (() -> Void)? = nil
    @State private var code = ""

    var body: some View {
        NavigationStack {
            content
                .animation(pairingPhaseAnimation, value: model.pairingState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(contentPadding)
                .background { RemoteBackground() }
                .navigationTitle("Pair with TV")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: finish)
                    }
                }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(trigger: model.pairingState) { _, newState in
            switch newState {
            case .paired: .success
            case .failed: .error
            default: nil
            }
        }
        .sensoryFeedback(trigger: model.pairingCodeError) { _, new in
            new != nil ? SensoryFeedback.error : nil
        }
        .onChange(of: model.pairingCodeError) { _, new in
            // Clear the entered code when a wrong-code error appears so the
            // field is empty and ready for the fresh code shown on the TV.
            if new != nil { code = "" }
        }
        .task {
            await model.beginPairing()
        }
        .onDisappear {
            // Covers interactive (swipe) dismissal, which never reaches
            // finish(); cancelPairing is idempotent for the button paths.
            Task { await model.cancelPairing() }
        }
    }

    private var pairingPhaseTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        )
    }

    private var pairingPhaseAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.24)
    }

    @ViewBuilder
    private var content: some View {
        switch model.pairingState {
        case .idle, .connecting:
            connectingPhase
        case .waitingForCode:
            codeEntry
                .transition(pairingPhaseTransition)
        case .verifying:
            verifyingPhase
        case .paired:
            pairedPhase
        case let .failed(message):
            failedPhase(message)
        }
    }

    private var connectingPhase: some View {
        PairingPhaseLayout(
            systemImage: "tv",
            symbolColor: .secondary,
            title: "Contacting \(deviceName)…",
            subtitle: "Make sure the TV is awake and on the same Wi-Fi network."
        ) {
            ProgressView()
                .controlSize(.large)
        }
        .transition(pairingPhaseTransition)
    }

    private var verifyingPhase: some View {
        PairingPhaseLayout(
            systemImage: "lock.shield",
            symbolColor: .secondary,
            title: "Checking the Code…",
            subtitle: "Confirming the pairing with \(deviceName)."
        ) {
            ProgressView()
                .controlSize(.large)
        }
        .transition(pairingPhaseTransition)
    }

    private var pairedPhase: some View {
        PairingPhaseLayout(
            systemImage: "checkmark.seal.fill",
            symbolColor: .green,
            title: "Paired with \(deviceName)",
            subtitle: "You're ready to take control."
        ) {
            Button("Done", systemImage: "checkmark", action: finish)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityHint("Closes pairing and returns to the remote.")
        }
        .transition(pairingPhaseTransition)
    }

    private func failedPhase(_ message: String) -> some View {
        PairingPhaseLayout(
            systemImage: "exclamationmark.triangle.fill",
            symbolColor: PultDesign.warning,
            title: "Pairing Didn't Finish",
            subtitle: pairingFailureSubtitle(message)
        ) {
            PairingFailureRecovery(
                retryPairing: retryPairing,
                useManualIP: manualIPRecoveryAction
            )
        }
        .transition(pairingPhaseTransition)
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: codeEntrySpacing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter the Code on Your TV")
                    .font(PultTypography.displaySmall)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                if let codeError = model.pairingCodeError {
                    Label(codeError, systemImage: "exclamationmark.circle.fill")
                        .font(PultTypography.captionStrong)
                        .foregroundStyle(PultDesign.warning)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .accessibilityLabel("Error: \(codeError)")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text("\(deviceName) is showing a 6-character code right now.")
                        .font(PultTypography.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .transition(.opacity)
                }
            }
            .animation(pairingPhaseAnimation, value: model.pairingCodeError != nil)

            PairingCodeField(code: $code, onComplete: submit)
                .onChange(of: code) { _, _ in
                    if model.pairingCodeError != nil {
                        model.clearPairingCodeError()
                    }
                }

            PairingCodeHelpRow()

            Button("Pair", systemImage: "link", action: submit)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(PairingCode(rawValue: code) == nil)
                .accessibilityHint(pairButtonAccessibilityHint)
        }
        .frame(maxWidth: 430, alignment: .leading)
        .padding(18)
        .pultContentSurface(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            tint: .pultAccent,
            isProminent: true
        )
    }

    private var contentPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 16 : 24
    }

    private var codeEntrySpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 20 : 28
    }

    private var deviceName: String {
        model.selectedDevice?.name ?? "the TV"
    }

    private func pairingFailureSubtitle(_ message: String) -> String {
        "\(message) Keep the TV awake, confirm the code is still visible, then try again."
    }

    private var pairButtonAccessibilityHint: String {
        PairingCode(rawValue: code) == nil
            ? "Enter all \(PairingCode.length) code characters before pairing."
            : "Submits the code shown on \(deviceName)."
    }

    private var manualIPRecoveryAction: (() -> Void)? {
        guard onManualIP != nil else { return nil }
        return { useManualIP() }
    }

    private func retryPairing() {
        code = ""
        Task { await model.beginPairing() }
    }

    private func useManualIP() {
        code = ""
        onManualIP?()
    }

    private func submit() {
        guard PairingCode(rawValue: code) != nil else { return }
        let entered = code
        Task { await model.submitPairingCode(entered) }
    }

    private func finish() {
        Task { await model.cancelPairing() }
        dismiss()
    }
}

private struct PairingPhaseLayout<Accessory: View>: View {
    var systemImage: String
    var symbolColor: Color
    var title: String
    var subtitle: String
    @ViewBuilder var accessory: Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            phaseImage
            VStack(spacing: 8) {
                Text(title)
                    .font(PultTypography.displaySmall)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                Text(subtitle)
                    .font(PultTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .minimumScaleFactor(0.82)
            }
            accessory
        }
        .frame(maxWidth: 420)
        .padding(20)
        .pultContentSurface(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            tint: symbolColor,
            isProminent: true
        )
    }

    @ViewBuilder
    private var phaseImage: some View {
        let image = Image(systemName: systemImage)
            .font(.system(size: 52))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(symbolColor)

        if reduceMotion {
            image
                .accessibilityHidden(true)
        } else {
            image
                .symbolEffect(.bounce, value: title)
                .accessibilityHidden(true)
        }
    }
}

private struct PairingFailureRecovery: View {
    var retryPairing: () -> Void
    var useManualIP: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            PairingRecoveryChecklist()
            VStack(spacing: 10) {
                retryButton
                if let useManualIP {
                    manualIPButton(useManualIP)
                }
            }
        }
    }

    private var retryButton: some View {
        Button("Try Again", systemImage: "arrow.clockwise", action: retryPairing)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityHint("Starts a fresh pairing attempt with the selected TV.")
    }

    private func manualIPButton(_ action: @escaping () -> Void) -> some View {
        Button("Use Manual IP", systemImage: "network", action: action)
            .buttonStyle(.glass)
            .controlSize(.large)
            .accessibilityHint("Opens manual address entry in case the TV address changed.")
    }
}

private struct PairingRecoveryChecklist: View {
    private let tips = [
        PairingRecoveryTip(
            systemImage: "tv",
            title: "Keep the prompt open",
            detail: "If the TV stopped showing a code, start pairing again."
        ),
        PairingRecoveryTip(
            systemImage: "wifi",
            title: "Check the network",
            detail: "The iPhone and TV need to be reachable on the same local network."
        ),
        PairingRecoveryTip(
            systemImage: "network",
            title: "Update the address",
            detail: "If the TV moved networks, enter its current IP address."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tips) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: tip.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.pultAccent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title)
                            .font(.footnote.weight(.semibold))
                        Text(tip.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .pultContentSurface(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            tint: PultDesign.warning
        )
        .accessibilityElement(children: .contain)
    }
}

private struct PairingRecoveryTip: Identifiable {
    var id: String { title }
    var systemImage: String
    var title: String
    var detail: String
}

private struct PairingCodeHelpRow: View {
    var body: some View {
        Label {
            Text("Use letters A-F and numbers 0-9 exactly as shown. If the TV shows a new code, clear this one and enter the new code.")
                .font(PultTypography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: "textformat.123")
                .foregroundStyle(Color.pultAccent)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }
}

/// Six glass code boxes driven by a hidden text field, OTP-style.
/// Tapping the boxes focuses the field; input is filtered to hex characters
/// and submission fires automatically when all six are typed.
private struct PairingCodeField: View {
    @Binding var code: String
    var onComplete: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var scaledBoxWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .title2) private var scaledBoxHeight: CGFloat = 56

    var body: some View {
        let characters = Array(code.prefix(PairingCode.length))

        ZStack {
            codeBoxes(characters: characters)
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            TextField("Pairing code", text: $code)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .font(.title2.monospaced().weight(.semibold))
                .foregroundStyle(Color.clear)
                .tint(.clear)
                #if os(iOS)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .textContentType(.oneTimeCode)
                .submitLabel(.done)
                #endif
                .autocorrectionDisabled()
                .frame(maxWidth: .infinity, minHeight: boxHeight)
                .contentShape(.rect)
                .accessibilityLabel("Pairing code")
                .accessibilityValue(accessibilityCodeValue)
                .accessibilityHint("Enter the 6-character code shown on the TV.")
                .accessibilityInputLabels(["Pairing code", "TV code"])
                .accessibilityAction(named: "Clear code") {
                    code = ""
                    isFocused = true
                }
        }
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
        .onChange(of: code) { _, newValue in
            let cleaned = PairingCode.sanitized(newValue)
            guard cleaned == newValue else {
                // Reassigning re-fires onChange with the cleaned value;
                // completion is decided on that settled pass only.
                code = cleaned
                return
            }
            if cleaned.count == PairingCode.length {
                onComplete()
            }
        }
        .task { isFocused = true }
    }

    private func codeBoxes(characters: [Character]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: preferredBoxSpacing) {
                ForEach(0..<PairingCode.length, id: \.self) { index in
                    characterBox(
                        at: index,
                        characters: characters,
                        width: preferredBoxWidth,
                        height: boxHeight
                    )
                }
            }

            HStack(spacing: compactBoxSpacing) {
                ForEach(0..<PairingCode.length, id: \.self) { index in
                    characterBox(
                        at: index,
                        characters: characters,
                        width: compactBoxWidth,
                        height: boxHeight
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: boxHeight)
    }

    @ViewBuilder
    private func characterBox(
        at index: Int,
        characters: [Character],
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let isActive = isFocused && index == min(code.count, PairingCode.length - 1)
        let cornerRadius = min(14, width * 0.34)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let box = Text(index < characters.count ? String(characters[index]) : " ")
            .font(.title2.monospaced().weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: width, height: height)
            .overlay {
                shape
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.7) : .white.opacity(0.1),
                        lineWidth: 1.5
                    )
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isActive)

        if reduceTransparency {
            box
                .pultGlassFallback(in: shape, tint: isActive ? .accentColor : nil, isProminent: isActive)
        } else {
            box
                .glassEffect(
                    isActive ? .regular.tint(.accentColor.opacity(0.3)) : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
                .pultGlassFallback(in: shape, tint: isActive ? .accentColor : nil, isProminent: isActive)
        }
    }

    private var preferredBoxSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 6 : 10
    }

    private var preferredBoxWidth: CGFloat {
        min(scaledBoxWidth, dynamicTypeSize.isAccessibilitySize ? 54 : 48)
    }

    private var compactBoxSpacing: CGFloat {
        4
    }

    private var compactBoxWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 40 : 38
    }

    private var boxHeight: CGFloat {
        min(scaledBoxHeight, dynamicTypeSize.isAccessibilitySize ? 66 : 58)
    }

    private var accessibilityCodeValue: String {
        if code.isEmpty {
            return "Empty"
        }
        return "\(code.count) of \(PairingCode.length) characters entered"
    }
}
