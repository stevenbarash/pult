import Foundation

/// File-backed, bounded ring buffer of `CommandTiming` samples kept in the App
/// Group container so the Lock Screen intent process can write while the
/// foreground app reads. One file per sample, written atomically, so concurrent
/// writers from two processes never corrupt a shared structure — losing an
/// occasional sample is acceptable; corruption is not.
public struct CommandTimingLog: Sendable {
    public let directory: URL
    public let maxSamples: Int

    public init(directory: URL, maxSamples: Int = 50) {
        self.directory = directory
        self.maxSamples = maxSamples
    }

    /// The default log: a "command-timings" subdirectory of the App Group
    /// container, or nil when the container is unavailable (e.g. SwiftPM tests
    /// without the entitlement).
    public static func appGroup() -> CommandTimingLog? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PultAppGroup.identifier
        ) else { return nil }
        return CommandTimingLog(
            directory: container.appendingPathComponent("command-timings", isDirectory: true)
        )
    }

    public func record(_ timing: CommandTiming) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(timing)
            let stamp = Int(timing.startedAt.timeIntervalSince1970 * 1_000)
            let url = directory.appendingPathComponent("\(stamp)-\(timing.id.uuidString).json")
            try data.write(to: url, options: .atomic)
            prune()
        } catch {
            // Measurement is best-effort: never let logging affect a command.
        }
    }

    public func recent(limit: Int = 50) -> [CommandTiming] {
        Array(sortedEntries().prefix(limit).map(\.timing))
    }

    public func clear() {
        for url in jsonURLs() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func prune() {
        let entries = sortedEntries() // newest first
        guard entries.count > maxSamples else { return }
        for entry in entries.dropFirst(maxSamples) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    private func jsonURLs() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls.filter { $0.pathExtension == "json" }
    }

    private func sortedEntries() -> [(url: URL, timing: CommandTiming)] {
        jsonURLs()
            .compactMap { url -> (url: URL, timing: CommandTiming)? in
                guard let data = try? Data(contentsOf: url),
                      let timing = try? JSONDecoder().decode(CommandTiming.self, from: data)
                else { return nil }
                return (url, timing)
            }
            .sorted { $0.timing.startedAt > $1.timing.startedAt }
    }
}
