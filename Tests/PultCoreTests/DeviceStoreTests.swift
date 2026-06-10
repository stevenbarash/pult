import Foundation
import Testing
@testable import PultCore

private func makeSuite(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test
func persistsAndRestoresSelectedDeviceID() {
    let suite = makeSuite("pult.tests.selection")
    let store = UserDefaultsDeviceStore(defaults: suite, legacyDefaults: suite)
    let id = UUID()

    store.saveSelectedDeviceID(id)
    #expect(store.loadSelectedDeviceID() == id)

    store.saveSelectedDeviceID(nil)
    #expect(store.loadSelectedDeviceID() == nil)
}

@Test
func migratesLegacyDevicesIntoGroupSuiteOnce() {
    let legacy = makeSuite("pult.tests.legacy")
    let group = makeSuite("pult.tests.group")
    let legacyStore = UserDefaultsDeviceStore(defaults: legacy, legacyDefaults: legacy)
    legacyStore.saveDevices([DeviceRecord(name: "Old TV", host: "10.0.0.9")])

    let store = UserDefaultsDeviceStore(defaults: group, legacyDefaults: legacy)
    #expect(store.loadDevices().first?.name == "Old TV")

    // A later save in the group suite must not be clobbered by re-migration.
    store.saveDevices([])
    #expect(store.loadDevices().isEmpty)
}

@MainActor
@Test
func discoveryPersistsSelection() {
    let memory = MemoryDeviceStore()
    let discovery = DeviceDiscovery(store: memory)
    let device = discovery.addManualDevice(name: "TV", host: "192.168.1.42")!

    discovery.selectedDeviceID = device.id

    #expect(memory.selectedID == device.id)
}
