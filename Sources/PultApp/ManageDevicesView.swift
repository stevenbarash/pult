import SwiftUI
import PultCore

/// Saved-TV management uses native list editing so the same saved devices that
/// power Spotlight, Siri, controls, and the app stay tidy from one place.
struct ManageDevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RemoteControlModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.discovery.devices) { device in
                        Button {
                            model.select(device)
                        } label: {
                            DeviceManagementRow(
                                device: device,
                                isSelected: model.selectedDevice?.id == device.id,
                                presence: model.discovery.presence(for: device),
                                reachability: model.discovery.reachability(for: device)
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(device)
                            }
                        }
                    }
                    .onMove(perform: model.moveDevices)
                    .onDelete(perform: model.deleteDevices)
                } footer: {
                    Text("Tap to select a TV. Use Edit to reorder saved TVs, or delete entries that moved networks. Add the same TV by Manual IP if it no longer appears nearby.")
                }
            }
            .navigationTitle("TVs")
            .scrollContentBackground(.hidden)
            .background { RemoteBackground() }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                #endif
            }
        }
        .preferredColorScheme(.dark)
    }

    private func delete(_ device: DeviceRecord) {
        guard let index = model.discovery.devices.firstIndex(where: { $0.id == device.id }) else { return }
        model.deleteDevices(atOffsets: IndexSet(integer: index))
    }
}

private struct DeviceManagementRow: View {
    let device: DeviceRecord
    let isSelected: Bool
    let presence: DevicePresence
    let reachability: DeviceReachability

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.isPaired ? "tv" : "tv.slash")
                .font(.title3.weight(.semibold))
                .foregroundStyle(device.isPaired ? Color.primary : PultDesign.warning)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.body.weight(.semibold))
                Text("\(device.host) - \(presence.managementText) - \(reachability.shortDiagnosticText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(device.isPaired ? "Paired" : "Pair required")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(device.isPaired ? Color.green : PultDesign.warning)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(device.host)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
