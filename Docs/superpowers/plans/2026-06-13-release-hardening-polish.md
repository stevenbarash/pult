# Release-Hardening + UX-Polish Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. For all SwiftUI view work (Phase 4), also use the **swiftui-design-skill**.

**Goal:** Take Pult from "feature-complete and compiles" to a beautiful, demo-able, TestFlight-ready beta by eliminating crash/hang risks, completing failure-state coverage, polishing the demo hero-path to the brand spec, and clearing App Store-review landmines.

**Architecture:** Pult is a SwiftUI iOS-27 app over a `PultCore` framework that reimplements Android TV Remote Service v2 (Bonjour discovery, mTLS pairing on 6467, command channel on 6466, hand-rolled protobuf + varint framing). UI surfaces: remote deck, lock-screen Live Activity, Control Center/Action-button controls, App Intents/Siri, widgets. This plan touches `PultCore` (crash/hang/reconnect), `PultApp` views (states + polish), `PultWidgets` (a11y), and project metadata (privacy manifest).

**Tech Stack:** Swift 6, SwiftUI, Network.framework, Swift Testing, App Intents, WidgetKit/ActivityKit. Build with Xcode-beta (iOS 27 SDK); tests with full Xcode.

**Spec:** `Docs/superpowers/specs/2026-06-13-release-hardening-polish-design.md`

---

## Conventions used by every task

**Run the test suite** (Swift Testing needs a full Xcode toolchain; CLT alone fails to import `Testing`):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HOME=$PWD/.build/home swift test --disable-sandbox
```

Filter to one test while iterating: append `--filter <testFunctionName>`.

**Build the full iOS-27 app** (app + `PultWidgets.appex`; needs the iOS 27 SDK, which lives ONLY in Xcode-beta — `/Applications/Xcode.app` has just iOS 26.5):

```sh
make verify-full XCODE_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

**Fast local check** (SwiftPM compile + lint, no iOS build): `make verify`.

**Device validation:** the maintainer has a physical iPhone + Google TV (`Android.local`). Tasks tagged **[device-validate]** require running the relevant flow on device and recording the result in `Docs/PhysicalDeviceValidationChecklist.md` (date + host + passed area) per the repo's evidence rule. Never write "validated" without that evidence.

**Brand tokens** live in the design layer referenced throughout the views as `PultDesign.*` / `RemoteMetrics.*`. The canonical brand values are in `Docs/PultBrandSpec.md`: connected `#7BD99A` (`PultDesign.connected`), danger `#FF6A63` (`PultDesign.danger`), accent aqua `#56D6C9` (`PultDesign.accent`/`.pultAccent`), hairline opacity `0.14` (`PultDesign.hairline`), deck radius `36` (`RemoteMetrics.surfaceCornerRadius`), panel radius `26–28`, min tap target `44`.

---

## Phase 0 — Foundation lock-in

Baseline is already green (`swift test` 91/91; `make verify`; `make verify-full` built `Pult.app` with the embedded `PultWidgets.appex` in Swift-6/iOS-27.0 on 2026-06-13). This phase just records the canonical commands so we never regress them.

### Task 0: Record the canonical verification commands

**Files:**
- Modify: `README.md` (Build section) — confirm `verify-full` documents `XCODE_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` as the iOS-27 path. (README already defaults to Xcode-beta; confirm and leave as-is if accurate.)

- [ ] **Step 1: Confirm both gates are green on a clean tree**

Run:
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HOME=$PWD/.build/home swift test --disable-sandbox
make verify-full XCODE_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```
Expected: `Test run with 91 tests ... passed` and `** BUILD SUCCEEDED **`.

- [ ] **Step 2: No commit unless README needs the SDK note.** If a README edit was needed, commit:
```sh
git add README.md
git commit -m "docs: pin iOS-27 SDK (Xcode-beta) as the verify-full toolchain"
```

---

## Phase 1 — Crash & hang safety (PultCore)

These four are the scariest findings: each can crash or permanently wedge a tester's app, and none is covered by the existing suite. Pure-logic fixes are full TDD; network-continuation fixes pair the code change with the tightest test feasible plus device validation.

### Task 1: VarintFramer rejects oversized/garbled length prefixes instead of trapping

**Why:** `Int(decoded.value)` at `VarintFramer.swift:24` traps when the decoded varint exceeds `Int.max`. `decodeVarint` accepts up to 10 bytes, so a corrupt inbound frame (flaky Wi-Fi, odd firmware, hostile LAN device) decodes to a huge `UInt64` and crashes the app — and this runs on **every** frame in the read loop.

**Files:**
- Create: `Tests/PultCoreTests/VarintFramerTests.swift`
- Modify: `Sources/PultCore/VarintFramer.swift` (lines 3–8 enum; line 24 conversion)

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import PultCore

@Test func nextFrameThrowsOnLengthPrefixLargerThanIntMax() throws {
    var framer = VarintFramer()
    // A 10-byte varint encoding a value > Int.max (all continuation bits set
    // until the final byte), followed by no payload.
    var buffer = Data([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f])
    #expect(throws: FramingError.self) {
        _ = try framer.nextFrame(from: &buffer)
    }
}

@Test func nextFrameRejectsImplausiblyLargePayload() throws {
    var framer = VarintFramer()
    // 16 MB declared length, far past any real RemoteMessage; must not be trusted.
    var buffer = framer.encodeVarint(UInt64(16 * 1024 * 1024))
    #expect(throws: FramingError.self) {
        _ = try framer.nextFrame(from: &buffer)
    }
}

@Test func nextFrameStillDecodesWellFormedFrame() throws {
    var framer = VarintFramer()
    let payload = Data([0x01, 0x02, 0x03])
    var buffer = framer.frame(payload)
    let decoded = try framer.nextFrame(from: &buffer)
    #expect(decoded == payload)
    #expect(buffer.isEmpty)
}
```

- [ ] **Step 2: Run to verify the first two fail (trap/no-throw) and the third passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HOME=$PWD/.build/home swift test --disable-sandbox --filter VarintFramer`
Expected: `nextFrameThrowsOnLengthPrefixLargerThanIntMax` and `nextFrameRejectsImplausiblyLargePayload` FAIL (crash or unthrown), well-formed PASSES.

- [ ] **Step 3: Add a bounded-length guard**

In `VarintFramer.swift`, add a case to `FramingError`:
```swift
public enum FramingError: Error, Equatable {
    case emptyInput
    case incompleteVarint
    case varintTooLong
    case incompleteFrame(expected: Int, actual: Int)
    case frameTooLarge(declared: UInt64)
}
```
Add a max-frame constant and replace line 24's conversion:
```swift
public struct VarintFramer: Sendable {
    /// RemoteMessage frames are small (key events, IME edits, volume). Cap well
    /// above any legitimate frame so a corrupt prefix can't allocate/crash.
    public static let maxFrameLength = 4 * 1024 * 1024
    public init() {}
    ...
    public func nextFrame(from buffer: inout Data) throws -> Data? {
        guard !buffer.isEmpty else { return nil }
        let decoded = try decodeVarint(from: buffer)
        let headerLength = decoded.bytesRead
        guard let payloadLength = Int(exactly: decoded.value),
              payloadLength >= 0,
              payloadLength <= Self.maxFrameLength else {
            throw FramingError.frameTooLarge(declared: decoded.value)
        }
        let frameLength = headerLength + payloadLength
        guard buffer.count >= frameLength else { return nil }
        let payload = buffer.subdata(in: headerLength..<frameLength)
        buffer.removeSubrange(0..<frameLength)
        return payload
    }
```

- [ ] **Step 4: Run tests — all VarintFramer tests pass, full suite stays green**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HOME=$PWD/.build/home swift test --disable-sandbox`
Expected: all pass (now 94 tests).

- [ ] **Step 5: Commit**
```sh
git add Sources/PultCore/VarintFramer.swift Tests/PultCoreTests/VarintFramerTests.swift
git commit -m "fix: reject oversized varint length prefixes instead of trapping"
```

### Task 2: Transport connect resumes (not hangs) when cancelled mid-handshake

**Why:** `RemoteTransport.swift:95` `default: break` ignores `.cancelled`. When `RemoteSession.disconnect()` (or a device delete / device switch) fires `transport.close()` → `connection.cancel()` during an in-flight handshake, the `.cancelled` state never resumes the continuation. `connect()` hangs → `RemoteSession.connect`'s `await task.value` hangs → every queued headless command behind it wedges. The `ContinuationGate` already guarantees single-resume, so resuming on cancel is safe.

**Files:**
- Modify: `Sources/PultCore/RemoteTransport.swift:95-97`

- [ ] **Step 1: Add the `.cancelled` case**

Replace the `default: break` in the `stateUpdateHandler` switch (lines 95–96) with:
```swift
                case .cancelled:
                    gate.resume {
                        continuation.resume(throwing: RemoteTransportError.disconnected)
                    }
                default:
                    break
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `make verify`
Expected: `Build complete!`

- [ ] **Step 3: [device-validate] Confirm the wedge is gone**

On device: start a connect to a slow/asleep TV and immediately switch devices / tap disconnect. Before: the remote freezes and later commands do nothing. After: the connect resolves to a clean failed/disconnected state and subsequent commands work. Record under "background reconnect / connection lifecycle" in the checklist.

- [ ] **Step 4: Commit**
```sh
git add Sources/PultCore/RemoteTransport.swift
git commit -m "fix: resume connect continuation when the socket is cancelled mid-handshake"
```

### Task 3: Transport connect has a hard timeout

**Why:** `connect()` waits on NWConnection states with no timeout of its own; only `.waiting` fast-fails. A TLS handshake stalled in `.preparing` (distrusted cert, half-open NAT) can hang past the session's 5s `configureTimeout`, freezing the connect→pair→command demo path.

**Files:**
- Modify: `Sources/PultCore/RemoteTransport.swift` (`connect`, add a timeout param + race)

- [ ] **Step 1: Add a timeout around the connect continuation**

Give `NetworkRemoteTransport` a `connectTimeout` (default `.seconds(8)`) and race the state-wait against a sleep that cancels the connection. Replace the `try await withCheckedThrowingContinuation { ... connection.start ... }` block (lines 72–100) so the continuation is also resumed by a timeout:
```swift
        let connectTimeout = self.connectTimeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let gate = ContinuationGate()
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            gate.resume { continuation.resume() }
                        case .failed, .cancelled:
                            gate.resume { continuation.resume(throwing: RemoteTransportError.connectionFailed) }
                        case .waiting:
                            gate.resume {
                                connection.cancel()
                                continuation.resume(throwing: RemoteTransportError.connectionFailed)
                            }
                        default:
                            break
                        }
                    }
                    connection.start(queue: self.queue)
                }
            }
            group.addTask {
                try await Task.sleep(for: connectTimeout)
                throw RemoteTransportError.connectionFailed
            }
            // First to finish wins; cancel the rest and propagate its result.
            defer { group.cancelAll() }
            try await group.next()
        }
```
Note: keep the `.cancelled` handling from Task 2 (folded into `case .failed, .cancelled` above). On timeout, the group's `defer` cancels the sleeper; also call `connection.cancel()` in a `catch` before rethrow so the dangling NWConnection is torn down. Add the stored property:
```swift
    private let connectTimeout: Duration
    public init(identityProvider: (any ClientIdentityProviding)? = KeychainClientIdentityStore.shared,
                connectTimeout: Duration = .seconds(8)) {
        self.identityProvider = identityProvider
        self.connectTimeout = connectTimeout
    }
```

- [ ] **Step 2: Build**

Run: `make verify`
Expected: `Build complete!`

- [ ] **Step 3: Run full suite (connect tests must still pass)**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HOME=$PWD/.build/home swift test --disable-sandbox`
Expected: all pass — especially `refusedConnectionFailsInsteadOfHangingForever`, `switchingDevicesAbandonsStaleHandshake`, `overlappingConnectsToSameDeviceShareOneAttempt`.

- [ ] **Step 4: Commit**
```sh
git add Sources/PultCore/RemoteTransport.swift
git commit -m "fix: bound the TLS connect with a hard timeout so handshakes can't hang"
```

### Task 4: Pairing receive loop times out instead of spinning forever

**Why:** `PairingSession.receiveMessage()` awaits `transport.receive()` with no timeout; `start`/`submit` therefore hang forever if the TV accepts the TCP connection but never sends the expected ack (mid-reboot, wrong service, half-open socket). The pairing UI shows an un-cancellable spinner on the hero path.

**Files:**
- Modify: `Sources/PultCore/PairingSession.swift` (add timeout to `receiveMessage`)
- Create: `Tests/PultCoreTests/PairingSessionTests.swift`
- Modify: `Tests/PultCoreTests/TestSupport.swift` (add a stalling transport stub if not already present)

- [ ] **Step 1: Add a stalling transport stub to TestSupport**

In `Tests/PultCoreTests/TestSupport.swift`, add (only if an equivalent doesn't already exist):
```swift
import Foundation
@testable import PultCore

/// Connects and accepts sends, but `receive()` never returns — simulates a TV
/// that completes TCP/TLS but never sends a pairing ack.
actor StallingTransport: RemoteTransport {
    func connect(to host: String, port: UInt16) async throws {}
    func send(_ data: Data) async throws {}
    func receive() async throws -> Data {
        try await Task.sleep(for: .seconds(3600))
        return Data()
    }
    func close() async {}
    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? { nil }
}
```

- [ ] **Step 2: Write the failing test**

```swift
import Foundation
import Testing
@testable import PultCore

@Test func pairingStartTimesOutWhenTvNeverAcks() async throws {
    let session = PairingSession(transport: StallingTransport(), receiveTimeout: .milliseconds(200))
    let device = DeviceRecord.fixture()   // existing test fixture helper
    let params = try RSAPublicKeyParameters.fixture()  // existing helper, or build a small test key
    await #expect(throws: PairingSessionError.self) {
        try await session.start(for: device, clientParameters: params)
    }
}
```
(If `DeviceRecord.fixture()` / `RSAPublicKeyParameters.fixture()` don't exist, reuse the constructors already used in `RemoteSessionTests.swift` / `PairingSecret`-related tests — grep those files for the existing builders and mirror them.)

- [ ] **Step 3: Run to verify it hangs/fails (it will hit the test's own time budget without the fix)**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HOME=$PWD/.build/home swift test --disable-sandbox --filter pairingStartTimesOut`
Expected: FAIL (no `PairingSessionError` thrown; the call hangs until the harness kills it).

- [ ] **Step 4: Implement the receive timeout**

Add `receiveTimeout` to `PairingSession` and race each receive:
```swift
    private let receiveTimeout: Duration
    public init(transport: RemoteTransport = NetworkRemoteTransport(),
                serviceName: String = "app.pult",
                clientName: String = "Pult",
                framer: VarintFramer = VarintFramer(),
                receiveTimeout: Duration = .seconds(12)) {
        self.transport = transport
        self.serviceName = serviceName
        self.clientName = clientName
        self.framer = framer
        self.receiveTimeout = receiveTimeout
    }

    private func receiveMessage() async throws -> PairingMessage {
        let deadline = ContinuousClock.now.advanced(by: receiveTimeout)
        while true {
            if let frame = try framer.nextFrame(from: &buffer) {
                let message = try PairingMessageCoder.decode(frame)
                guard message.status == .ok else { throw PairingSessionError.rejected(message.status) }
                return message
            }
            guard ContinuousClock.now < deadline else { throw PairingSessionError.timedOut }
            let chunk = try await withThrowingTaskGroup(of: Data.self) { group -> Data in
                group.addTask { try await self.transport.receive() }
                group.addTask {
                    try await Task.sleep(for: .milliseconds(250))
                    return Data()   // periodic wake so the deadline check runs
                }
                defer { group.cancelAll() }
                return try await group.next() ?? Data()
            }
            if chunk.isEmpty { await Task.yield(); continue }
            buffer.append(chunk)
        }
    }
```
Add `case timedOut` to `PairingSessionError`.

- [ ] **Step 5: Run tests — timeout test passes, suite green**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HOME=$PWD/.build/home swift test --disable-sandbox`
Expected: all pass.

- [ ] **Step 6: Commit**
```sh
git add Sources/PultCore/PairingSession.swift Tests/PultCoreTests/PairingSessionTests.swift Tests/PultCoreTests/TestSupport.swift
git commit -m "fix: time out the pairing handshake instead of spinning forever"
```

---

## Phase 2 — Connection lifecycle & reconnect

### Task 5: Surface dropped sessions clearly; auto-reconnect the foreground remote (bounded)

**Why:** `ReconnectionBackoff` is fully implemented and tested but wired into nothing — a mid-session drop (TV sleeps during an ad) silently freezes the remote until the user notices the banner. **Decision flagged:** auto-reconnect is the one item with real behavioral risk (reconnect storms, battery). Scope it tightly: only the foreground `RemoteControlSurface` auto-redials, only for a paired device, bounded attempts, and the manual Retry banner stays as the backstop. Headless/Control-Center paths keep their existing redial-once.

**Files:**
- Modify: `Sources/PultCore/RemoteControlModel.swift` (observe session `.failed`, drive a bounded `ReconnectionBackoff` redial loop)
- Test: `Tests/PultCoreTests/RemoteSessionTests.swift` or a new `ReconnectionTests.swift`

- [ ] **Step 1: Write the failing test** — a model whose session fails once then succeeds redials after a backoff delay and returns to `.connected`; a model that keeps failing stops after the max attempts and lands on `.failed`. Use the existing `MockRemoteTransport` pattern (see `Sources/PultCoreCheck/MockRemoteTransport.swift`; port/share it into `Tests` via `TestSupport.swift`). Assert attempt count == cap and final state.

- [ ] **Step 2: Run to verify it fails** (`--filter Reconnect`). Expected: FAIL (no auto-redial today).

- [ ] **Step 3: Implement** a `reconnectForegroundIfNeeded()` on the model that, when the active surface is foregrounded and `session.connectionState` becomes `.failed` for the selected paired device, runs:
```swift
var backoff = ReconnectionBackoff()
let maxAttempts = 4
for _ in 0..<maxAttempts {
    guard isRemoteForeground, let device = selectedDevice, device.isPaired else { return }
    try? await Task.sleep(for: backoff.nextDelay())
    await session.connect(to: device)
    if session.connectionState == .connected { return }
}
// fall through to the manual .failed banner
```
Gate it so it never runs for headless/intent contexts and never stacks concurrent loops (guard a `isReconnecting` flag).

- [ ] **Step 4: Run tests — pass, suite green.**

- [ ] **Step 5: [device-validate]** Put the TV to sleep mid-session; confirm Pult auto-recovers within a few seconds, and that after the cap it shows the Retry banner. Record under "background reconnect."

- [ ] **Step 6: Commit**
```sh
git add Sources/PultCore/RemoteControlModel.swift Tests/PultCoreTests/
git commit -m "feat: bounded auto-reconnect for the foreground remote via ReconnectionBackoff"
```

---

## Phase 3 — Failure, empty & recovery states

### Task 6: `.connecting` shows a banner + inline progress (no dead-looking dimmed remote)

**Why:** `RemoteControlSurface.swift:301-317` `bannerKind` returns `nil` for `.connecting`; the remote just dims to 0.46 and taps no-op for up to several seconds on the hero path. Add a `.connecting` banner with an inline `ProgressView` and "Connecting to {name}…".

**Files:** Modify `Sources/PultApp/RemoteControlSurface.swift` (`bannerKind` ~301-317), and the banner view it maps to (`Sources/PultApp/RemoteSurfaceStatusViews.swift`).

- [ ] **Step 1:** Add a `.connecting` case to the banner-kind logic returning a non-dismissable info banner with a `ProgressView()` and the device name. Reuse the existing `StatusBanner` style.
- [ ] **Step 2:** Build (`make verify`). Expected: `Build complete!`.
- [ ] **Step 3: [device-validate]** Cold-launch → select TV → observe a clear "Connecting…" banner, not a dead grey remote.
- [ ] **Step 4: Commit** `git commit -am "fix: show a connecting banner with progress on the remote surface"`.

### Task 7: Distinguish Local-Network-permission denial from "no TVs found"

**Why:** `NetServiceBrowser` returns zero results (not `didNotSearch`) when the user taps "Don't Allow", so `DeviceDiscovery.swift:299-310` lands the user in `.manualOnly` ("TV may be asleep…") — misdiagnosing the single most likely first-run failure. The "Open Settings" fix is buried in an always-on row (`AddDeviceView.swift:619-647`).

**Files:** Modify `Sources/PultCore/DeviceDiscovery.swift` (detect/track denied authorization), `Sources/PultApp/AddDeviceView.swift` (permission-denied state copy + prominent Open Settings button).

- [ ] **Step 1:** Add a discovery state distinguishing "permission denied" from "nothing found". Detect via a `NWBrowser`-based authorization probe (preferred) or a heuristic: first scan yields zero services AND the OS prompt was shown before → treat as denied; expose `discoveryState == .permissionDenied`.
- [ ] **Step 2:** In `AddDeviceView`, when `.permissionDenied`, replace the generic manual-only copy with: **"Pult needs Local Network access to find your TV."** + a prominent **"Open Settings"** button (`UIApplication.openSettingsURLString`) + the manual-IP fallback. Keep manual IP always reachable.
- [ ] **Step 3:** Build (`make verify`).
- [ ] **Step 4: [device-validate]** Reset network permission (or deny on a fresh install) → confirm Pult names the real cause and Open Settings works. Record under "setup / local-network."
- [ ] **Step 5: Commit** `git commit -am "fix: name Local Network permission denial instead of 'no TVs found'"`.

### Task 8: Wrong pairing code keeps the displayed code (no full teardown)

**Why:** `PairingView.swift:91-101,196-199` routes any verify failure through `retryPairing()`, which tears down the session and makes the TV show a **new** code — so fixing one mistyped digit forces a full restart. On `badSecret`/code-mismatch, return to `waitingForCode` with the field cleared but the session intact, so the same on-screen code can be retried.

**Files:** Modify `Sources/PultApp/PairingView.swift`, and check `RemoteControlModel`/pairing glue that maps `PairingSessionError.rejected`/`badSecret` to UI state.

- [ ] **Step 1:** Distinguish "bad code" (recoverable → `waitingForCode`, clear field, keep session, light error haptic) from "connection lost" (→ full `failedPhase`). Wire the submit path so a rejected secret does not call `beginPairing()` again.
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: [device-validate]** Enter a wrong code → confirm you can immediately retype against the same TV-displayed code; only a dropped connection triggers a fresh code. Record under "pairing."
- [ ] **Step 4: Commit** `git commit -am "fix: retry a mistyped pairing code without restarting the handshake"`.

### Task 9: "No TV selected" state in the keyboard sheet

**Why:** `TextEntryView` has no handling for `selectedDevice == nil`; `ensureConnected()` returns early (`RemoteControlModel.swift:160-161`) so Send/keys silently no-op while showing "Disconnected". The launcher already does this right (`FavoriteAppLauncherView.swift:160-162`).

**Files:** Modify `Sources/PultApp/TextEntryView.swift`.

- [ ] **Step 1:** When `model.selectedDevice == nil`, render an explicit empty state — **"No TV selected. Add or choose a TV to type."** — with an add/select affordance (open Manage Devices / Add TV), mirroring the launcher's copy/pattern. Suppress the dead keyboard controls in that state.
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: [device-validate]** Open the keyboard from the command palette with no TV selected → confirm the guided empty state, not a silent dead field.
- [ ] **Step 4: Commit** `git commit -am "fix: guide the user when the keyboard sheet has no selected TV"`.

### Task 10: Route favorite-app launch failures through the standard failure UI

**Why:** `FavoriteAppLauncherView.swift:211-214` dumps a raw `session.lastError` with no retry, unlike the remote surface/keyboard which wrap failures in `RemoteCommandFailure` + Retry/Reconnect.

**Files:** Modify `Sources/PultApp/FavoriteAppLauncherView.swift`.

- [ ] **Step 1:** Replace the raw-string status with the shared `RemoteCommandFailure` presentation (Retry/Reconnect/Pair-Again affordances), matching `TextEntryView.errorMessage` (`TextEntryView.swift:332-370`).
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: [device-validate]** Force a launch failure (TV offline) → confirm a recoverable banner. Record under "favorite app links."
- [ ] **Step 4: Commit** `git commit -am "fix: give favorite-app launch failures a recovery path"`.

---

## Phase 4 — Demo hero-path polish (brand · haptics · visual)

**Use the swiftui-design-skill for this whole phase.** These changes are what sells the "remote Google should've built" hook on camera. Read each view before editing; honor `Docs/PultBrandSpec.md`. Group commits logically.

### Task 11: Unify success/error colors onto brand tokens (kill duplicate greens/reds and stray cyan)

**Why:** connected/paired/success states render in two greens (system `.green` vs `PultDesign.connected`) and failures in two reds simultaneously; the ⌘K palette adds a third teal (`.cyan`). A disciplined color pass is the single highest-leverage visual fix.

**Files & exact replacements:**
- `.green` → `PultDesign.connected`: `ConnectionStatusControl.swift:32`, `RemoteControlPresentation.swift:53,82`, `ManageDevicesView.swift:87`, `FavoriteAppLauncherView.swift:147`, `TextEntryView.swift:265,403`, `AddDeviceView.swift:407,463,477`, `DiagnosticsAndValidationView.swift:469,578,623`, `PairingView.swift:107`.
- `.red` → `PultDesign.danger`: `ConnectionStatusControl.swift:34`, `CommandPaletteView.swift:335`, `AddDeviceView.swift:409,485`, `DiagnosticsAndValidationView.swift:579`.
- `.cyan` → `PultDesign.utility` (volume/mute) / `PultDesign.accent` (search): `CommandPaletteView.swift:237,337` (match the tint logic in `RemoteControlSurface.tint(for:)`).

- [ ] **Step 1:** Apply each replacement (verify the line still matches; the executor reads the file first). Confirm no remaining `Color.green`/`Color.red`/`.cyan` in `Sources/PultApp` except where the system genuinely requires it (grep: `rg '\.(green|red|cyan)\b' Sources/PultApp`).
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: [device-validate]** Trigger connected + failed states together (status header + toolbar pill) and the ⌘K palette; confirm one green, one red, one aqua.
- [ ] **Step 4: Commit** `git commit -am "polish: unify success/error/accent colors onto brand tokens"`.

### Task 12: Differentiate remote haptics and de-buzz volume-hold

**Why:** every gesture fires one identical `SensoryFeedback.impact(.rigid, 0.78)` (`RemoteHardwareInput.swift:43`, `RemoteControlSurface.swift:131-135`), and volume-hold fires a haptic on every ~180ms repeat (`RemoteControls.swift:512-520`) — a machine-gun buzz that feels broken.

**Files:** `Sources/PultApp/RemoteHardwareInput.swift`, `RemoteControlSurface.swift`, `RemoteControls.swift`.

- [ ] **Step 1:** Give distinct feedback per interaction: SELECT/confirm → heavier `.impact(.rigid)` or `.success`; directional swipe → light `.impact(.soft)`; button tap → medium. Suppress per-repeat haptics in the hold-repeat zone (haptic on initial press only, or a slow light tick).
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: [device-validate]** On device, confirm tap vs swipe vs hold feel distinct and volume-hold no longer buzzes. (Haptics only validate on hardware.) Record under "remote controls / volume."
- [ ] **Step 4: Commit** `git commit -am "polish: distinct haptics per gesture; stop volume-hold haptic buzz"`.

### Task 13: Land every radius on the 36 / 26–28 / 18 shape scale

**Why:** orphan radii cheapen the hero empty-state and failure banners: banners at 22 (`RemoteSurfaceStatusViews.swift:70,152`), welcome poster at 34 with a 38 inner remote (`PultLaunchView.swift:61,149`).

**Files:** `Sources/PultApp/RemoteSurfaceStatusViews.swift`, `PultLaunchView.swift`.

- [ ] **Step 1:** Banners → `26` (or `18` if treated as inner rows). Welcome poster → `RemoteMetrics.surfaceCornerRadius` (36); make the inner mini-remote subordinate (≤ poster).
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: Commit** `git commit -am "polish: snap banner and welcome-poster radii to the brand shape scale"`.

### Task 14: Pairing-code field uses brand tokens + per-digit haptic

**Why:** `PairingView.swift:480-495` uses raw `Color.accentColor` and `.white.opacity(0.1)` (vs `PultDesign.hairline` 0.14) and has no per-character tick. Pairing is a guaranteed demo step.

**Files:** `Sources/PultApp/PairingView.swift`.

- [ ] **Step 1:** Active box border → `PultDesign.accent`; inactive → `PultDesign.hairline`. Add a light `.sensoryFeedback(.selection, ...)` as each of the 6 characters lands.
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: [device-validate]** Enter a code; confirm per-digit tick and brand-consistent boxes.
- [ ] **Step 4: Commit** `git commit -am "polish: brand-token pairing boxes with per-digit haptic"`.

### Task 15: Fix the touchpad left-swipe chevron (real bug)

**Why:** `TouchpadView.swift:209-216` `chevronName` returns `"chevron.right"` in `default`, and `.left` isn't handled — a left swipe flashes a right-pointing chevron.

**Files:** `Sources/PultApp/TouchpadView.swift`.

- [ ] **Step 1:** Add the explicit `.left → "chevron.left"` case.
- [ ] **Step 2:** Also gate the hint-label animation behind reduce-motion (a11y finding): `TouchpadView.swift:161` → `.animation(reduceMotion ? nil : .smooth, value: lifetimeGestureCount)`.
- [ ] **Step 3:** Build (`make verify`).
- [ ] **Step 4: [device-validate]** Swipe left → left chevron flashes.
- [ ] **Step 5: Commit** `git commit -am "fix: correct left-swipe chevron and gate touchpad hint animation for reduce-motion"`.

### Task 16: Recovery buttons meet the 44pt target

**Why:** the four `CommandFailureBanner` recovery buttons (`RemoteSurfaceStatusViews.swift:122-141`) render ~34pt — the only sub-44pt targets on a primary path. The sibling `StatusBanner` button (line 167) already uses `minHeight: 44`.

**Files:** `Sources/PultApp/RemoteSurfaceStatusViews.swift:122-141`.

- [ ] **Step 1:** Add `.frame(minHeight: 44)` to each recovery button (match line 167).
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: Commit** `git commit -am "fix: 44pt minimum on command-failure recovery buttons"`.

### Task 17: Live Activity status not color-only; tidy the welcome power dot

**Why:** the small Live Activity state badge is color-only for low-vision sighted users (`RemoteLiveActivity.swift:78-103`); the welcome preview power dot is a 14×14 circle holding an 8pt glyph that reads as a smudge (`PultLaunchView.swift:111-118`).

**Files:** `Sources/PultWidgets/RemoteLiveActivity.swift`, `Sources/PultApp/PultLaunchView.swift`.

- [ ] **Step 1:** Vary the compact status dot's SF Symbol (or show 1–2 chars) per state so connected/connecting/failed isn't color-alone. Drop the inner glyph from the welcome power dot (plain dot) or enlarge it.
- [ ] **Step 2:** Build the full app+widget: `make verify-full XCODE_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 3: [device-validate]** Check the lock-screen Live Activity states. Record under "Lock Screen Live Activity."
- [ ] **Step 4: Commit** `git commit -am "a11y/polish: non-color Live Activity status; cleaner welcome power dot"`.

### Task 18: Optional nice-to-haves (defer unless time allows)

Logged, not required for beta exit: signal-burst `.blendMode(.screen)` toning (`PultLaunchView.swift:231`, `RemoteControls.swift:619`); search/launcher button symmetry (`RemoteControlSurface.swift:597-660`); unify primary CTA heights (52 vs 48 vs 44); idle connected-meter breathe; neutral echo-toast shadow; command-palette segmented picker `titleAndIcon`; diagnostics toggle traits. Pick up only after Phases 1–5 and 19–22 are done.

---

## Phase 5 — App Store compliance & copy

### Task 19: Add the privacy manifest (blocks upload without it)

**Why:** No `PrivacyInfo.xcprivacy` exists; the app/widget use `UserDefaults` (a required-reason API), so upload triggers automated rejection ITMS-91053. Pult collects no off-device data and does no tracking.

**Files:**
- Create: `Sources/PultApp/Supporting/PrivacyInfo.xcprivacy`
- Create: `Sources/PultWidgets/Supporting/PrivacyInfo.xcprivacy`
- Modify: `Pult.xcodeproj/project.pbxproj` (add both to the respective target Resources/Copy-Bundle phases)

- [ ] **Step 1: Write the manifest** (identical for both targets):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```
- [ ] **Step 2:** Add both files to their targets in `project.pbxproj` (Xcode: drag in, check the right target membership; or hand-edit the pbxproj resources build phase). Lint: `plutil -lint Sources/PultApp/Supporting/PrivacyInfo.xcprivacy Sources/PultWidgets/Supporting/PrivacyInfo.xcprivacy`.
- [ ] **Step 3:** Build the full app: `make verify-full XCODE_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. Expected: `** BUILD SUCCEEDED **` and the manifest copied into `Pult.app`/`.appex`.
- [ ] **Step 4: Commit** `git commit -am "feat: add PrivacyInfo.xcprivacy for app and widget (UserDefaults reason CA92.1)"`.

### Task 20: Replace the "IME" jargon chip on the welcome screen

**Why:** `PultLaunchView.swift:253` shows a user-facing `PultStatusChip(title: "IME", …)` — dev jargon on the first screen a reviewer sees. (The "IME" search aliases in `CommandPaletteView.swift:267`/`TextEntryView` are fine — those are hidden.)

**Files:** `Sources/PultApp/PultLaunchView.swift:253`.

- [ ] **Step 1:** Change the chip title to **"Text Entry"** (avoid duplicating the existing "Keyboard" chip).
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: Commit** `git commit -am "copy: replace 'IME' welcome chip with plain-language 'Text Entry'"`.

### Task 21: Lower the success-path intent log from .error to .debug

**Why:** `RemoteIntents.swift:348` logs at `.error` on every successful Control-Center/Action-button invocation — pollutes device logs at error severity for a non-error.

**Files:** `Sources/PultApp/RemoteIntents.swift:348`.

- [ ] **Step 1:** `intentLogger.error(...)` → `intentLogger.debug(...)`.
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: Commit** `git commit -am "chore: log the intent-routing diagnostic at debug, not error"`.

### Task 22: Add a "not affiliated with Google" line

**Why:** UI uses "Google TV"/"Android TV" descriptively (acceptable nominative use), but third-party remotes are sometimes asked to clarify non-affiliation. Low-risk insurance.

**Files:** `Sources/PultApp/DiagnosticsAndValidationView.swift` (About/footer) — and note it for the App Store description (Sub-project B).

- [ ] **Step 1:** Add a small footer line: **"Pult is not affiliated with or endorsed by Google. Google TV and Android TV are trademarks of Google LLC."**
- [ ] **Step 2:** Build (`make verify`).
- [ ] **Step 3: Commit** `git commit -am "copy: add non-affiliation disclaimer"`.

---

## Phase 6 — Final sweep, full validation & hero-path capture

### Task 23: Green gates + full device validation pass

- [ ] **Step 1:** Run both gates clean:
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HOME=$PWD/.build/home swift test --disable-sandbox
make verify-full XCODE_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```
Expected: all tests pass; `** BUILD SUCCEEDED **`.
- [ ] **Step 2: [device-validate]** Run the in-app Diagnostics guided validation runner end to end on `Android.local`, then walk the full hero-path manually: first launch → discover → pair → remote (touchpad/d-pad/media/volume/haptics) → keyboard → lock-screen Live Activity (locked) → Siri → Control Center → Action button. Record passed areas with date + host in `Docs/PhysicalDeviceValidationChecklist.md`.
- [ ] **Step 3:** Accessibility spot-check on device: VoiceOver across the hero-path; Dynamic Type at an accessibility size; reduce-motion on.
- [ ] **Step 4: Commit** the updated checklist `git commit -am "docs: record physical validation for the hardened build"`.

### Task 24: Record the hero-path (hand-off to Sub-project C)

- [ ] **Step 1:** Screen-record the hero-path in one clean take on device (this is the raw material the launch video edits from — production happens in Sub-project C).
- [ ] **Step 2:** Note any rough frames discovered during recording; if any are demo-critical, loop back to the relevant phase.

---

## Self-review (against the spec)

- **Spec coverage:** DoD #1 build/test green → Phase 0 + Task 23. #2 hero-path flawless/beautiful → Phases 3–4 + Task 24. #3 no crashes/dead-ends, designed recovery → Phases 1–3. #4 zero-context tester → Tasks 6–9, 19–20. #5 a11y floor → Tasks 15–17 + Task 23 Step 3. #6 brand/icon consistency → Tasks 11–14, 16–17. #7 no placeholder copy → Tasks 20, 22. Demo hero-path (spec §C) → Phases 3–4 mapped step-by-step. Validation strategy (spec §F) → every [device-validate] step + checklist commits. Risks: iOS-27 SDK → resolved (Xcode-beta, Phase 0); IP/ToS → out of scope, flagged for Sub-project C; single-TV ceiling → checklist labels per-TV.
- **Placeholder scan:** Task 18 is explicitly the deferred bucket (allowed); every required task has concrete files, code, and commands. No "TBD/handle edge cases/similar to Task N".
- **Type consistency:** `FramingError.frameTooLarge`, `PairingSessionError.timedOut`, `RemoteTransportError.disconnected`, `ReconnectionBackoff.nextDelay()/reset()`, `PultDesign.connected/.danger/.accent/.hairline`, `RemoteMetrics.surfaceCornerRadius` are used consistently across tasks and match the real source read during planning.

## Exit criteria

All beta-blocking and demo-critical tasks (Phases 1–6, Tasks 0–17, 19–24) complete; both gates green; hero-path device-validated and recorded. Task 18 nice-to-haves deferred to post-beta. Then proceed to Sub-project B (TestFlight/App Store Connect).
