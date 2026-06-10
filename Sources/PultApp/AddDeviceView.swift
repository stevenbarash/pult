import SwiftUI
import PultCore

struct AddDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RemoteControlModel
    @State private var name = ""
    @State private var host = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case host
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddDevice: Bool {
        !trimmedHost.isEmpty && !trimmedHost.contains(" ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        TextField("Living Room TV", text: $name)
                            .textContentType(.name)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .host }
                    } label: {
                        Image(systemName: "tv")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent {
                        TextField("192.168.1.42", text: $host)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .host)
                            .submitLabel(.done)
                            .onSubmit(addDeviceIfPossible)
                    } label: {
                        Image(systemName: "network")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Google TV")
                } footer: {
                    Text("Find the TV's IP address under Settings › Network & Internet on the TV. Both devices must be on the same network.")
                }
            }
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
                }
            }
            .task { focusedField = .name }
        }
        .preferredColorScheme(.dark)
    }

    private func addDeviceIfPossible() {
        if canAddDevice {
            addDevice()
        }
    }

    private func addDevice() {
        model.addManualDevice(name: name, host: trimmedHost)
        dismiss()
    }
}
