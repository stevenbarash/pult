import Foundation
import Testing
@testable import PultCore

@MainActor
@Test
func trimsHostAndFallsBackToHostForWhitespaceName() {
    let discovery = DeviceDiscovery(store: MemoryDeviceStore())

    let added = discovery.addManualDevice(name: "  ", host: " 192.168.1.42 ")

    #expect(added?.name == "192.168.1.42")
    #expect(added?.host == "192.168.1.42")
    #expect(added?.source == .manual)
}

@MainActor
@Test
func whitespaceRenameKeepsExistingName() {
    let discovery = DeviceDiscovery(store: MemoryDeviceStore())
    discovery.addManualDevice(name: "Living Room", host: "192.168.1.42")

    let renamed = discovery.addManualDevice(name: "   ", host: "192.168.1.42")

    #expect(renamed?.name == "Living Room")
    #expect(discovery.devices.count == 1)
}

@MainActor
@Test
func rejectsBlankHost() {
    let discovery = DeviceDiscovery(store: MemoryDeviceStore())

    #expect(discovery.addManualDevice(name: "TV", host: "   ") == nil)
    #expect(discovery.devices.isEmpty)
}

@MainActor
@Test
func movesSavedDevicesAndPersistsOrder() {
    let store = MemoryDeviceStore()
    let discovery = DeviceDiscovery(store: store)
    _ = discovery.addManualDevice(name: "Living Room", host: "192.168.1.42")
    _ = discovery.addManualDevice(name: "Bedroom", host: "192.168.1.43")
    _ = discovery.addManualDevice(name: "Office", host: "192.168.1.44")

    discovery.moveDevices(fromOffsets: IndexSet(integer: 2), toOffset: 0)

    #expect(discovery.devices.map(\.name) == ["Office", "Living Room", "Bedroom"])
    #expect(store.records.map(\.name) == ["Office", "Living Room", "Bedroom"])
}

@MainActor
@Test
func deletingSelectedDeviceFallsBackToFirstRemainingDevice() {
    let discovery = DeviceDiscovery(store: MemoryDeviceStore())
    let first = discovery.addManualDevice(name: "Living Room", host: "192.168.1.42")
    let second = discovery.addManualDevice(name: "Bedroom", host: "192.168.1.43")
    discovery.selectedDeviceID = second?.id

    let removed = discovery.deleteDevices(atOffsets: IndexSet(integer: 1))

    #expect(removed.first?.id == second?.id)
    #expect(discovery.devices.first?.id == first?.id)
    #expect(discovery.devices.count == 1)
    #expect(discovery.selectedDeviceID == first?.id)
}

@MainActor
@Test
func discoveredDeviceAddsAndUpdatesSavedDevice() {
    let store = MemoryDeviceStore()
    let discovery = DeviceDiscovery(store: store)
    let first = DiscoveredDevice(
        name: "Living Room TV",
        host: "living-room.local",
        commandPort: 6466,
        pairingPort: 6467,
        serviceName: "Living Room TV",
        serviceType: "_androidtvremote2._tcp."
    )

    let saved = discovery.addDiscoveredDevice(first)
    let updated = discovery.addDiscoveredDevice(
        DiscoveredDevice(
            name: "Den TV",
            host: "living-room.local",
            commandPort: 6466,
            pairingPort: 6467,
            serviceName: "Den TV",
            serviceType: "_androidtvremote2._tcp."
        )
    )

    #expect(saved?.id == updated?.id)
    #expect(discovery.devices.count == 1)
    #expect(discovery.devices.first?.name == "Den TV")
    #expect(store.records.first?.host == "living-room.local")
    #expect(store.records.first?.source == .bonjour)
    #expect(discovery.presence(for: updated!) == .saved)
}

@MainActor
@Test
func legacyDeviceRecordDecodesAsManualSource() throws {
    let data = Data("""
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "name": "Old TV",
      "host": "10.0.0.5",
      "commandPort": 6466,
      "pairingPort": 6467,
      "lastSeen": "2026-06-11T00:00:00Z",
      "isPaired": false
    }
    """.utf8)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(DeviceRecord.self, from: data)

    #expect(decoded.source == .manual)
}

@MainActor
@Test
func discoveryRecordsSuccessfulPhysicalValidation() throws {
    let store = MemoryDeviceStore()
    let discovery = DeviceDiscovery(store: store)
    let device = try #require(discovery.addManualDevice(name: "TV", host: "10.0.0.5"))
    var run = ValidationRunState(startedAt: Date(timeIntervalSince1970: 100))
    for item in run.items {
        run.update(item.id, status: .passed, note: "Checked.", at: Date(timeIntervalSince1970: 101))
    }
    let report = run.makeReport(for: device, updatedAt: Date(timeIntervalSince1970: 200))

    let validation = try #require(discovery.recordSuccessfulValidation(from: report))

    #expect(validation.deviceID == device.id)
    #expect(discovery.devices.first?.lastSuccessfulValidation?.validatedAt == Date(timeIntervalSince1970: 200))
    #expect(store.records.first?.lastSuccessfulValidation?.deviceName == "TV")
}

@MainActor
@Test
func reachabilityProbeUpdatesSavedDeviceState() async {
    let discovery = DeviceDiscovery(
        store: MemoryDeviceStore(),
        reachabilityProbe: StaticReachabilityProbe(result: .reachable(Date(timeIntervalSince1970: 0)))
    )
    let device = discovery.addManualDevice(name: "TV", host: "10.0.0.5")!

    let result = await discovery.checkReachability(for: device)

    #expect(result.isReachable)
    #expect(discovery.reachability(for: device).isReachable)
}
