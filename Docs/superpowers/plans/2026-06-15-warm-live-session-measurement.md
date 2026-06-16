# Warm Live Session — Measurement Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add measurement-only instrumentation that times each phase of the Lock Screen command path (`resolve → tcp+tls → configure → send`), tags each command WARM/COLD, counts live volume pushes, and surfaces it all in an on-device Diagnostics readout plus `os_signpost` — so real-TV numbers decide which warm-session mechanisms ship.

**Architecture:** New value/storage/recorder types in `PultCore` (`CommandTiming`, `CommandTimingLog`, `CommandTimingRecorder`) write one JSON file per sample into the App Group container, so the headless-intent process can write and the foreground app can read without cross-process corruption. `RemoteSession` and `RemoteControlModel` gain purely-additive timestamp capture; the recorder is gated by a runtime flag in App Group defaults that a new Diagnostics toggle controls, so nothing is recorded for normal users. No command behavior changes.

**Tech Stack:** Swift 6, `@Observable`/`@MainActor`, `ContinuousClock`/`Duration`, `os` (`OSSignposter`), `UserDefaults` App Group suite, SwiftUI (Diagnostics), swift-testing (`import Testing`, `@Test`, `#expect`).

**Spec:** `Docs/superpowers/specs/2026-06-15-warm-live-session-design.md`

---

## Key facts the implementer must respect

- **Measurement must never change command behavior.** All edits to `RemoteSession`/`RemoteControlModel` are additive (extra timestamp reads + recording). The command control flow is preserved verbatim.
- **Tests use swift-testing**, not XCTest: `import Testing`, `@Test`, `#expect(...)`, `@MainActor` on async UI/actor tests, `Issue.record(...)` for forced failures. Shared doubles live in `Tests/PultCoreTests/TestSupport.swift`.
- **Run tests with** `make test` (which runs `swift test --disable-sandbox`). Run a single test with `swift test --disable-sandbox --filter <testFuncName>`.
- **Volume decode frame** (already supported by the codec): `Data([0x92, 0x03, 0x06, 0x30, 0x64, 0x38, 0x19, 0x40, 0x01])` decodes to `.volume(level: 25, maximum: 100, muted: true)`.
- **Configure frame:** `Data([0x0A, 0x02, 0x08, 0x01])`.
- **`RemoteKey` is `enum RemoteKey: String`** — `.volumeUp.rawValue == "volumeUp"`.
- **New Swift files must be registered in `Pult.xcodeproj`** for the simulator/device build (`make verify-full`). `swift test`/`make test` use SwiftPM and do NOT need the project edit, so do TDD against `make test` first and register files in Task 8.
- Commit messages end with the trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File Structure

**Create (PultCore):**
- `Sources/PultCore/CommandTiming.swift` — the per-command timing value type + a `Duration.millisecondsValue` helper. One responsibility: the data shape + its display strings.
- `Sources/PultCore/CommandTimingLog.swift` — file-backed bounded ring buffer in the App Group container. One responsibility: durable, cross-process storage of samples.
- `Sources/PultCore/CommandTimingRecorder.swift` — the `CommandTimingRecording` protocol + concrete recorder (log + signpost + runtime flag). One responsibility: deciding whether/where to record.
- `Sources/PultCore/ProcessClock.swift` — process-age heuristic for fresh-launch detection.

**Create (tests):**
- `Tests/PultCoreTests/CommandTimingTests.swift`
- `Tests/PultCoreTests/CommandTimingLogTests.swift`
- `Tests/PultCoreTests/CommandTimingRecorderTests.swift`
- `Tests/PultCoreTests/CommandTimingModelTests.swift`

**Modify:**
- `Sources/PultCore/RemoteSession.swift` — additive dial-phase timestamps, volume-push counters, signpost intervals.
- `Sources/PultCore/RemoteControlModel.swift` — additive measurement wrapper around the existing command body; new injected `timingRecorder`.
- `Sources/PultApp/DiagnosticsAndValidationView.swift` — a "Command Timing" section (toggle + readout + clear).
- `Sources/PultApp/PultApp.swift` and `Sources/PultApp/RemoteIntents.swift` — touch `ProcessClock.start` early (one line each).
- `Pult.xcodeproj/project.pbxproj` — register the four new PultCore files (Task 8).
- `Tests/PultCoreTests/RemoteSessionTests.swift` — add two tests for the new session counters.

---

### Task 1: `CommandTiming` value type + `Duration.millisecondsValue`

**Files:**
- Create: `Sources/PultCore/CommandTiming.swift`
- Test: `Tests/PultCoreTests/CommandTimingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PultCoreTests/CommandTimingTests.swift`:

```swift
import Foundation
import Testing
@testable import PultCore

@Test
func coldTimingSummaryAndDetailFormatWithPhases() {
    let timing = CommandTiming(
        key: "volumeUp",
        startedAt: Date(timeIntervalSince1970: 1_000),
        totalMs: 312,
        dialed: true,
        tcpTlsMs: 181,
        configureMs: 121,
        processAgeMs: 5_000,
        succeeded: true
    )

    #expect(timing.classification == "COLD")
    #expect(timing.summaryLine == "volumeUp  COLD  312 ms")
    #expect(timing.detailLine == "tcp+tls 181 · configure 121 · send ~10")
    #expect(timing.likelyFreshLaunch == false)
}

@Test
func warmTimingReportsReusedSocketAndFreshLaunchHeuristic() {
    let timing = CommandTiming(
        key: "home",
        startedAt: Date(timeIntervalSince1970: 2_000),
        totalMs: 1_400,
        dialed: true,
        tcpTlsMs: 410,
        configureMs: 690,
        processAgeMs: 800,
        succeeded: true
    )
    #expect(timing.summaryLine == "home  COLD  1.4 s")
    #expect(timing.likelyFreshLaunch == true)

    let warm = CommandTiming(
        key: "mute",
        startedAt: Date(timeIntervalSince1970: 3_000),
        totalMs: 14,
        dialed: false,
        tcpTlsMs: nil,
        configureMs: nil,
        processAgeMs: 60_000,
        succeeded: true
    )
    #expect(warm.classification == "WARM")
    #expect(warm.detailLine == "reused socket · send ~14")
}

@Test
func durationMillisecondsValueConvertsSecondsAndFraction() {
    #expect(Duration.milliseconds(250).millisecondsValue == 250)
    #expect(Duration.seconds(2).millisecondsValue == 2_000)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test` (or `swift test --disable-sandbox --filter coldTimingSummaryAndDetailFormatWithPhases`)
Expected: FAIL — `cannot find 'CommandTiming' in scope` / `value of type 'Duration' has no member 'millisecondsValue'`.

- [ ] **Step 3: Write the implementation**

Create `Sources/PultCore/CommandTiming.swift`:

```swift
import Foundation

extension Duration {
    /// This duration as a floating-point count of milliseconds.
    var millisecondsValue: Double {
        let c = components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1_000_000_000_000_000
    }
}

/// One Lock Screen / headless command's connect-and-send timing, captured by
/// the measurement pass. Pure data: written to the shared timing log and read
/// back by the in-app Diagnostics readout. Measurement only — it never gates or
/// changes command behavior.
public struct CommandTiming: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    /// RemoteKey raw value, e.g. "volumeUp", or "appLink".
    public let key: String
    /// Wall-clock start, used only for display ordering.
    public let startedAt: Date
    /// Entry-to-sent wall time in milliseconds.
    public let totalMs: Double
    /// True when the command had to dial the TV (COLD); false when it reused a
    /// live socket (WARM).
    public let dialed: Bool
    /// TCP + mutual-TLS handshake time, present only when `dialed`.
    public let tcpTlsMs: Double?
    /// Protocol `configure` handshake time, present only when `dialed`.
    public let configureMs: Double?
    /// Milliseconds since this process first touched the remote stack — a
    /// fresh-launch heuristic, not an exact process age.
    public let processAgeMs: Double
    /// Whether the command was delivered.
    public let succeeded: Bool

    public init(
        id: UUID = UUID(),
        key: String,
        startedAt: Date,
        totalMs: Double,
        dialed: Bool,
        tcpTlsMs: Double?,
        configureMs: Double?,
        processAgeMs: Double,
        succeeded: Bool
    ) {
        self.id = id
        self.key = key
        self.startedAt = startedAt
        self.totalMs = totalMs
        self.dialed = dialed
        self.tcpTlsMs = tcpTlsMs
        self.configureMs = configureMs
        self.processAgeMs = processAgeMs
        self.succeeded = succeeded
    }

    /// "WARM" or "COLD".
    public var classification: String { dialed ? "COLD" : "WARM" }

    /// Heuristic: the command arrived so soon after the process first touched
    /// the remote stack that the process was likely cold-launched for it.
    public var likelyFreshLaunch: Bool { processAgeMs < 1_500 }

    /// Milliseconds spent sending, derived as the remainder after the dial
    /// phases. Approximate (it also absorbs decision overhead).
    public var sendMsApprox: Double {
        max(totalMs - (tcpTlsMs ?? 0) - (configureMs ?? 0), 0)
    }

    private static func formatMs(_ value: Double) -> String {
        value >= 1_000
            ? String(format: "%.1f s", value / 1_000)
            : "\(Int(value.rounded())) ms"
    }

    /// e.g. "volumeUp  COLD  312 ms".
    public var summaryLine: String {
        "\(key)  \(classification)  \(Self.formatMs(totalMs))"
    }

    /// e.g. "tcp+tls 181 · configure 121 · send ~10" or "reused socket · send ~14".
    public var detailLine: String {
        if dialed {
            let tcp = Int((tcpTlsMs ?? 0).rounded())
            let cfg = Int((configureMs ?? 0).rounded())
            let send = Int(sendMsApprox.rounded())
            let launch = likelyFreshLaunch ? " · fresh launch" : ""
            return "tcp+tls \(tcp) · configure \(cfg) · send ~\(send)\(launch)"
        } else {
            return "reused socket · send ~\(Int(sendMsApprox.rounded()))"
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make test`
Expected: PASS for the three new tests; existing suite still green.

- [ ] **Step 5: Commit**

```bash
git add Sources/PultCore/CommandTiming.swift Tests/PultCoreTests/CommandTimingTests.swift
git commit -m "$(cat <<'EOF'
feat: add CommandTiming value type for measurement pass

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `CommandTimingLog` file-backed ring buffer

**Files:**
- Create: `Sources/PultCore/CommandTimingLog.swift`
- Test: `Tests/PultCoreTests/CommandTimingLogTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PultCoreTests/CommandTimingLogTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'CommandTimingLog' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/PultCore/CommandTimingLog.swift`:

```swift
import Foundation

/// File-backed, bounded ring buffer of `CommandTiming` samples kept in the App
/// Group container so the Lock Screen intent process can write while the
/// foreground app reads. One file per sample, written atomically, so concurrent
/// writers from two processes never corrupt a shared structure — losing an
/// occasional sample is acceptable; corruption is not.
public struct CommandTimingLog: Sendable {
    public let directory: URL
    public let maxSamples: Int
    private let fileManager: FileManager

    public init(directory: URL, maxSamples: Int = 50, fileManager: FileManager = .default) {
        self.directory = directory
        self.maxSamples = maxSamples
        self.fileManager = fileManager
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
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
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
            try? fileManager.removeItem(at: url)
        }
    }

    private func prune() {
        let entries = sortedEntries() // newest first
        guard entries.count > maxSamples else { return }
        for entry in entries.dropFirst(maxSamples) {
            try? fileManager.removeItem(at: entry.url)
        }
    }

    private func jsonURLs() -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make test`
Expected: PASS for the four new tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/PultCore/CommandTimingLog.swift Tests/PultCoreTests/CommandTimingLogTests.swift
git commit -m "$(cat <<'EOF'
feat: add file-backed CommandTimingLog ring buffer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `CommandTimingRecording` protocol + `CommandTimingRecorder`

**Files:**
- Create: `Sources/PultCore/CommandTimingRecorder.swift`
- Test: `Tests/PultCoreTests/CommandTimingRecorderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PultCoreTests/CommandTimingRecorderTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'CommandTimingRecorder' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/PultCore/CommandTimingRecorder.swift`:

```swift
import Foundation
import os

/// Sink for `CommandTiming` samples. Injected into `RemoteControlModel` so the
/// hot command path can skip all measurement bookkeeping when disabled, and so
/// tests can capture timings.
public protocol CommandTimingRecording: Sendable {
    /// Whether timings are currently being recorded.
    var isEnabled: Bool { get }
    func record(_ timing: CommandTiming)
}

/// Records command timings to the shared App Group log and emits an
/// `os_signpost` event per command. Gated by a runtime flag in App Group
/// defaults that the Diagnostics screen toggles, so it never writes for normal
/// TestFlight users.
public struct CommandTimingRecorder: CommandTimingRecording {
    public static let enabledDefaultsKey = "pult.measureTimings"

    private let log: CommandTimingLog?
    private let defaults: UserDefaults
    private let signposter: OSSignposter

    public init(
        log: CommandTimingLog? = CommandTimingLog.appGroup(),
        defaults: UserDefaults = PultAppGroup.sharedDefaults()
    ) {
        self.log = log
        self.defaults = defaults
        self.signposter = OSSignposter(subsystem: "app.pult", category: "command-timing")
    }

    public var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    public func record(_ timing: CommandTiming) {
        guard isEnabled else { return }
        signposter.emitEvent(
            "command",
            "\(timing.key, privacy: .public) \(timing.classification, privacy: .public) \(Int(timing.totalMs.rounded()))ms"
        )
        log?.record(timing)
    }

    /// Reads the runtime flag (used by the Diagnostics toggle).
    public static func isEnabled(defaults: UserDefaults = PultAppGroup.sharedDefaults()) -> Bool {
        defaults.bool(forKey: enabledDefaultsKey)
    }

    /// Sets the runtime flag (used by the Diagnostics toggle).
    public static func setEnabled(_ enabled: Bool, defaults: UserDefaults = PultAppGroup.sharedDefaults()) {
        defaults.set(enabled, forKey: enabledDefaultsKey)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make test`
Expected: PASS for both new tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/PultCore/CommandTimingRecorder.swift Tests/PultCoreTests/CommandTimingRecorderTests.swift
git commit -m "$(cat <<'EOF'
feat: add flag-gated CommandTimingRecorder with signposts

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `ProcessClock` fresh-launch heuristic

**Files:**
- Create: `Sources/PultCore/ProcessClock.swift`
- Test: `Tests/PultCoreTests/CommandTimingModelTests.swift` (one test now; more added in Task 6)

- [ ] **Step 1: Write the failing test**

Create `Tests/PultCoreTests/CommandTimingModelTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --disable-sandbox --filter processClockAgeIsNonNegativeAndAdvances`
Expected: FAIL — `cannot find 'ProcessClock' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/PultCore/ProcessClock.swift`:

```swift
import Foundation

/// Captures roughly when this process first touched the remote stack, used as a
/// fresh-launch heuristic in command timings. A static `let` initializes on
/// first access, so the app and the Lock Screen intent touch `start` as early
/// as possible (see PultApp / RemoteIntents). It is not an exact process age.
public enum ProcessClock {
    public static let start = ContinuousClock.now

    public static var ageMilliseconds: Double {
        start.duration(to: .now).millisecondsValue
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --disable-sandbox --filter processClockAgeIsNonNegativeAndAdvances`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PultCore/ProcessClock.swift Tests/PultCoreTests/CommandTimingModelTests.swift
git commit -m "$(cat <<'EOF'
feat: add ProcessClock fresh-launch heuristic

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Instrument `RemoteSession` (dial phases, volume pushes, signposts)

**Files:**
- Modify: `Sources/PultCore/RemoteSession.swift`
- Test: `Tests/PultCoreTests/RemoteSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/PultCoreTests/RemoteSessionTests.swift`:

```swift
@MainActor
@Test
func connectRecordsDialPhaseDurations() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))

    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))

    #expect(session.connectionState == .connected)
    #expect(session.lastTCPTLSMilliseconds != nil)
    #expect(session.lastConfigureMilliseconds != nil)
}

@MainActor
@Test
func volumePushUpdatesCountAndTimestamp() async throws {
    let volumeFrame = Data([0x92, 0x03, 0x06, 0x30, 0x64, 0x38, 0x19, 0x40, 0x01])
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))
    await transport.enqueueIncoming(framer.frame(volumeFrame))

    await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))

    // The read loop delivers the volume frame shortly after configure.
    for _ in 0..<100 where session.volumePushCount == 0 {
        try await Task.sleep(for: .milliseconds(5))
    }

    #expect(session.volumePushCount == 1)
    #expect(session.volumeStatus?.level == 25)
    #expect(session.volumeStatus?.maximum == 100)
    #expect(session.volumeStatus?.muted == true)
    #expect(session.lastVolumePushAt != nil)
}
```

Note: `framer` and `tvConfigureFrame` are already defined at the top of `RemoteSessionTests.swift`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --disable-sandbox --filter connectRecordsDialPhaseDurations`
Expected: FAIL — `value of type 'RemoteSession' has no member 'lastTCPTLSMilliseconds'`.

- [ ] **Step 3: Add the `os` import and signposter**

In `Sources/PultCore/RemoteSession.swift`, change the imports at the top:

```swift
import Foundation
import Observation
import os
```

Add the signposter as a stored property inside `RemoteSession`, right after `private var nextImeCounter = 0`:

```swift
    private let dialSignposter = OSSignposter(subsystem: "app.pult", category: "dial")
```

- [ ] **Step 4: Add the new observable counters**

In `RemoteSession`, immediately after the `lastSentAt` declaration (the line `public private(set) var lastSentAt: Date?`), add:

```swift
    /// TCP + mutual-TLS handshake duration (ms) of the most recent dial.
    /// Measurement only — nil until the first dial.
    public private(set) var lastTCPTLSMilliseconds: Double?
    /// Protocol `configure` handshake duration (ms) of the most recent dial.
    public private(set) var lastConfigureMilliseconds: Double?
    /// Count of inbound volume pushes seen this app run (measurement readout).
    public private(set) var volumePushCount: Int = 0
    /// When the most recent volume push arrived.
    public private(set) var lastVolumePushAt: Date?
```

- [ ] **Step 5: Reset the dial durations at connect start**

In `connect(to:)`, find the reset block (the lines setting `volumeStatus = nil`, `lastReceivedAt = nil`, `lastSentAt = nil`). Add two resets right after `lastSentAt = nil`:

```swift
        lastReceivedAt = nil
        lastSentAt = nil
        lastTCPTLSMilliseconds = nil
        lastConfigureMilliseconds = nil
        nextImeCounter = 0
```

(Do NOT reset `volumePushCount`/`lastVolumePushAt` — they are cumulative across the app run.)

- [ ] **Step 6: Capture the dial-phase durations in `performConnect`**

Replace the body of `performConnect(to:attempt:)` with this instrumented version (control flow is unchanged; only timestamp capture + signpost intervals are added):

```swift
    private func performConnect(to device: DeviceRecord, attempt: Int) async {
        readTask?.cancel()
        readTask = nil
        await transport.close()
        guard attempt == connectAttempt else { return }

        let tcpState = dialSignposter.beginInterval("tcp+tls")
        let tcpStart = ContinuousClock.now
        do {
            try await transport.connect(to: device.host, port: device.commandPort)
        } catch {
            dialSignposter.endInterval("tcp+tls", tcpState)
            fail(with: "Could not reach \(device.host): \(describe(error))", attempt: attempt)
            return
        }
        lastTCPTLSMilliseconds = tcpStart.duration(to: .now).millisecondsValue
        dialSignposter.endInterval("tcp+tls", tcpState)
        guard attempt == connectAttempt else { return }

        startReadLoop(attempt: attempt)
        let configureState = dialSignposter.beginInterval("configure")
        let configureStart = ContinuousClock.now
        await waitForConfiguration(attempt: attempt)
        lastConfigureMilliseconds = configureStart.duration(to: .now).millisecondsValue
        dialSignposter.endInterval("configure", configureState)
    }
```

- [ ] **Step 7: Count volume pushes in `handle`**

In `handle(_:attempt:)`, replace the `.volume` case:

```swift
        case let .volume(level, maximum, muted):
            volumeStatus = RemoteVolumeStatus(level: level, maximum: maximum, muted: muted)
            volumePushCount += 1
            lastVolumePushAt = .now
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `swift test --disable-sandbox --filter connectRecordsDialPhaseDurations`
then: `swift test --disable-sandbox --filter volumePushUpdatesCountAndTimestamp`
Expected: PASS. Then run the full session suite: `swift test --disable-sandbox --filter RemoteSession` and confirm no regressions.

- [ ] **Step 9: Commit**

```bash
git add Sources/PultCore/RemoteSession.swift Tests/PultCoreTests/RemoteSessionTests.swift
git commit -m "$(cat <<'EOF'
feat: instrument RemoteSession dial phases and volume pushes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Instrument `RemoteControlModel.executeRemoteAction`

**Files:**
- Modify: `Sources/PultCore/RemoteControlModel.swift`
- Test: `Tests/PultCoreTests/CommandTimingModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/PultCoreTests/CommandTimingModelTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --disable-sandbox --filter recorderCapturesColdThenWarmCommands`
Expected: FAIL — `extra argument 'timingRecorder' in call` (the init does not accept it yet).

- [ ] **Step 3: Add the injected recorder to `RemoteControlModel`**

In `Sources/PultCore/RemoteControlModel.swift`, add a stored property after `private var headlessTask: Task<HeadlessCommandOutcome, Never>?`:

```swift
    private let timingRecorder: any CommandTimingRecording
```

Add a `timingRecorder` parameter to `init` (last parameter, with a default) and assign it. The new initializer signature and the added assignment:

```swift
    public init(
        discovery: DeviceDiscovery = DeviceDiscovery(),
        session: RemoteSession = RemoteSession(),
        identityProvider: any ClientIdentityProviding = KeychainClientIdentityStore.shared,
        makePairingTransport: @escaping @Sendable () -> any RemoteTransport = { NetworkRemoteTransport() },
        timingRecorder: any CommandTimingRecording = CommandTimingRecorder()
    ) {
        self.discovery = discovery
        self.session = session
        self.identityProvider = identityProvider
        self.makePairingTransport = makePairingTransport
        self.timingRecorder = timingRecorder
        self.selectedDevice = discovery.devices.first(where: { $0.id == discovery.selectedDeviceID })
            ?? discovery.devices.first
        discovery.selectedDeviceID = selectedDevice?.id
    }
```

- [ ] **Step 4: Add `timingKey` to the private `RemoteAction` enum**

Replace the `private enum RemoteAction` declaration with:

```swift
    private enum RemoteAction: Equatable, Sendable {
        case key(RemoteKey, KeyAction)
        case appLink(URL)

        var timingKey: String {
            switch self {
            case let .key(key, _): key.rawValue
            case .appLink: "appLink"
            }
        }
    }

    /// Reference flag the inner command body flips when it dials, so the
    /// measurement wrapper can classify WARM vs COLD without changing control
    /// flow. MainActor-isolated, single-threaded use.
    private final class DialFlag {
        var dialed: Bool
        init(_ dialed: Bool) { self.dialed = dialed }
    }
```

- [ ] **Step 5: Wrap the command body with measurement**

Rename the existing `executeRemoteAction(_:staleAfter:)` method to `runRemoteAction(_:staleAfter:dialFlag:)`, and add the new `executeRemoteAction` wrapper in front of it. Replace the whole existing `executeRemoteAction` method (the one with the doc comment "Ensures a fresh connection, sends once...") with the following two methods:

```swift
    /// Measurement wrapper around the command body. When timing is disabled it
    /// calls straight through with zero added work. When enabled it records one
    /// `CommandTiming` per command, classifying WARM vs COLD. It never changes
    /// the command result or control flow.
    private func executeRemoteAction(
        _ action: RemoteAction,
        staleAfter idleTimeout: TimeInterval
    ) async -> HeadlessCommandOutcome {
        guard timingRecorder.isEnabled else {
            return await runRemoteAction(action, staleAfter: idleTimeout, dialFlag: nil)
        }

        let willDial = selectedDevice.map {
            session.needsConnectionRefresh(for: $0, idleTimeout: idleTimeout)
        } ?? true
        let flag = DialFlag(willDial)
        let startedAt = Date()
        let clockStart = ContinuousClock.now

        let outcome = await runRemoteAction(action, staleAfter: idleTimeout, dialFlag: flag)

        let totalMs = clockStart.duration(to: .now).millisecondsValue
        timingRecorder.record(
            CommandTiming(
                key: action.timingKey,
                startedAt: startedAt,
                totalMs: totalMs,
                dialed: flag.dialed,
                tcpTlsMs: flag.dialed ? session.lastTCPTLSMilliseconds : nil,
                configureMs: flag.dialed ? session.lastConfigureMilliseconds : nil,
                processAgeMs: ProcessClock.ageMilliseconds,
                succeeded: outcome == .sent
            )
        )
        return outcome
    }

    /// Ensures a fresh connection, sends once, then redials and retries once
    /// when a connected-looking session fails during the send. The retry limit
    /// prevents Lock Screen / Control Center commands from looping forever
    /// against a TV that is asleep or on another network.
    private func runRemoteAction(
        _ action: RemoteAction,
        staleAfter idleTimeout: TimeInterval,
        dialFlag: DialFlag?
    ) async -> HeadlessCommandOutcome {
        guard let selectedDevice, selectedDevice.isPaired else {
            return .failed("Open Pult and pair a TV first.")
        }

        await ensureFreshConnection(staleAfter: idleTimeout)
        if session.connectionState == .connected {
            let sent = await send(action)
            if sent, session.connectionState == .connected {
                return .sent
            }
        }

        // Fresh dial: either the first connect failed outright, or the press
        // above killed a stale connection.
        //
        // A send that fails on a dead socket almost certainly never reached the
        // TV, so resending on the fresh connection is safe for the common case.
        // In the rare window where delivery succeeded but the read loop flagged
        // death concurrently, a duplicated d-pad/volume key is harmless.
        await session.connect(to: selectedDevice)
        dialFlag?.dialed = true
        guard session.connectionState == .connected else {
            return .failed("Could not reach \(selectedDevice.name).")
        }
        let sent = await send(action)
        guard sent, session.connectionState == .connected else {
            return .failed("Lost the connection to \(selectedDevice.name).")
        }
        return .sent
    }
```

(The body of `runRemoteAction` is the original `executeRemoteAction` body verbatim, with exactly one added line: `dialFlag?.dialed = true` immediately after `await session.connect(to: selectedDevice)`.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --disable-sandbox --filter recorderCapturesColdThenWarmCommands`
then: `swift test --disable-sandbox --filter disabledRecorderCapturesNothing`
Expected: PASS.

- [ ] **Step 7: Run the full PultCore suite to confirm no behavior regression**

Run: `make test`
Expected: PASS — all existing tests (especially `HeadlessCommandTests`) still green, proving the command path is behavior-preserved.

- [ ] **Step 8: Commit**

```bash
git add Sources/PultCore/RemoteControlModel.swift Tests/PultCoreTests/CommandTimingModelTests.swift
git commit -m "$(cat <<'EOF'
feat: record command timing around the headless command path

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Diagnostics "Command Timing" section

**Files:**
- Modify: `Sources/PultApp/DiagnosticsAndValidationView.swift`
- Modify: `Sources/PultApp/PultApp.swift` (touch `ProcessClock.start`)
- Modify: `Sources/PultApp/RemoteIntents.swift` (touch `ProcessClock.start`)

This task is UI; the existing `DiagnosticsAndValidationView` has no unit tests, so it is verified by build. Keep the section native and quiet, matching the existing `DiagnosticValueRow` style.

- [ ] **Step 1: Add measurement state to the view**

In `DiagnosticsAndValidationView`, add two `@State` properties after `@State private var isRunningValidation = false`:

```swift
    @State private var isMeasuringTimings = CommandTimingRecorder.isEnabled()
    @State private var recentTimings: [CommandTiming] = []
```

Add a private constant for the log after the existing `private let validationStore = ...` line:

```swift
    private let timingLog = CommandTimingLog.appGroup()
```

- [ ] **Step 2: Add the Command Timing section to the List**

Insert this `Section` in `body`, immediately after the `Section { ... } header: { Text("Session") }` block (i.e. before the `Section { ... } header: { Text("Discovery") }` block):

```swift
                Section {
                    Toggle("Record Command Timing", isOn: $isMeasuringTimings)
                        .onChange(of: isMeasuringTimings) { _, enabled in
                            CommandTimingRecorder.setEnabled(enabled)
                            if enabled { statusMessage = "Recording command timing." }
                        }

                    DiagnosticValueRow(
                        "Volume Pushes",
                        value: volumePushSummary,
                        systemImage: "speaker.wave.2"
                    )

                    if recentTimings.isEmpty {
                        DiagnosticValueRow(
                            "Recent Commands",
                            value: isMeasuringTimings ? "None yet" : "Recording off",
                            systemImage: "clock"
                        )
                    } else {
                        ForEach(recentTimings) { timing in
                            CommandTimingRow(timing: timing)
                        }
                    }

                    Button("Refresh Timings", systemImage: "arrow.clockwise") {
                        reloadTimings()
                    }
                    Button("Clear Timings", systemImage: "trash", role: .destructive) {
                        timingLog?.clear()
                        recentTimings = []
                        statusMessage = "Cleared command timings."
                    }
                } header: {
                    Text("Command Timing")
                } footer: {
                    Text("Measurement only. Turn on, run the lock-screen test protocol, then read the WARM/COLD breakdown here. Turn off when done.")
                }
```

- [ ] **Step 3: Add the supporting computed property and reload method**

Add these to `DiagnosticsAndValidationView` (next to the other private helpers, e.g. after `private func format(_ date: Date?)`):

```swift
    private var volumePushSummary: String {
        let count = model.session.volumePushCount
        guard count > 0, let volume = model.session.volumeStatus else {
            return "None yet"
        }
        return "\(count) · last \(volume.level)/\(volume.maximum)\(volume.muted ? " muted" : "")"
    }

    private func reloadTimings() {
        recentTimings = timingLog?.recent(limit: 12) ?? []
    }
```

- [ ] **Step 4: Load timings when the screen appears**

In `body`, the `List` already has `.task(id: model.selectedDevice?.id) { loadPersistedValidationState() }`. Add a reload of timings inside that closure so the section is populated on appear. Change it to:

```swift
        .task(id: model.selectedDevice?.id) {
            loadPersistedValidationState()
            reloadTimings()
        }
```

- [ ] **Step 5: Add the `CommandTimingRow` view**

Add this private view at the bottom of the file, next to the other private `struct` views (e.g. after `private struct DiagnosticValueRow`):

```swift
private struct CommandTimingRow: View {
    let timing: CommandTiming

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: timing.dialed ? "bolt.slash" : "bolt.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(timing.dialed ? PultDesign.warning : PultDesign.connected)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(timing.summaryLine)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(timing.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timing.key), \(timing.classification), \(Int(timing.totalMs.rounded())) milliseconds")
    }
}
```

- [ ] **Step 6: Touch `ProcessClock.start` early in both processes**

In `Sources/PultApp/PultApp.swift`, find the app's `init()` (or the `@main` struct initializer). If there is no `init`, add one to the `App` struct. Add this as the first line of the initializer:

```swift
        _ = ProcessClock.start
```

In `Sources/PultApp/RemoteIntents.swift`, find the `SharedRemote` enum's `model` accessor (the process-wide singleton). Add `_ = ProcessClock.start` as the first statement where the model is first constructed, so the intent process pins its start time as early as possible. If `SharedRemote.model` is a lazily-initialized `static let`, add the touch at the top of `SendRemoteKeyIntent.perform()` and `StartRemoteSessionIntent.perform()` instead:

```swift
        _ = ProcessClock.start
        let model = SharedRemote.model
```

Verify `import PultCore` is present in both files (it is used already for `RemoteControlModel`).

- [ ] **Step 7: Build the app target via SwiftPM to catch compile errors**

Run: `make build`
Expected: PASS (`swift build --disable-sandbox` succeeds). This compiles `PultApp` sources and surfaces any SwiftUI/type errors.

- [ ] **Step 8: Commit**

```bash
git add Sources/PultApp/DiagnosticsAndValidationView.swift Sources/PultApp/PultApp.swift Sources/PultApp/RemoteIntents.swift
git commit -m "$(cat <<'EOF'
feat: add Command Timing readout to Diagnostics

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Register new files in Xcode project + full verification

**Files:**
- Modify: `Pult.xcodeproj/project.pbxproj`

- [ ] **Step 1: Confirm the SwiftPM build and tests are green**

Run: `make core-check && make test && make build`
Expected: all PASS.

- [ ] **Step 2: Check whether the Xcode project needs the new files**

Run: `make xcode-project-check`
Expected: this script fails or reports the four new PultCore files (`CommandTiming.swift`, `CommandTimingLog.swift`, `CommandTimingRecorder.swift`, `ProcessClock.swift`) are missing from the project if the app target compiles PultCore sources directly. If it passes, skip Step 3.

- [ ] **Step 3: Add the four new files to `Pult.xcodeproj`**

Open `Pult.xcodeproj` in Xcode and add the four new files under the existing `PultCore` group (`File > Add Files to "Pult"…`, select the four files in `Sources/PultCore/`, add to the same target(s) the sibling PultCore files belong to). Alternatively, mirror an existing PultCore file's three `project.pbxproj` entries (PBXFileReference, PBXBuildFile, and group/sources-phase membership) for each new file, matching how the most recent commit `6d3b439` added lock-screen layout files. Then re-run:

Run: `make xcode-project-check`
Expected: PASS.

- [ ] **Step 4: Run the full verification suite**

Run: `make verify-full`
Expected: PASS — `PultCoreCheck`, `swift build`, scheme/plist lint, `xcode-project-check`, and the iOS-27 simulator build all succeed. (Per the toolchain memory, `verify-full` needs Xcode-beta via `XCODE_DEVELOPER_DIR`; the Makefile already defaults it.)

- [ ] **Step 5: Commit**

```bash
git add Pult.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
chore: register command-timing files in Xcode project

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Hand off the on-device test protocol to the maintainer**

The measurement build is ready. The maintainer runs this on the physical iPhone + Google TV, then reports the numbers (which finalize the warm-session mechanism design):

1. In the app, open **Diagnostics → Command Timing → turn on "Record Command Timing."**
2. **Cold taps:** lock the phone, wait ~2–3 minutes, tap one command from the Live Activity. Repeat ~5×.
3. **Burst:** immediately tap Volume-Up ~5× fast.
4. **Volume:** change volume with the TV's own remote; confirm "Volume Pushes" increments.
5. Open **Diagnostics → Command Timing**, tap **Refresh Timings**, and read the WARM/COLD breakdown (`tcp+tls`, `configure`, total, fresh-launch). Optionally capture an Instruments trace via the `app.pult` `dial` / `command-timing` signpost subsystems.
6. Turn **off** "Record Command Timing."

Do not claim any latency or volume number is validated until the maintainer reports it from this run, per `AGENTS.md`.

---

## Self-Review

**1. Spec coverage** (checked against `2026-06-15-warm-live-session-design.md`):
- Phase timestamps `resolve · tcp+tls · configure · send` → Tasks 5 (tcp+tls, configure on the session) + 6 (total, send-as-remainder, WARM/COLD). `resolve` is effectively zero in this path (the device host is already known; no mDNS in the command path), so it is folded into the decision/total rather than a separate field — noted here intentionally, not omitted.
- WARM/COLD + fresh-launch indicator → Task 6 (`dialed`) + Task 4 (`ProcessClock`, `likelyFreshLaunch`).
- App Group ring buffer surviving process death, concurrency-safe via atomic per-file writes → Task 2.
- `os_signpost` → Task 3 (per-command event) + Task 5 (per-phase intervals).
- In-app Diagnostics readout with volume-push stats → Task 7.
- Runtime measurement flag so nothing ships enabled → Task 3 + Task 7 toggle.
- Logging-only, no behavior change → enforced in Tasks 5–6 (additive edits; `make test` regression gate in Task 6 Step 7).
- Unit tests for timing math, ring-buffer bounding, WARM/COLD classification, volume counter → Tasks 1, 2, 5, 6.
- Verification commands (`core-check`, `test`, `xcode-project-check`, `verify-full`) → Task 8.

**2. Placeholder scan:** No TBD/TODO; every code step contains complete code; no "similar to Task N" references (the one verbatim reuse — `runRemoteAction`'s body — is shown in full in Task 6 Step 5).

**3. Type consistency:** `CommandTiming` initializer args, `CommandTimingRecording.isEnabled`/`record`, `CommandTimingLog.record`/`recent`/`clear`/`appGroup`, `CommandTimingRecorder.enabledDefaultsKey`/`isEnabled(defaults:)`/`setEnabled(_:defaults:)`, `ProcessClock.start`/`ageMilliseconds`, and the new `RemoteSession.lastTCPTLSMilliseconds`/`lastConfigureMilliseconds`/`volumePushCount`/`lastVolumePushAt` are used identically across tasks. The `RemoteControlModel.init` `timingRecorder` parameter name matches the test's `makeModel`.
