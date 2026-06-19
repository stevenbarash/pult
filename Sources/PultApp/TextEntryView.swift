import SwiftUI
import PultCore
#if canImport(PostHog)
import PostHog
#endif
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
            Group {
                if model.selectedDevice == nil {
                    noTVSelectedState
                } else {
                    mainContent
                }
            }
            .background { RemoteBackground() }
            .navigationTitle("TV Keyboard")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            let preparation = await model.prepareTextEntry()
            if case let .failed(message) = preparation {
                actionFailure = RemoteCommandFailure(message: message)
            }
            if model.session.textFieldStatus != nil {
                isFocused = true
            }
        }
    }

    // MARK: - Empty state

    private var noTVSelectedState: some View {
        ContentUnavailableView {
            Label("No TV Selected", systemImage: "tv.badge.wifi.slash")
        } description: {
            Text("Add or choose a TV to type.")
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        List {
            // Status row — inline, calm
            Section {
                statusRow
            }

            // Draft editor
            Section {
                editorField
                draftActions
                editorStatus
            } header: {
                Text("Draft")
            }

            // Field focus guidance (shown when connected but no TV field focused)
            if model.session.connectionState == .connected && model.session.textFieldStatus == nil {
                Section {
                    Label {
                        Text("Open search or another text field on the TV first. You can draft here now, then send when the TV field is focused.")
                            .font(PultTypography.bodySmall)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .foregroundStyle(PultDesign.warning)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            // Quick queries
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.suggestedQueries, id: \.self) { query in
                            quickQueryButton(query)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Label("Quick Queries", systemImage: "magnifyingglass")
            }

            // Send + key controls
            Section {
                keyControls
                sendButton
            } header: {
                Text("Actions")
            }

            // Error / recovery
            if let actionFailure {
                Section {
                    errorRow(actionFailure)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    // MARK: - Status row

    private var statusRow: some View {
        let status = model.session.textFieldStatus
        let title = status?.label.isEmpty == false ? (status?.label ?? "TV Text Field") : "TV Text Field"
        let detail: String = {
            switch model.session.connectionState {
            case .connected where status != nil:
                return status?.value.isEmpty == false ? "Editing current TV text" : "Ready"
            case .connected:
                return "Waiting for a focused text field"
            case .connecting:
                return "Connecting"
            case .disconnected:
                return "Disconnected"
            case let .failed(message):
                return message
            }
        }()

        return HStack(spacing: 12) {
            Image(systemName: status == nil ? "keyboard.badge.ellipsis" : "keyboard")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(status == nil ? PultDesign.warning : Color.pultAccent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }

    // MARK: - Editor

    private var editorField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search or type for TV", text: $text, axis: .vertical)
                .focused($isFocused)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.send)
                #endif
                .autocorrectionDisabled()
                .lineLimit(3...6)
                .onSubmit(sendText)
                .onChange(of: text) { _, _ in
                    if actionFailure != nil { actionFailure = nil }
                }
                .accessibilityLabel("Text for TV")
                .accessibilityHint(textFieldAccessibilityHint)

            if let status = model.session.textFieldStatus, !status.value.isEmpty {
                Label("TV: \(status.value)", systemImage: "text.cursor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .accessibilityLabel("Current TV text: \(status.value)")
            }
        }
    }

    private var draftActions: some View {
        HStack(spacing: 8) {
            #if canImport(UIKit)
            Button("Paste", systemImage: "doc.on.clipboard") {
                importClipboard()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Imports clipboard text into the draft.")
            #endif

            Button("Clear", systemImage: "xmark.circle") {
                clearDraft()
            }
            .buttonStyle(.bordered)
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
            .foregroundStyle(canSendText ? PultDesign.connected : Color.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
    }

    // MARK: - Controls

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
        Button(action: sendText) {
            Label("Send to TV", systemImage: "paperplane.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.pultAccent)
        .disabled(!canSendText)
        .accessibilityLabel("Send text")
        .accessibilityHint(sendButtonHint)
    }

    // MARK: - Error row

    private func errorRow(_ failure: RemoteCommandFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(failure.message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PultDesign.warning)
                Text(failure.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Keyboard error: \(failure.message). \(failure.guidance)")

            HStack(spacing: 8) {
                Button("Reconnect", systemImage: "arrow.clockwise") {
                    reconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Try Again", systemImage: "paperplane") {
                    sendText()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(text.isEmpty)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Quick query button

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
        .buttonStyle(.bordered)
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
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .disabled(!canSendKeys)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    // MARK: - Computed status strings

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
            PultDesign.connected
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

    // MARK: - Actions

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
                #if canImport(PostHog)
                PostHogSDK.shared.capture("text_sent_to_tv", properties: [
                    "char_count": payload.count,
                ])
                #endif
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
            await model.ensureConnected(staleAfter: 0)
            if case let .failed(message) = model.session.connectionState {
                actionFailure = RemoteCommandFailure(message: message)
            }
            isFocused = true
        }
    }
}
