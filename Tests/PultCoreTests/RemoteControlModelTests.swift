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

@MainActor
@Test
func prepareTextEntryConnectsAndRequestsTvSearchWhenNoFieldIsFocused() async throws {
    let store = MemoryDeviceStore()
    let device = DeviceRecord(name: "Living Room", host: "10.0.0.2", isPaired: true)
    store.records = [device]
    store.selectedID = device.id
    let transport = MockTransport()
    let model = RemoteControlModel(
        discovery: DeviceDiscovery(store: store),
        session: RemoteSession(transport: transport, configureTimeout: .milliseconds(200))
    )
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))

    let prepare = Task { await model.prepareTextEntry(timeout: .milliseconds(200)) }
    var sent = await transport.waitForSent(count: 2)
    #expect(sent.count >= 2)
    #expect(sent[1] == framer.frame(try codec.encode(.key(.search, .tap))))

    await transport.enqueueIncoming(framer.frame(remoteImeShowRequestFrame(counter: 11)))
    let result = await prepare.value

    #expect(result == .ready)
    #expect(model.session.textFieldStatus?.counter == 11)
    sent = await transport.waitForSent(count: 2)
    #expect(sent.count == 2)
}

private let framer = VarintFramer()
private let codec = AndroidTVRemoteMessageCodec()
private let tvConfigureFrame = Data([0x0A, 0x02, 0x08, 0x01])

private func remoteImeShowRequestFrame(counter: Int) -> Data {
    var status = ProtobufEncoder()
    status.appendVarint(field: 1, UInt64(counter))
    status.appendString(field: 2, "")
    status.appendVarint(field: 3, 0)
    status.appendVarint(field: 4, 0)
    status.appendVarint(field: 5, 0)
    status.appendString(field: 6, "Search")

    var showRequest = ProtobufEncoder()
    showRequest.appendMessage(field: 2, status.data)

    var message = ProtobufEncoder()
    message.appendMessage(field: 22, showRequest.data)
    return message.data
}
