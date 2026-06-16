import Foundation
import Testing
@testable import PultCore

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("recorder-tests-\(UUID().uuidString)", isDirectory: true)
}

private func sampleTiming() -> CommandTiming {
    CommandTiming(
        key: "volumeUp",
        startedAt: Date(timeIntervalSince1970: 100),
        totalMs: 200,
        dialed: true,
        tcpTlsMs: 100,
        configureMs: 80,
        processAgeMs: 5_000,
        succeeded: true
    )
}

@Test
func recorderDoesNothingWhenFlagDisabled() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let defaults = UserDefaults(suiteName: "recorder-test-\(UUID().uuidString)")!
    defaults.set(false, forKey: CommandTimingRecorder.enabledDefaultsKey)
    let recorder = CommandTimingRecorder(log: CommandTimingLog(directory: dir), defaults: defaults)

    #expect(recorder.isEnabled == false)
    recorder.record(sampleTiming())

    #expect(CommandTimingLog(directory: dir).recent().isEmpty)
}

@Test
func recorderWritesToLogWhenFlagEnabled() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let defaults = UserDefaults(suiteName: "recorder-test-\(UUID().uuidString)")!
    defaults.set(true, forKey: CommandTimingRecorder.enabledDefaultsKey)
    let recorder = CommandTimingRecorder(log: CommandTimingLog(directory: dir), defaults: defaults)

    #expect(recorder.isEnabled == true)
    recorder.record(sampleTiming())

    #expect(CommandTimingLog(directory: dir).recent().map(\.key) == ["volumeUp"])
}
