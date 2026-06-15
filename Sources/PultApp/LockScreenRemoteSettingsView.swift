import SwiftUI
import PultCore

struct LockScreenRemoteSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLayout: RemoteActivityLayout

    private let store: RemoteActivityLayoutStore
    private let onLayoutChange: () async -> Void

    init(
        store: RemoteActivityLayoutStore = RemoteActivityLayoutStore(),
        onLayoutChange: @escaping () async -> Void = {}
    ) {
        self.store = store
        self.onLayoutChange = onLayoutChange
        _selectedLayout = State(initialValue: store.load())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Lock Screen Layout", selection: $selectedLayout) {
                        ForEach(RemoteActivityLayout.allCases) { layout in
                            Text(layout.displayTitle).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Chooses which controls Pult emphasizes in the Lock Screen remote.")
                } header: {
                    Text("Layout")
                } footer: {
                    Text(selectedLayout.settingsDescription)
                }

                Section {
                    layoutRow(
                        layout: .hybrid,
                        systemImage: "button.programmable",
                        detail: "Best for browsing menus: D-pad stays visible while play/pause, mute, and volume are promoted."
                    )
                    layoutRow(
                        layout: .media,
                        systemImage: "playpause",
                        detail: "Best for watching: playback, mute, and volume take the largest Lock Screen targets."
                    )
                } header: {
                    Text("Modes")
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Lock Screen Remote")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedLayout) { _, newValue in
                store.save(newValue)
                Task { await onLayoutChange() }
            }
        }
    }

    private func layoutRow(
        layout: RemoteActivityLayout,
        systemImage: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(layout == selectedLayout ? Color.pultAccent : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(layout.displayTitle)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if layout == selectedLayout {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.pultAccent)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            selectedLayout = layout
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(layout.displayTitle). \(detail)")
    }
}
