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
                    Text("Tap a TV to select it. Swipe left to delete, or use Edit to reorder. Add the same TV by Manual IP if it no longer appears nearby.")
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
            .background { RemoteBackground() }
            .navigationTitle("TVs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
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
                .foregroundStyle(device.isPaired ? Color.pultAccent : PultDesign.warning)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(device.host)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(presence.managementText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
                Text(device.isPaired ? "Paired" : "Pair required")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(device.isPaired ? PultDesign.connected : PultDesign.warning)
            }
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(device.host)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
