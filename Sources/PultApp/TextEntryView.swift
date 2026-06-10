import SwiftUI

struct TextEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool
    let onSubmit: (String) -> Void

    private var canSubmit: Bool {
        !text.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Text for TV", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isFocused)
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        #endif
                } footer: {
                    Text("Sends the text to the focused field on the TV. Requires TV-side support.")
                }
            }
            .navigationTitle("TV Keyboard")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", action: submit)
                        .disabled(!canSubmit)
                }
            }
            .task { isFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        onSubmit(text)
        dismiss()
    }
}
