import Foundation
import Testing
@testable import PultCore

@MainActor
@Test
func restoresPersistedSelectionOverFirstDevice() {
    let store = MemoryDeviceStore()
    let first = DeviceRecord(name: "Bedroom", host: "10.0.0.1", isPaired: true)
    let second = DeviceRecord(name: "Living Room", host: "10.0.0.2", isPaired: true)
    store.records = [first, second]
    store.selectedID = second.id

    let model = RemoteControlModel(discovery: DeviceDiscovery(store: store))

    #expect(model.selectedDevice?.id == second.id)
}

@MainActor
@Test
func danglingPersistedSelectionFallsBackAndRepairsStore() {
    let store = MemoryDeviceStore()
    let only = DeviceRecord(name: "Bedroom", host: "10.0.0.1")
    store.records = [only]
    store.selectedID = UUID() // device no longer exists

    let model = RemoteControlModel(discovery: DeviceDiscovery(store: store))

    #expect(model.selectedDevice?.id == only.id)
    #expect(store.selectedID == only.id)
}

@MainActor
@Test
func selectingDevicePersistsSelection() {
    let store = MemoryDeviceStore()
    let first = DeviceRecord(name: "Bedroom", host: "10.0.0.1")
    let second = DeviceRecord(name: "Living Room", host: "10.0.0.2")
    store.records = [first, second]

    let model = RemoteControlModel(discovery: DeviceDiscovery(store: store))
    model.select(second)

    #expect(store.selectedID == second.id)
}
