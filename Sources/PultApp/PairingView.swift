import SwiftUI
import PultCore

struct PairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RemoteControlModel
    @State private var code = ""

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
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
        .animation(.smooth(duration: 0.35), value: model.pairingState)
        .sensoryFeedback(trigger: model.pairingState) { _, newState in
            switch newState {
            case .paired: .success
            case .failed: .error
            default: nil
            }
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

    @ViewBuilder
    private var content: some View {
        switch model.pairingState {
        case .idle, .connecting:
            PairingPhaseLayout(
                systemImage: "tv",
                symbolColor: .secondary,
                title: "Contacting \(deviceName)…",
                subtitle: "Make sure the TV is awake and on the same Wi-Fi network."
            ) {
                ProgressView()
                    .controlSize(.large)
            }
            .transition(.blurReplace)
        case .waitingForCode:
            codeEntry
                .transition(.blurReplace)
        case .verifying:
            PairingPhaseLayout(
                systemImage: "lock.shield",
                symbolColor: .secondary,
                title: "Checking the Code…",
                subtitle: "Confirming the pairing with \(deviceName)."
            ) {
                ProgressView()
                    .controlSize(.large)
            }
            .transition(.blurReplace)
        case .paired:
            PairingPhaseLayout(
                systemImage: "checkmark.seal.fill",
                symbolColor: .green,
                title: "Paired with \(deviceName)",
                subtitle: "You're ready to take control."
            ) {
                Button("Done", action: finish)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .transition(.blurReplace)
        case let .failed(message):
            PairingPhaseLayout(
                systemImage: "exclamationmark.triangle.fill",
                symbolColor: .orange,
                title: "Pairing Didn't Finish",
                subtitle: message
            ) {
                Button("Try Again") {
                    code = ""
                    Task { await model.beginPairing() }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .transition(.blurReplace)
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Enter the Code on Your TV")
                    .font(.title3.weight(.semibold))
                Text("\(deviceName) is showing a 6-character code right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            PairingCodeField(code: $code, onComplete: submit)

            Button("Pair", action: submit)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(PairingCode(rawValue: code) == nil)
        }
    }

    private var deviceName: String {
        model.selectedDevice?.name ?? "the TV"
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

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolColor)
                .symbolEffect(.bounce, value: title)
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            accessory
        }
    }
}

/// Six glass code boxes driven by a hidden text field, OTP-style.
/// Tapping the boxes focuses the field; input is filtered to hex characters
/// and submission fires automatically when all six are typed.
private struct PairingCodeField: View {
    @Binding var code: String
    var onComplete: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .focused($isFocused)
                #if os(iOS)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                #endif
                .autocorrectionDisabled()
                .opacity(0.02)
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                ForEach(0..<PairingCode.length, id: \.self) { index in
                    characterBox(at: index)
                }
            }
            .contentShape(.rect)
            .onTapGesture { isFocused = true }
        }
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
        .accessibilityElement()
        .accessibilityLabel("Pairing code")
        .accessibilityValue(code.isEmpty ? "Empty" : code)
    }

    private func characterBox(at index: Int) -> some View {
        let characters = Array(code)
        let isActive = isFocused && index == min(code.count, PairingCode.length - 1)
        return Text(index < characters.count ? String(characters[index]) : " ")
            .font(.title2.monospaced().weight(.semibold))
            .frame(width: 44, height: 56)
            .glassEffect(
                isActive ? .regular.tint(.accentColor.opacity(0.3)) : .regular,
                in: .rect(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.7) : .white.opacity(0.1),
                        lineWidth: 1.5
                    )
            }
            .animation(.snappy(duration: 0.18), value: isActive)
    }
}
