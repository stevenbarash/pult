import Foundation
import Testing
@testable import PultCore

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("command-timing-tests-\(UUID().uuidString)", isDirectory: true)
}

private func timing(_ key: String, at seconds: TimeInterval, dialed: Bool = true) -> CommandTiming {
    CommandTiming(
        key: key,
        startedAt: Date(timeIntervalSince1970: seconds),
        totalMs: 100,
        dialed: dialed,
        tcpTlsMs: dialed ? 50 : nil,
        configureMs: dialed ? 40 : nil,
        processAgeMs: 5_000,
        succeeded: true
    )
}

@Test
func recentReturnsSamplesNewestFirst() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = CommandTimingLog(directory: dir)

    log.record(timing("a", at: 10))
    log.record(timing("b", at: 20))
    log.record(timing("c", at: 30))

    #expect(log.recent().map(\.key) == ["c", "b", "a"])
}

@Test
func recordEvictsOldestBeyondMaxSamples() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = CommandTimingLog(directory: dir, maxSamples: 2)

    log.record(timing("a", at: 10))
    log.record(timing("b", at: 20))
    log.record(timing("c", at: 30))

    #expect(log.recent().map(\.key) == ["c", "b"])
}

@Test
func clearRemovesAllSamples() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = CommandTimingLog(directory: dir)

    log.record(timing("a", at: 10))
    log.clear()

    #expect(log.recent().isEmpty)
}

@Test
func recentIsEmptyWhenDirectoryMissing() {
    let log = CommandTimingLog(directory: tempDir())
    #expect(log.recent().isEmpty)
}
