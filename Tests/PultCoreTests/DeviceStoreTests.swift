import Foundation
import Testing
@testable import PultCore

private func makeSuite(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func successfulValidationReport(
    for device: DeviceRecord,
    updatedAt: Date = Date(timeIntervalSince1970: 200)
) -> ValidationReport {
    var run = ValidationRunState(startedAt: Date(timeIntervalSince1970: 100))
    for item in run.items {
        run.update(item.id, status: .passed, note: "Checked.", at: Date(timeIntervalSince1970: 101))
    }
    return run.makeReport(for: device, updatedAt: updatedAt)
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

@Test
func migratesLegacySelectionOnLoadSelectedDeviceID() {
    let legacy = makeSuite("pult.tests.legacy2")
    let group = makeSuite("pult.tests.group2")
    let legacyStore = UserDefaultsDeviceStore(defaults: legacy, legacyDefaults: legacy)
    let device = DeviceRecord(name: "Old TV", host: "10.0.0.9")
    legacyStore.saveDevices([device])
    legacyStore.saveSelectedDeviceID(device.id)

    let store = UserDefaultsDeviceStore(defaults: group, legacyDefaults: legacy)
    // Call loadSelectedDeviceID() WITHOUT calling loadDevices() first — fix 1 pins this.
    #expect(store.loadSelectedDeviceID() == device.id)
}

@Test
func legacyDeviceRecordDecodesWithoutValidationClaim() throws {
    let data = try JSONSerialization.data(withJSONObject: [
        "id": "00000000-0000-0000-0000-000000000045",
        "name": "Legacy TV",
        "host": "10.0.0.45",
        "commandPort": 6466,
        "pairingPort": 6467,
        "lastSeen": 100.0,
        "isPaired": true,
        "source": "manual"
    ])

    let device = try JSONDecoder().decode(DeviceRecord.self, from: data)

    #expect(device.lastSuccessfulValidation == nil)
    #expect(!device.isValidatedOnPhysicalDevice)
    #expect(device.validationClaimState == .unvalidated)
}

@Test
func deviceRecordPersistsSuccessfulPhysicalValidation() throws {
    let suite = makeSuite("pult.tests.device-validation")
    let store = UserDefaultsDeviceStore(defaults: suite, legacyDefaults: suite)
    let device = DeviceRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000046")!,
        name: "Validated TV",
        host: "10.0.0.46",
        isPaired: true
    )
    let report = successfulValidationReport(for: device)

    store.saveDevices([device])
    let savedValidation = try #require(store.saveSuccessfulValidation(from: report))
    #expect(savedValidation.deviceName == "Validated TV")
    let loaded = try #require(store.loadDevices().first)

    #expect(loaded.isValidatedOnPhysicalDevice)
    #expect(loaded.lastSuccessfulValidation?.deviceName == "Validated TV")
    #expect(loaded.lastSuccessfulValidation?.host == "10.0.0.46")
    #expect(loaded.lastSuccessfulValidation?.validatedAt == Date(timeIntervalSince1970: 200))
    #expect(loaded.lastSuccessfulValidation?.passedAreas.map(\.id).contains(ValidationRunStepID.volume) == true)
}

@Test
func deviceRecordRejectsIncompleteValidationReport() {
    var device = DeviceRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000047")!,
        name: "Incomplete TV",
        host: "10.0.0.47",
        isPaired: true
    )
    var run = ValidationRunState(startedAt: Date(timeIntervalSince1970: 100))
    run.update(ValidationRunStepID.selectedTV, status: .passed, note: "Selected.", at: Date(timeIntervalSince1970: 101))
    run.skipPending(reason: "Stopped early.", at: Date(timeIntervalSince1970: 102))
    let report = run.makeReport(for: device, updatedAt: Date(timeIntervalSince1970: 200))

    let didRecordValidation = device.recordSuccessfulValidation(from: report)
    #expect(!didRecordValidation)
    #expect(!device.isValidatedOnPhysicalDevice)
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

@Test
func remoteActivityLayoutDefaultsToHybridWhenMissingOrInvalid() {
    let suite = makeSuite("pult.tests.remote-activity-layout-default")
    let store = RemoteActivityLayoutStore(defaults: suite)

    #expect(store.load() == .hybrid)

    suite.set("future-layout", forKey: RemoteActivityLayoutStore.key)

    #expect(store.load() == .hybrid)
}

@Test
func remoteActivityLayoutPersistsMediaSelection() {
    let suite = makeSuite("pult.tests.remote-activity-layout-save")
    let store = RemoteActivityLayoutStore(defaults: suite)

    store.save(.media)

    #expect(suite.string(forKey: RemoteActivityLayoutStore.key) == RemoteActivityLayout.media.rawValue)
    #expect(store.load() == .media)
}

@Test
func remoteActivityLayoutProvidesSettingsCopy() {
    #expect(RemoteActivityLayout.hybrid.displayTitle == "Hybrid")
    #expect(RemoteActivityLayout.media.displayTitle == "Media")
    #expect(RemoteActivityLayout.hybrid.settingsDescription.contains("D-pad"))
    #expect(RemoteActivityLayout.media.settingsDescription.contains("Playback"))
}
