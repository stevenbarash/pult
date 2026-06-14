import SwiftUI
import PultCore
#if canImport(UIKit)
import UIKit
#endif

struct TextEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RemoteControlModel
    @State private var text = ""
    @State private var actionFailure: RemoteCommandFailure?
    @FocusState private var isFocused: Bool

    private static let suggestedQueries = [
        "YouTube",
        "Netflix",
        "music",
        "weather",
        "movie trailers",
        "settings"
    ]

    private var canSendText: Bool {
        model.session.connectionState == .connected
            && model.session.textFieldStatus != nil
            && !text.isEmpty
    }

    private var canSendKeys: Bool {
        model.session.connectionState == .connected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    fieldFocusPrompt
                    editorSection
                    suggestions
                    controls
                    errorMessage
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .background { RemoteBackground() }
            .navigationTitle("TV Keyboard")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await model.ensureConnected()
            if model.session.textFieldStatus != nil {
                isFocused = true
            }
        }
    }

    private var header: some View {
        let status = model.session.textFieldStatus
        let title = status?.label.isEmpty == false ? status?.label ?? "TV Text Field" : "TV Text Field"
        let detail = switch model.session.connectionState {
        case .connected where status != nil:
            status?.value.isEmpty == false ? "Editing current TV text" : "Ready"
        case .connected:
            "Waiting for a focused text field"
        case .connecting:
            "Connecting"
        case .disconnected:
            "Disconnected"
        case let .failed(message):
            message
        }

        return HStack(spacing: 12) {
            Image(systemName: status == nil ? "keyboard.badge.ellipsis" : "keyboard")
                .font(.title2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(status == nil ? PultDesign.warning : Color.pultAccent)
                .frame(width: 46, height: 46)
                .glassEffect(
                    .regular.tint((status == nil ? PultDesign.warning : Color.pultAccent).opacity(0.16)),
                    in: .circle
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PultTypography.displaySmall)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(detail)
                    .font(PultTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular.tint(.pultAccent.opacity(0.10)), in: .rect(cornerRadius: 28))
        .pultGlassFallback(in: RoundedRectangle(cornerRadius: 28, style: .continuous), tint: .pultAccent)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            textField
            currentTVText
            draftActions
            editorStatus
        }
        .padding(14)
        .pultContentSurface(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            tint: .pultAccent
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Send Draft") {
            sendText()
        }
        .accessibilityAction(named: "Clear Draft") {
            clearDraft()
        }
        #if canImport(UIKit)
        .accessibilityAction(named: "Paste Clipboard") {
            importClipboard()
        }
        #endif
    }

    @ViewBuilder
    private var fieldFocusPrompt: some View {
        if model.session.connectionState == .connected && model.session.textFieldStatus == nil {
            Label {
                Text("Open search or another text field on the TV first. You can draft here now, then send when the TV field is focused.")
                    .font(PultTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.86)
            } icon: {
                Image(systemName: "keyboard.badge.ellipsis")
                    .foregroundStyle(PultDesign.warning)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pultContentSurface(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: PultDesign.warning
            )
            .accessibilityElement(children: .combine)
        }
    }

    private var textField: some View {
        TextField("Search or type for TV", text: $text, axis: .vertical)
            .focused($isFocused)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .submitLabel(.send)
            #endif
            .autocorrectionDisabled()
            .lineLimit(3...6)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PultDesign.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PultDesign.hairline, lineWidth: 1)
            }
            .onSubmit(sendText)
            .onChange(of: text) { _, _ in
                if actionFailure != nil {
                    actionFailure = nil
                }
            }
            .accessibilityLabel("Text for TV")
            .accessibilityHint(textFieldAccessibilityHint)
    }

    @ViewBuilder
    private var currentTVText: some View {
        if let status = model.session.textFieldStatus, !status.value.isEmpty {
            Label("TV: \(status.value)", systemImage: "text.cursor")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.84)
                .accessibilityLabel("Current TV text: \(status.value)")
        }
    }

    private var draftActions: some View {
        HStack(spacing: 8) {
            #if canImport(UIKit)
            Button("Paste", systemImage: "doc.on.clipboard") {
                importClipboard()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityHint("Imports clipboard text into the draft.")
            #endif

            Button("Clear", systemImage: "xmark.circle") {
                clearDraft()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(text.isEmpty)
            .accessibilityHint("Clears the keyboard draft.")

            Spacer(minLength: 0)

            Text("\(text.count) chars")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityLabel("\(text.count) characters")
        }
    }

    private var editorStatus: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                fieldStatusLabel
                Spacer(minLength: 8)
                sendReadinessLabel
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldStatusLabel
                sendReadinessLabel
            }
        }
    }

    private var fieldStatusLabel: some View {
        Label(fieldStatusText, systemImage: fieldStatusImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(fieldStatusTint)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
    }

    private var sendReadinessLabel: some View {
        Label(sendDisabledReason ?? "Ready to send", systemImage: canSendText ? "checkmark.circle.fill" : "info.circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(canSendText ? Color.green : Color.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quick Queries", systemImage: "magnifyingglass")
                .font(PultTypography.captionStrong)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.suggestedQueries, id: \.self) { query in
                        quickQueryButton(query)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                keyControls
                sendButton
            }

            VStack(spacing: 10) {
                keyControls
                sendButton
            }
        }
    }

    private var keyControls: some View {
        HStack(spacing: 10) {
            keyboardKeyButton(
                systemImage: "delete.left",
                label: "Delete",
                hint: keyButtonHint(for: "Delete")
            ) {
                sendKey(.delete)
            }

            keyboardKeyButton(
                systemImage: "return",
                label: "Enter",
                hint: keyButtonHint(for: "Enter")
            ) {
                sendKey(.enter)
            }
        }
    }

    private var sendButton: some View {
        Button("Send", systemImage: "paperplane.fill", action: sendText)
            .buttonStyle(.glassProminent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(!canSendText)
            .accessibilityLabel("Send text")
            .accessibilityHint(sendButtonHint)
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let actionFailure {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(actionFailure.message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PultDesign.warning)
                    Text(actionFailure.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Keyboard error: \(actionFailure.message). \(actionFailure.guidance)")

                HStack(spacing: 8) {
                    Button("Reconnect", systemImage: "arrow.clockwise") {
                        reconnect()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)

                    Button("Try Again", systemImage: "paperplane") {
                        sendText()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(text.isEmpty)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pultContentSurface(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: PultDesign.warning
            )
            .accessibilityElement(children: .contain)
        }
    }

    private var fieldStatusText: String {
        switch model.session.connectionState {
        case .connected where model.session.textFieldStatus != nil:
            "Focused TV field"
        case .connected:
            "No TV field focused"
        case .connecting:
            "Connecting"
        case .disconnected:
            "Disconnected"
        case .failed:
            "Connection failed"
        }
    }

    private var fieldStatusImage: String {
        switch model.session.connectionState {
        case .connected where model.session.textFieldStatus != nil:
            "keyboard"
        case .connected:
            "keyboard.badge.ellipsis"
        case .connecting:
            "antenna.radiowaves.left.and.right"
        case .disconnected, .failed:
            "exclamationmark.triangle"
        }
    }

    private var fieldStatusTint: Color {
        switch model.session.connectionState {
        case .connected where model.session.textFieldStatus != nil:
            .green
        case .connected:
            PultDesign.warning
        case .connecting:
            .pultAccent
        case .disconnected, .failed:
            PultDesign.warning
        }
    }

    private var sendDisabledReason: String? {
        guard !text.isEmpty else {
            return "Add text first"
        }

        switch model.session.connectionState {
        case .connected where model.session.textFieldStatus != nil:
            return nil
        case .connected:
            return "Open a TV text field"
        case .connecting:
            return "Connection in progress"
        case .disconnected:
            return "Connect before sending"
        case let .failed(message):
            return message
        }
    }

    private var sendButtonHint: String {
        sendDisabledReason ?? "Sends the draft to the focused TV text field."
    }

    private var textFieldAccessibilityHint: String {
        if let sendDisabledReason {
            return "\(sendDisabledReason). You can still edit the draft."
        }
        return "Enter text to send to the focused TV field."
    }

    private func keyButtonHint(for label: String) -> String {
        guard canSendKeys else {
            return "Connect to the TV before sending \(label.lowercased())."
        }
        return "Sends \(label.lowercased()) to the TV."
    }

    private func quickQueryButton(_ query: String) -> some View {
        Button {
            useSuggestion(query)
        } label: {
            Text(query)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(.capsule)
        }
        .buttonStyle(.glass)
        .pultGlassFallback(in: Capsule(), tint: .pultAccent)
        .accessibilityLabel("Use \(query)")
        .accessibilityHint("Replaces the keyboard draft.")
    }

    private func keyboardKeyButton(
        systemImage: String,
        label: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(width: 48, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .disabled(!canSendKeys)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    private func useSuggestion(_ query: String) {
        text = query
        actionFailure = nil
        isFocused = true
    }

    private func clearDraft() {
        guard !text.isEmpty else { return }
        text = ""
        actionFailure = nil
        isFocused = true
    }

    private func importClipboard() {
        #if canImport(UIKit)
        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else {
            actionFailure = RemoteCommandFailure(message: "Clipboard does not contain text.")
            isFocused = true
            return
        }

        text = clipboardText
        actionFailure = nil
        isFocused = true
        #endif
    }

    private func sendText() {
        let payload = text
        guard !payload.isEmpty else {
            isFocused = true
            return
        }

        Task { @MainActor in
            let sent = await model.session.sendText(payload)
            if sent {
                text = ""
                actionFailure = nil
            } else if let lastError = model.session.lastError {
                actionFailure = RemoteCommandFailure(message: lastError)
            }
            isFocused = true
        }
    }

    private func sendKey(_ key: RemoteKey) {
        Task { @MainActor in
            let outcome = await model.sendKey(key)
            switch outcome {
            case .sent:
                actionFailure = nil
            case let .failed(message):
                actionFailure = RemoteCommandFailure(message: message)
            }
            isFocused = true
        }
    }

    private func reconnect() {
        actionFailure = nil
        Task { @MainActor in
            await model.ensureConnected()
            if case let .failed(message) = model.session.connectionState {
                actionFailure = RemoteCommandFailure(message: message)
            }
            isFocused = true
        }
    }
}
