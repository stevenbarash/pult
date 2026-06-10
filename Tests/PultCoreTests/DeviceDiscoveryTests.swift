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
