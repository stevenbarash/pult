import Foundation
import Testing
@testable import PultCore

@Test
func processClockAgeIsNonNegativeAndAdvances() async throws {
    let first = ProcessClock.ageMilliseconds
    try await Task.sleep(for: .milliseconds(20))
    let second = ProcessClock.ageMilliseconds

    #expect(first >= 0)
    #expect(second >= first)
}

private let framer = VarintFramer()
private let tvConfigureFrame = Data([0x0A, 0x02, 0x08, 0x01])

final class CapturingTimingRecorder: CommandTimingRecording, @unchecked Sendable {
    let enabled: Bool
    private let lock = NSLock()
    private var samples: [CommandTiming] = []

    init(enabled: Bool) { self.enabled = enabled }

    var isEnabled: Bool { enabled }

    func record(_ timing: CommandTiming) {
        lock.lock(); defer { lock.unlock() }
        samples.append(timing)
    }

    var recorded: [CommandTiming] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }
}

@MainActor
private func makeModel(
    transport: any RemoteTransport,
    device: DeviceRecord,
    recorder: CommandTimingRecording
) -> RemoteControlModel {
    let store = MemoryDeviceStore()
    store.records = [device]
    store.selectedID = device.id
    return RemoteControlModel(
        discovery: DeviceDiscovery(store: store),
        session: RemoteSession(transport: transport, configureTimeout: .milliseconds(200)),
        timingRecorder: recorder
    )
}

@MainActor
@Test
func recorderCapturesColdThenWarmCommands() async throws {
    let transport = MockTransport()
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: true)
    let recorder = CapturingTimingRecorder(enabled: true)
    let model = makeModel(transport: transport, device: device, recorder: recorder)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))

    // First command dials (COLD).
    #expect(await model.sendKey(.volumeUp) == .sent)
    // Second command reuses the live session (WARM).
    #expect(await model.sendKey(.volumeUp) == .sent)

    #expect(recorder.recorded.count == 2)
    #expect(recorder.recorded[0].dialed == true)
    #expect(recorder.recorded[0].key == "volumeUp")
    #expect(recorder.recorded[0].succeeded == true)
    #expect(recorder.recorded[0].tcpTlsMs != nil)
    #expect(recorder.recorded[1].dialed == false)
    #expect(recorder.recorded[1].tcpTlsMs == nil)
}

@MainActor
@Test
func disabledRecorderCapturesNothing() async {
    let transport = MockTransport()
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: true)
    let recorder = CapturingTimingRecorder(enabled: false)
    let model = makeModel(transport: transport, device: device, recorder: recorder)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))

    #expect(await model.sendKey(.volumeUp) == .sent)

    #expect(recorder.recorded.isEmpty)
}
