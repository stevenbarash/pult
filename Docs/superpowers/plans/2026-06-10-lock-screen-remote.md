# Lock-Screen Remote ("Pult Anywhere") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Control a paired Google TV from the iPhone lock screen without unlocking, via an interactive Live Activity mini-remote plus Control Center / lock-screen / Action-button controls.

**Architecture:** App Intents conforming to `LiveActivityIntent` run in the app's process without unlocking; they drive the existing `RemoteSession` through a new `RemoteControlModel.performHeadlessCommand`. A new `PultWidgets` WidgetKit extension renders the Live Activity and the controls. The mTLS keychain identity moves to after-first-unlock protection, and the device store moves to an App Group with persisted device selection so intents know which TV to dial.

**Tech Stack:** Swift 6 / SwiftUI, AppIntents (`LiveActivityIntent`), ActivityKit, WidgetKit (`ControlWidget`, `ActivityConfiguration`), Network.framework mTLS (existing), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-10-lock-screen-remote-design.md`

**Project constraints (read before starting):**
- `make build` / `make test` compile `PultApp` and `PultCore` for **macOS** via SwiftPM. Anything in those directories must keep compiling on macOS: guard ActivityKit code with `#if canImport(ActivityKit)` and use the `HeadlessRemoteIntent` typealias for `LiveActivityIntent`.
- `Sources/PultWidgets/` is **Xcode-only** (not in `Package.swift`); it cannot be compiled in a Command Line Tools-only environment. Its correctness gates are `make metadata-check`, `make xcode-project-check`, and a device build in Xcode.
- `swift test` may fail with `no such module 'Testing'` under CLT-only toolchains. If so, run `make verify` and treat the missing test runner as a toolchain issue per AGENTS.md — but still write the tests; they run under full Xcode.
- Per AGENTS.md, do not claim end-to-end lock-screen behavior works without device evidence. The final section lists the device checklist.

---

### Task 0: Initialize git (workspace is not a repo)

The workspace has no `.git`. Commits below assume one exists.

- [ ] **Step 1: Initialize and baseline**

```bash
cd /Users/nyetwork/Developer/pult
git init -b main
git add -A
git commit -m "chore: baseline before lock-screen remote work"
```

If the user has said not to use git, skip this task and replace every "Commit" step below with running `make verify`.

---

### Task 1: Keychain identity readable after first unlock

The mTLS client identity is created with default (`WhenUnlocked`) protection, so a locked-screen intent cannot load it. Create new items with `kSecAttrAccessibleAfterFirstUnlock` and upgrade existing items on load. macOS file keychains don't support data-protection classes, so accessibility is `nil` (unchanged behavior) off-iOS — which also keeps `make core-check` working.

**Files:**
- Modify: `Sources/PultCore/ClientIdentity.swift`
- Create: `Tests/PultCoreTests/ClientIdentityTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PultCoreTests/ClientIdentityTests.swift`:

```swift
import Foundation
import Security
import Testing
@testable import PultCore

@Test
func privateKeyAttributesCarryAccessibilityWhenProvided() {
    let attributes = KeychainClientIdentityStore.privateKeyAttributes(
        keyTag: Data("tag".utf8),
        accessibility: kSecAttrAccessibleAfterFirstUnlock
    )
    let privateAttrs = attributes[kSecPrivateKeyAttrs as String] as? [String: Any]
    #expect(privateAttrs?[kSecAttrAccessible as String] as! CFString == kSecAttrAccessibleAfterFirstUnlock)
    #expect(privateAttrs?[kSecAttrIsPermanent as String] as? Bool == true)
    #expect(attributes[kSecAttrKeySizeInBits as String] as? Int == 2048)
}

@Test
func privateKeyAttributesOmitAccessibilityWhenNil() {
    let attributes = KeychainClientIdentityStore.privateKeyAttributes(
        keyTag: Data("tag".utf8),
        accessibility: nil
    )
    let privateAttrs = attributes[kSecPrivateKeyAttrs as String] as? [String: Any]
    #expect(privateAttrs?[kSecAttrAccessible as String] == nil)
}

@Test
func certificateBaseAttributesCarryLabelAndAccessibility() {
    let attributes = KeychainClientIdentityStore.certificateBaseAttributes(
        label: "label",
        accessibility: kSecAttrAccessibleAfterFirstUnlock
    )
    #expect(attributes[kSecAttrLabel as String] as? String == "label")
    #expect(attributes[kSecAttrAccessible as String] as! CFString == kSecAttrAccessibleAfterFirstUnlock)
}

@Test
func accessibilityUpgradeQueriesTargetBothItems() {
    let upgrades = KeychainClientIdentityStore.accessibilityUpgrades(
        keyTag: Data("tag".utf8),
        certificateLabel: "label",
        accessibility: kSecAttrAccessibleAfterFirstUnlock
    )
    #expect(upgrades.count == 2)
    #expect(upgrades[0].query[kSecClass as String] as! CFString == kSecClassKey)
    #expect(upgrades[1].query[kSecClass as String] as! CFString == kSecClassCertificate)
    for upgrade in upgrades {
        #expect(upgrade.update[kSecAttrAccessible as String] as! CFString == kSecAttrAccessibleAfterFirstUnlock)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test` (or `HOME=$PWD/.build/home swift test --disable-sandbox`)
Expected: FAIL — `KeychainClientIdentityStore` has no members `privateKeyAttributes`, `certificateBaseAttributes`, `accessibilityUpgrades`. (If `no such module 'Testing'`, note the toolchain limitation, continue, and verify compile via `make build` after Step 3.)

- [ ] **Step 3: Implement in `Sources/PultCore/ClientIdentity.swift`**

Add to `KeychainClientIdentityStore` (alongside the existing properties):

```swift
    /// Locked-screen intents must load the identity for mutual TLS, so iOS
    /// items use after-first-unlock protection. The macOS file keychain does
    /// not support data-protection classes; there accessibility stays nil.
    public static var defaultAccessibility: CFString? {
        #if os(iOS)
        kSecAttrAccessibleAfterFirstUnlock
        #else
        nil
        #endif
    }

    private let accessibility: CFString?
    private var didUpgradeAccessibility = false
```

Change the initializer:

```swift
    public init(
        certificateLabel: String = "app.pult.client-identity",
        keyTag: String = "app.pult.client-key",
        accessibility: CFString? = KeychainClientIdentityStore.defaultAccessibility
    ) {
        self.certificateLabel = certificateLabel
        self.keyTag = Data(keyTag.utf8)
        self.accessibility = accessibility
    }
```

Add the attribute builders (internal, so tests reach them via `@testable`):

```swift
    static func privateKeyAttributes(keyTag: Data, accessibility: CFString?) -> [String: Any] {
        var privateAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: keyTag
        ]
        if let accessibility {
            privateAttrs[kSecAttrAccessible as String] = accessibility
        }
        return [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: privateAttrs
        ]
    }

    static func certificateBaseAttributes(label: String, accessibility: CFString?) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label
        ]
        if let accessibility {
            attributes[kSecAttrAccessible as String] = accessibility
        }
        return attributes
    }

    static func accessibilityUpgrades(
        keyTag: Data,
        certificateLabel: String,
        accessibility: CFString
    ) -> [(query: [String: Any], update: [String: Any])] {
        let update: [String: Any] = [kSecAttrAccessible as String: accessibility]
        return [
            (
                query: [
                    kSecClass as String: kSecClassKey,
                    kSecAttrApplicationTag as String: keyTag,
                    kSecAttrKeyType as String: kSecAttrKeyTypeRSA
                ],
                update: update
            ),
            (
                query: [
                    kSecClass as String: kSecClassCertificate,
                    kSecAttrLabel as String: certificateLabel
                ],
                update: update
            )
        ]
    }
```

Wire them in. In `createIdentity()`, replace the inline `keyAttributes` dictionary with:

```swift
        let keyAttributes = Self.privateKeyAttributes(keyTag: keyTag, accessibility: accessibility)
```

and replace the inline `addQuery` with:

```swift
        var addQuery = Self.certificateBaseAttributes(label: certificateLabel, accessibility: accessibility)
        addQuery[kSecValueRef as String] = certificate
```

In `loadOrCreateIdentity()`, call the upgrade first:

```swift
    private func loadOrCreateIdentity() throws -> SecIdentity {
        upgradeAccessibilityIfNeeded()
        if let identity = copyIdentity() {
            return identity
        }
        try createIdentity()
        guard let identity = copyIdentity() else {
            throw ClientIdentityError.identityUnavailable
        }
        return identity
    }

    /// Items created before the lock-screen feature carry when-unlocked
    /// protection; move them to the configured class so background intents
    /// can present the identity. Missing items (first run) are fine.
    private func upgradeAccessibilityIfNeeded() {
        guard let accessibility, !didUpgradeAccessibility else { return }
        didUpgradeAccessibility = true
        for upgrade in Self.accessibilityUpgrades(
            keyTag: keyTag,
            certificateLabel: certificateLabel,
            accessibility: accessibility
        ) {
            SecItemUpdate(upgrade.query as CFDictionary, upgrade.update as CFDictionary)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test` (fallback: `make build && make core-check`)
Expected: the four new tests PASS; existing tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add Sources/PultCore/ClientIdentity.swift Tests/PultCoreTests/ClientIdentityTests.swift
git commit -m "feat: store mTLS identity with after-first-unlock keychain protection"
```

---

### Task 2: App Group device store + persisted device selection

Intents need the device list and the *selected* device outside the UI lifecycle. Move `UserDefaultsDeviceStore` to the `group.app.pult` suite (with one-time migration from `.standard`) and persist the selected device ID. (The entitlements that make the suite real on device are added in Task 6.)

**Files:**
- Modify: `Sources/PultCore/DeviceDiscovery.swift`
- Modify: `Sources/PultCore/RemoteControlModel.swift:26` (selection restore) and `:34` (persist on select)
- Modify: `Tests/PultCoreTests/TestSupport.swift` (move/extend `MemoryDeviceStore`)
- Modify: `Tests/PultCoreTests/DeviceDiscoveryTests.swift` (delete its private `MemoryDeviceStore`)
- Create: `Tests/PultCoreTests/DeviceStoreTests.swift`
- Create: `Tests/PultCoreTests/RemoteControlModelTests.swift`

- [ ] **Step 1: Move `MemoryDeviceStore` into TestSupport with selection support**

Delete the private `MemoryDeviceStore` class from `Tests/PultCoreTests/DeviceDiscoveryTests.swift` (lines 5–11) and add to `Tests/PultCoreTests/TestSupport.swift`:

```swift
final class MemoryDeviceStore: DeviceStore {
    var records: [DeviceRecord] = []
    var selectedID: UUID?

    func loadDevices() -> [DeviceRecord] { records }

    func saveDevices(_ devices: [DeviceRecord]) { records = devices }

    func loadSelectedDeviceID() -> UUID? { selectedID }

    func saveSelectedDeviceID(_ id: UUID?) { selectedID = id }
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/PultCoreTests/DeviceStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import PultCore

private func makeSuite(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
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

@MainActor
@Test
func discoveryPersistsSelection() {
    let memory = MemoryDeviceStore()
    let discovery = DeviceDiscovery(store: memory)
    let device = discovery.addManualDevice(name: "TV", host: "192.168.1.42")!

    discovery.selectedDeviceID = device.id

    #expect(memory.selectedID == device.id)
}
```

Create `Tests/PultCoreTests/RemoteControlModelTests.swift`:

```swift
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
func selectingDevicePersistsSelection() {
    let store = MemoryDeviceStore()
    let first = DeviceRecord(name: "Bedroom", host: "10.0.0.1")
    let second = DeviceRecord(name: "Living Room", host: "10.0.0.2")
    store.records = [first, second]

    let model = RemoteControlModel(discovery: DeviceDiscovery(store: store))
    model.select(second)

    #expect(store.selectedID == second.id)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `DeviceStore` has no selection requirements, `UserDefaultsDeviceStore` has no `legacyDefaults:` parameter, `DeviceDiscovery` has no `selectedDeviceID`.

- [ ] **Step 4: Implement in `Sources/PultCore/DeviceDiscovery.swift`**

Add the App Group constant at file scope:

```swift
public enum PultAppGroup {
    public static let identifier = "group.app.pult"

    /// The shared suite when the App Group entitlement is present; standard
    /// defaults otherwise (SwiftPM checks, simulator without entitlements).
    public static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
```

Extend the protocol:

```swift
public protocol DeviceStore {
    func loadDevices() -> [DeviceRecord]
    func saveDevices(_ devices: [DeviceRecord])
    func loadSelectedDeviceID() -> UUID?
    func saveSelectedDeviceID(_ id: UUID?)
}
```

Replace `UserDefaultsDeviceStore` with:

```swift
public struct UserDefaultsDeviceStore: DeviceStore {
    private let key: String
    private let selectionKey: String
    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults

    public init(
        key: String = "pult.devices",
        selectionKey: String = "pult.selectedDevice",
        defaults: UserDefaults = PultAppGroup.sharedDefaults(),
        legacyDefaults: UserDefaults = .standard
    ) {
        self.key = key
        self.selectionKey = selectionKey
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
    }

    public func loadDevices() -> [DeviceRecord] {
        migrateLegacyDevicesIfNeeded()
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DeviceRecord].self, from: data)) ?? []
    }

    public func saveDevices(_ devices: [DeviceRecord]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: key)
    }

    public func loadSelectedDeviceID() -> UUID? {
        defaults.string(forKey: selectionKey).flatMap(UUID.init(uuidString:))
    }

    public func saveSelectedDeviceID(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: selectionKey)
        } else {
            defaults.removeObject(forKey: selectionKey)
        }
    }

    /// Devices saved before the App Group move live in standard defaults.
    /// Copy them into the shared suite the first time it is empty; a marker
    /// is unnecessary because a populated (or intentionally emptied) suite
    /// always has data for the key afterwards.
    private func migrateLegacyDevicesIfNeeded() {
        guard defaults !== legacyDefaults,
              defaults.data(forKey: key) == nil,
              let legacy = legacyDefaults.data(forKey: key) else { return }
        defaults.set(legacy, forKey: key)
        if defaults.string(forKey: selectionKey) == nil,
           let legacySelection = legacyDefaults.string(forKey: selectionKey) {
            defaults.set(legacySelection, forKey: selectionKey)
        }
    }
}
```

Note the migration guard: `saveDevices([])` writes an (empty) array for the key, so an intentional clear is not re-migrated — that is what the second assertion in `migratesLegacyDevicesIntoGroupSuiteOnce` checks.

Add selection to `DeviceDiscovery`:

```swift
    public var selectedDeviceID: UUID? {
        didSet {
            guard oldValue != selectedDeviceID else { return }
            store.saveSelectedDeviceID(selectedDeviceID)
        }
    }
```

and in `DeviceDiscovery.init`, after `self.devices = store.loadDevices()`:

```swift
        self.selectedDeviceID = store.loadSelectedDeviceID()
```

- [ ] **Step 5: Wire selection through `Sources/PultCore/RemoteControlModel.swift`**

In `init`, replace `self.selectedDevice = discovery.devices.first` with:

```swift
        self.selectedDevice = discovery.devices.first(where: { $0.id == discovery.selectedDeviceID })
            ?? discovery.devices.first
```

In `select(_:)` and at the end of the non-nil branch of `addManualDevice(name:host:)`, persist:

```swift
    public func select(_ device: DeviceRecord) {
        selectedDevice = device
        discovery.selectedDeviceID = device.id
    }

    public func addManualDevice(name: String, host: String) {
        guard let record = discovery.addManualDevice(name: name, host: host) else { return }
        selectedDevice = record
        discovery.selectedDeviceID = record.id
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `make test` (fallback: `make build && make core-check`)
Expected: PASS, including the pre-existing `DeviceDiscoveryTests` now using the shared `MemoryDeviceStore`.

- [ ] **Step 7: Commit**

```bash
git add Sources/PultCore/DeviceDiscovery.swift Sources/PultCore/RemoteControlModel.swift Tests/PultCoreTests
git commit -m "feat: App Group device store with persisted device selection"
```

---

### Task 3: `RemoteControlModel.performHeadlessCommand`

The single entry point intents call: connect if needed, send the key, retry once with a fresh dial when a stale "connected" session turns out dead (the common case after the app was suspended in the background).

**Files:**
- Modify: `Sources/PultCore/RemoteControlModel.swift`
- Create: `Tests/PultCoreTests/HeadlessCommandTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PultCoreTests/HeadlessCommandTests.swift`:

```swift
import Foundation
import Testing
@testable import PultCore

private let framer = VarintFramer()
private let codec = AndroidTVRemoteMessageCodec()
private let tvConfigureFrame = Data([0x0A, 0x02, 0x08, 0x01])

@MainActor
private func makeModel(transport: any RemoteTransport, device: DeviceRecord) -> RemoteControlModel {
    let store = MemoryDeviceStore()
    store.records = [device]
    store.selectedID = device.id
    return RemoteControlModel(
        discovery: DeviceDiscovery(store: store),
        session: RemoteSession(transport: transport, configureTimeout: .milliseconds(200))
    )
}

@MainActor
@Test
func headlessCommandConnectsAndSendsKey() async throws {
    let transport = MockTransport()
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: true)
    let model = makeModel(transport: transport, device: device)
    await transport.enqueueIncoming(framer.frame(tvConfigureFrame))

    let outcome = await model.performHeadlessCommand(.playPause)

    #expect(outcome == .sent)
    let sent = await transport.waitForSent(count: 2)
    #expect(sent.last == framer.frame(try codec.encode(.key(.playPause, .tap))))
}

@MainActor
@Test
func headlessCommandFailsWithoutPairedSelection() async {
    let transport = MockTransport()
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: false)
    let model = makeModel(transport: transport, device: device)

    let outcome = await model.performHeadlessCommand(.home)

    guard case .failed = outcome else {
        Issue.record("expected failure for unpaired device")
        return
    }
    let dialCount = await transport.connectCount
    #expect(dialCount == 0)
}

@MainActor
@Test
func headlessCommandReportsUnreachableTV() async {
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: true)
    let model = makeModel(transport: UnreachableTransport(), device: device)

    let outcome = await model.performHeadlessCommand(.home)

    guard case let .failed(message) = outcome else {
        Issue.record("expected failure")
        return
    }
    #expect(message.contains("192.168.1.10"))
}

@MainActor
@Test
func headlessCommandRedialsWhenStaleConnectionDies() async throws {
    let transport = StaleAfterConfigureTransport(
        configureFrame: framer.frame(tvConfigureFrame),
        configureResponse: framer.frame(codec.encodeConfigureResponse())
    )
    let device = DeviceRecord(name: "TV", host: "192.168.1.10", isPaired: true)
    let model = makeModel(transport: transport, device: device)

    // First call establishes the session normally.
    #expect(await model.performHeadlessCommand(.home) == .sent)
    await transport.killNextKeySend()

    // The session still reports connected, but the socket is dead: the model
    // must redial once and deliver on the fresh connection.
    let outcome = await model.performHeadlessCommand(.volumeUp)

    #expect(outcome == .sent)
    let dialCount = await transport.connectCount
    #expect(dialCount == 2)
    let keyPayloads = await transport.keyPayloads()
    #expect(keyPayloads.last == framer.frame(try codec.encode(.key(.volumeUp, .tap))))
}

private actor UnreachableTransport: RemoteTransport {
    func connect(to host: String, port: UInt16) async throws {
        throw RemoteTransportError.connectionFailed
    }
    func send(_ data: Data) async throws {}
    func receive() async throws -> Data { throw RemoteTransportError.disconnected }
    func close() async {}
    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? { nil }
}

/// Answers the configure handshake on every dial; key sends can be made to
/// fail exactly once to simulate a connection that died while the app was
/// suspended.
private actor StaleAfterConfigureTransport: RemoteTransport {
    private let configureFrame: Data
    private let configureResponse: Data
    private(set) var connectCount = 0
    private var incoming: [Data] = []
    private var keys: [Data] = []
    private var failNextKeySend = false
    private var closed = false

    init(configureFrame: Data, configureResponse: Data) {
        self.configureFrame = configureFrame
        self.configureResponse = configureResponse
    }

    func killNextKeySend() { failNextKeySend = true }

    func keyPayloads() -> [Data] { keys }

    func connect(to host: String, port: UInt16) async throws {
        connectCount += 1
        closed = false
        incoming = [configureFrame]
    }

    func send(_ data: Data) async throws {
        if data == configureResponse { return }
        if failNextKeySend {
            failNextKeySend = false
            throw RemoteTransportError.disconnected
        }
        keys.append(data)
    }

    func receive() async throws -> Data {
        while incoming.isEmpty {
            if closed { throw RemoteTransportError.disconnected }
            try await Task.sleep(for: .milliseconds(1))
        }
        return incoming.removeFirst()
    }

    func close() async { closed = true }

    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? { nil }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `RemoteControlModel` has no member `performHeadlessCommand`, no `HeadlessCommandOutcome`.

- [ ] **Step 3: Implement in `Sources/PultCore/RemoteControlModel.swift`**

Add at file scope:

```swift
public enum HeadlessCommandOutcome: Equatable, Sendable {
    case sent
    case failed(String)
}
```

Add to `RemoteControlModel`:

```swift
    /// Sends a key without any UI in the loop — the path used by App Intents
    /// fired from the Lock Screen, Control Center, and Siri. Reuses a live
    /// session when possible and redials once when a connection that still
    /// claims to be connected turns out dead (typical after the app spent
    /// time suspended in the background).
    public func performHeadlessCommand(_ key: RemoteKey) async -> HeadlessCommandOutcome {
        guard let selectedDevice, selectedDevice.isPaired else {
            return .failed("Open Pult and pair a TV first.")
        }

        await ensureConnected()
        if session.connectionState == .connected {
            await session.press(key)
            if session.connectionState == .connected {
                return .sent
            }
        }

        // Fresh dial: either the first connect failed outright, or the press
        // above killed a stale connection.
        await session.connect(to: selectedDevice)
        guard session.connectionState == .connected else {
            return .failed(session.lastError ?? "Could not reach \(selectedDevice.name).")
        }
        await session.press(key)
        guard session.connectionState == .connected else {
            return .failed(session.lastError ?? "Lost the connection to \(selectedDevice.name).")
        }
        return .sent
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test` (fallback: `make build && make core-check`)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PultCore/RemoteControlModel.swift Tests/PultCoreTests/HeadlessCommandTests.swift
git commit -m "feat: headless command path with single redial for intents"
```

---

### Task 4: Shared model, Live Activity plumbing, and intent rewrite (app side)

Make one `RemoteControlModel` reachable from both SwiftUI and intents, add the Live Activity attributes/controller, and replace the queue-based intent with direct headless execution. Everything here compiles for macOS too, hence the `canImport(ActivityKit)` guards and the `HeadlessRemoteIntent` typealias.

**Files:**
- Create: `Sources/PultApp/RemoteSessionActivity.swift` (shared with widget target in Task 6)
- Create: `Sources/PultApp/RemoteActivityController.swift` (app only)
- Rewrite: `Sources/PultApp/RemoteIntents.swift` (shared with widget target in Task 6)
- Modify: `Sources/PultApp/PultApp.swift`
- Modify: `Sources/PultApp/RemoteRootView.swift:32-46,143-156`
- Delete: `Sources/PultApp/SharedIntentCommandQueue.swift`
- Modify: `Sources/PultApp/Supporting/Info.plist` (NSSupportsLiveActivities)
- Modify: `Pult.xcodeproj/project.pbxproj` (file adds/removal)

- [ ] **Step 1: Create `Sources/PultApp/RemoteSessionActivity.swift`**

```swift
#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Identity and state of the lock-screen remote Live Activity. Compiled into
/// both the app and the widget extension; ActivityKit requires the exact same
/// type on both sides.
struct RemoteSessionAttributes: ActivityAttributes {
    enum Status: String, Codable, Hashable {
        case connecting
        case connected
        case failed
    }

    struct ContentState: Codable, Hashable {
        var status: Status
        var message: String?
    }

    var deviceID: UUID
    var deviceName: String
}
#endif
```

- [ ] **Step 2: Create `Sources/PultApp/RemoteActivityController.swift`**

```swift
#if canImport(ActivityKit)
import ActivityKit
import Foundation
import PultCore

/// Owns the lock-screen remote Live Activity. Lives in the app process only;
/// intents and the UI both run there, so every update flows through here.
@MainActor
final class RemoteActivityController {
    static let shared = RemoteActivityController()

    private init() {}

    func startOrUpdate(for device: DeviceRecord, state: ConnectionState, message: String? = nil) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = Self.content(for: state, message: message)
        if let activity = Self.activity(for: device.id) {
            await activity.update(content)
            return
        }
        // One remote on the lock screen at a time: switching TVs replaces it.
        for stale in Activity<RemoteSessionAttributes>.activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }
        _ = try? Activity<RemoteSessionAttributes>.request(
            attributes: RemoteSessionAttributes(deviceID: device.id, deviceName: device.name),
            content: content
        )
    }

    func noteOutcome(_ outcome: HeadlessCommandOutcome, device: DeviceRecord, state: ConnectionState) async {
        guard let activity = Self.activity(for: device.id) else { return }
        let message: String? = if case let .failed(text) = outcome { text } else { nil }
        await activity.update(Self.content(for: state, message: message))
    }

    func endAll() async {
        for activity in Activity<RemoteSessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func activity(for deviceID: UUID) -> Activity<RemoteSessionAttributes>? {
        Activity<RemoteSessionAttributes>.activities.first { $0.attributes.deviceID == deviceID }
    }

    private static func content(for state: ConnectionState, message: String?) -> ActivityContent<RemoteSessionAttributes.ContentState> {
        let contentState: RemoteSessionAttributes.ContentState = switch state {
        case .connected: .init(status: .connected, message: message)
        case .connecting: .init(status: .connecting, message: message)
        case .disconnected: .init(status: .failed, message: message ?? "Disconnected")
        case let .failed(text): .init(status: .failed, message: message ?? text)
        }
        // Without presses for a long stretch the remote is probably done;
        // let the system render it stale rather than confidently live.
        return ActivityContent(state: contentState, staleDate: Date(timeIntervalSinceNow: 4 * 60 * 60))
    }
}
#endif
```

- [ ] **Step 3: Rewrite `Sources/PultApp/RemoteIntents.swift`**

Full replacement:

```swift
import AppIntents
import Foundation
import PultCore

#if os(iOS)
/// LiveActivityIntent makes the system run perform() in the app's own
/// process — without unlocking the device and without foregrounding the app.
/// That is what lets lock-screen buttons reuse the live mTLS session.
typealias HeadlessRemoteIntent = LiveActivityIntent
#else
typealias HeadlessRemoteIntent = AppIntent
#endif

/// Process-wide model shared by the SwiftUI scene and every intent. Compiled
/// into the widget extension too (the types must exist there), but only the
/// app process ever executes perform().
@MainActor
enum SharedRemote {
    static let model = RemoteControlModel()
}

enum RemoteKeyOption: String, AppEnum {
    case up, down, left, right, select
    case back, home, power
    case volumeUp, volumeDown, mute
    case playPause, rewind, fastForward

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Remote Command")

    static let caseDisplayRepresentations: [RemoteKeyOption: DisplayRepresentation] = [
        .up: "Up", .down: "Down", .left: "Left", .right: "Right", .select: "Select",
        .back: "Back", .home: "Home", .power: "Power",
        .volumeUp: "Volume Up", .volumeDown: "Volume Down", .mute: "Mute",
        .playPause: "Play or Pause", .rewind: "Rewind", .fastForward: "Fast Forward"
    ]

    var remoteKey: RemoteKey {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .select: .select
        case .back: .back
        case .home: .home
        case .power: .power
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .mute: .mute
        case .playPause: .playPause
        case .rewind: .rewind
        case .fastForward: .fastForward
        }
    }

    var displayTitle: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .power: "Power"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .playPause: "Play or Pause"
        case .rewind: "Rewind"
        case .fastForward: "Fast Forward"
        }
    }

    var systemImage: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .select: "smallcircle.filled.circle"
        case .back: "arrow.uturn.backward"
        case .home: "house"
        case .power: "power"
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .mute: "speaker.slash"
        case .playPause: "playpause"
        case .rewind: "backward"
        case .fastForward: "forward"
        }
    }
}

struct OpenRemoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Remote"
    static let description = IntentDescription("Open Pult to the remote controls.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SendRemoteKeyIntent: HeadlessRemoteIntent {
    static let title: LocalizedStringResource = "Send Remote Command"
    static let description = IntentDescription("Send a command to the selected Google TV without opening Pult.")
    static let openAppWhenRun = false

    @Parameter(title: "Command")
    var command: RemoteKeyOption

    init() {}

    init(command: RemoteKeyOption) {
        self.command = command
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = SharedRemote.model
        let outcome = await model.performHeadlessCommand(command.remoteKey)
        #if canImport(ActivityKit)
        if let device = model.selectedDevice {
            await RemoteActivityController.shared.noteOutcome(
                outcome, device: device, state: model.session.connectionState
            )
        }
        #endif
        switch outcome {
        case .sent:
            return .result(dialog: IntentDialog(stringLiteral: "Sent \(command.displayTitle)."))
        case let .failed(message):
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
    }
}

struct StartRemoteSessionIntent: HeadlessRemoteIntent {
    static let title: LocalizedStringResource = "Show TV Remote"
    static let description = IntentDescription("Connect to the selected Google TV and put the remote on the Lock Screen.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = SharedRemote.model
        guard let device = model.selectedDevice, device.isPaired else {
            return .result(dialog: "Open Pult and pair a TV first.")
        }
        await model.ensureConnected()
        #if canImport(ActivityKit)
        await RemoteActivityController.shared.startOrUpdate(
            for: device, state: model.session.connectionState
        )
        #endif
        if case let .failed(message) = model.session.connectionState {
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
        return .result(dialog: IntentDialog(stringLiteral: "Remote ready for \(device.name)."))
    }
}

struct EndRemoteSessionIntent: HeadlessRemoteIntent {
    static let title: LocalizedStringResource = "Hide TV Remote"
    static let description = IntentDescription("Disconnect and remove the remote from the Lock Screen.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedRemote.model.session.disconnect()
        #if canImport(ActivityKit)
        await RemoteActivityController.shared.endAll()
        #endif
        return .result()
    }
}

struct PultShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRemoteIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open remote in \(.applicationName)"
            ],
            shortTitle: "Open Remote",
            systemImageName: "av.remote"
        )

        AppShortcut(
            intent: StartRemoteSessionIntent(),
            phrases: [
                "Show my TV remote with \(.applicationName)",
                "\(.applicationName) remote"
            ],
            shortTitle: "TV Remote",
            systemImageName: "av.remote"
        )

        AppShortcut(
            intent: SendRemoteKeyIntent(),
            phrases: [
                "\(\.$command) the TV with \(.applicationName)",
                "Send TV command with \(.applicationName)"
            ],
            shortTitle: "TV Command",
            systemImageName: "tv"
        )
    }
}
```

- [ ] **Step 4: Use the shared model in `Sources/PultApp/PultApp.swift`**

Full replacement of the struct body:

```swift
import SwiftUI
import PultCore

@main
struct PultApp: App {
    // The same instance intents resolve via SharedRemote, so a command sent
    // from the Lock Screen and the on-screen remote drive one session.
    private let model = SharedRemote.model

    var body: some Scene {
        WindowGroup {
            RemoteRootView(model: model)
                // Applied above the root so sheets, which inherit their
                // environment from inside RemoteRootView, pick it up too.
                .tint(.pultAccent)
        }
    }
}
```

- [ ] **Step 5: Update `Sources/PultApp/RemoteRootView.swift` and delete the queue**

Delete `Sources/PultApp/SharedIntentCommandQueue.swift` (`rm`). In `RemoteRootView.swift`:

Remove the two queue hooks (lines 35–40):

```swift
        .task {
            await drainIntentCommands()
        }
        .onReceive(NotificationCenter.default.publisher(for: SharedIntentCommandQueue.didEnqueueCommand)) { _ in
            Task { await drainIntentCommands() }
        }
```

Remove the whole `drainIntentCommands()` function (lines 148–156). Replace `autoConnectIfNeeded()` with:

```swift
    @MainActor
    private func autoConnectIfNeeded() async {
        await model.ensureConnected()
        #if canImport(ActivityKit)
        if let device = model.selectedDevice, model.session.connectionState == .connected {
            await RemoteActivityController.shared.startOrUpdate(for: device, state: .connected)
        }
        #endif
    }
```

- [ ] **Step 6: Declare Live Activity support in `Sources/PultApp/Supporting/Info.plist`**

Add inside the top-level `<dict>` (alphabetical position, after `LSRequiresIPhoneOS`):

```xml
	<key>NSSupportsLiveActivities</key>
	<true/>
```

- [ ] **Step 7: Update `Pult.xcodeproj/project.pbxproj` for the file changes**

Remove the two `SharedIntentCommandQueue.swift` object lines (`010000000000000000000008` in PBXBuildFile, `010000000000000000000108` in PBXFileReference), its child entry in group `010000000000000000000604`, and its entry in sources phase `010000000000000000000521`.

Add to the PBXBuildFile section:

```
		010000000000000000000032 /* RemoteSessionActivity.swift in Sources */ = {isa = PBXBuildFile; fileRef = 010000000000000000000132 /* RemoteSessionActivity.swift */; };
		010000000000000000000033 /* RemoteActivityController.swift in Sources */ = {isa = PBXBuildFile; fileRef = 010000000000000000000133 /* RemoteActivityController.swift */; };
```

Add to the PBXFileReference section:

```
		010000000000000000000132 /* RemoteSessionActivity.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RemoteSessionActivity.swift; sourceTree = "<group>"; };
		010000000000000000000133 /* RemoteActivityController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RemoteActivityController.swift; sourceTree = "<group>"; };
```

Add both file refs as children of group `010000000000000000000604 /* PultApp */`, and add the two build files to sources phase `010000000000000000000521`:

```
				010000000000000000000032 /* RemoteSessionActivity.swift in Sources */,
				010000000000000000000033 /* RemoteActivityController.swift in Sources */,
```

- [ ] **Step 8: Verify**

Run: `make verify`
Expected: `build` compiles the macOS variants (ActivityKit code compiled out, `HeadlessRemoteIntent == AppIntent`), `core-check` passes, `metadata-check` lints the edited plist, `xcode-project-check` finds the new files and no stale queue references.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: headless intents, shared model, and Live Activity lifecycle"
```

---

### Task 5: Widget extension sources (Live Activity UI + controls)

Pure source files; the Xcode target that compiles them lands in Task 6. They are not part of `Package.swift`, so `make build` ignores them by design.

**Files:**
- Create: `Sources/PultWidgets/PultWidgetsBundle.swift`
- Create: `Sources/PultWidgets/RemoteLiveActivity.swift`
- Create: `Sources/PultWidgets/PultControls.swift`

- [ ] **Step 1: Create `Sources/PultWidgets/PultWidgetsBundle.swift`**

```swift
import SwiftUI
import WidgetKit

@main
struct PultWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RemoteLiveActivity()
        RemoteSessionControl()
        RemoteCommandControl()
        OpenRemoteControl()
    }
}
```

- [ ] **Step 2: Create `Sources/PultWidgets/RemoteLiveActivity.swift`**

```swift
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RemoteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RemoteSessionAttributes.self) { context in
            LockScreenRemoteView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "tv")
                        Text(context.attributes.deviceName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusDot(status: context.state.status)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 18) {
                        KeyButton(command: .back)
                        KeyButton(command: .rewind)
                        KeyButton(command: .playPause)
                        KeyButton(command: .fastForward)
                        KeyButton(command: .mute)
                    }
                    .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: "tv")
            } compactTrailing: {
                StatusDot(status: context.state.status)
            } minimal: {
                Image(systemName: "tv")
            }
        }
    }
}

/// The lock-screen mini-remote. Lives inside the ~160 pt Live Activity
/// budget: one status row, then a d-pad cluster beside a command grid.
private struct LockScreenRemoteView: View {
    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(status: context.state.status)
                Text(context.attributes.deviceName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let message = context.state.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                KeyButton(command: .power, size: 26)
                Button(intent: EndRemoteSessionIntent()) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.12), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide remote")
            }
            HStack(alignment: .center, spacing: 18) {
                DPadCluster()
                Spacer(minLength: 0)
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        KeyButton(command: .back)
                        KeyButton(command: .home)
                        KeyButton(command: .playPause)
                    }
                    GridRow {
                        KeyButton(command: .volumeDown)
                        KeyButton(command: .mute)
                        KeyButton(command: .volumeUp)
                    }
                }
            }
        }
        .padding(12)
        .foregroundStyle(.white)
    }
}

private struct DPadCluster: View {
    var body: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            GridRow {
                EmptyCell()
                KeyButton(command: .up)
                EmptyCell()
            }
            GridRow {
                KeyButton(command: .left)
                KeyButton(command: .select)
                KeyButton(command: .right)
            }
            GridRow {
                EmptyCell()
                KeyButton(command: .down)
                EmptyCell()
            }
        }
    }
}

private struct EmptyCell: View {
    var body: some View {
        Color.clear.frame(width: 30, height: 30)
    }
}

private struct KeyButton: View {
    let command: RemoteKeyOption
    var size: CGFloat = 30

    var body: some View {
        Button(intent: SendRemoteKeyIntent(command: command)) {
            Image(systemName: command.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: size, height: size)
                .background(.white.opacity(0.12), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(command.displayTitle))
    }
}

private struct StatusDot: View {
    let status: RemoteSessionAttributes.Status

    private var color: Color {
        switch status {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(Text(status.rawValue))
    }
}
```

- [ ] **Step 3: Create `Sources/PultWidgets/PultControls.swift`**

```swift
import AppIntents
import SwiftUI
import WidgetKit

/// The hero control for a Lock Screen slot or the Action button: one press
/// connects to the selected TV and summons the Live Activity remote.
struct RemoteSessionControl: ControlWidget {
    static let kind = "app.pult.controls.session"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartRemoteSessionIntent()) {
                Label("TV Remote", systemImage: "av.remote")
            }
        }
        .displayName("TV Remote")
        .description("Connects to your Google TV and puts the remote on the Lock Screen.")
    }
}

/// A single-command button the user configures (play/pause by default).
struct RemoteCommandControl: ControlWidget {
    static let kind = "app.pult.controls.command"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: RemoteCommandProvider()
        ) { command in
            ControlWidgetButton(action: SendRemoteKeyIntent(command: command)) {
                Label(command.displayTitle, systemImage: command.systemImage)
            }
        }
        .displayName("TV Command")
        .description("Sends one command to your Google TV.")
    }
}

struct RemoteCommandProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectRemoteCommandIntent) -> RemoteKeyOption {
        configuration.command
    }

    func currentValue(configuration: SelectRemoteCommandIntent) async throws -> RemoteKeyOption {
        configuration.command
    }
}

struct SelectRemoteCommandIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose TV Command"

    @Parameter(title: "Command", default: .playPause)
    var command: RemoteKeyOption

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Opens the full app (touchpad, pairing). Requires unlock, by design.
struct OpenRemoteControl: ControlWidget {
    static let kind = "app.pult.controls.open"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenRemoteIntent()) {
                Label("Open Pult", systemImage: "appletvremote.gen4.fill")
            }
        }
        .displayName("Open Pult")
        .description("Opens the full remote.")
    }
}
```

- [ ] **Step 4: Sanity check that SwiftPM still ignores the new directory**

Run: `make build`
Expected: builds exactly as before (no `PultWidgets` module).

- [ ] **Step 5: Commit**

```bash
git add Sources/PultWidgets
git commit -m "feat: widget extension sources for Live Activity remote and controls"
```

---

### Task 6: PultWidgets target, entitlements, and verification plumbing

Wire the extension into `Pult.xcodeproj` by hand (the project uses synthetic sequential object IDs — continue the pattern), add App Group entitlements to both targets, give the extension its Info.plist, and extend the Makefile checks.

**Files:**
- Create: `Sources/PultApp/Pult.entitlements`
- Create: `Sources/PultWidgets/PultWidgets.entitlements`
- Create: `Sources/PultWidgets/Supporting/Info.plist`
- Modify: `Pult.xcodeproj/project.pbxproj`
- Modify: `Makefile`

- [ ] **Step 1: Create both entitlements files**

`Sources/PultApp/Pult.entitlements` and `Sources/PultWidgets/PultWidgets.entitlements`, identical content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.app.pult</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Create `Sources/PultWidgets/Supporting/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>Pult Widgets</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 3: Add the target to `Pult.xcodeproj/project.pbxproj`**

All insertions, by section (IDs continue the project's existing synthetic scheme):

**PBXBuildFile** — append:

```
		010000000000000000000034 /* PultWidgetsBundle.swift in Sources */ = {isa = PBXBuildFile; fileRef = 010000000000000000000134 /* PultWidgetsBundle.swift */; };
		010000000000000000000035 /* RemoteLiveActivity.swift in Sources */ = {isa = PBXBuildFile; fileRef = 010000000000000000000135 /* RemoteLiveActivity.swift */; };
		010000000000000000000036 /* PultControls.swift in Sources */ = {isa = PBXBuildFile; fileRef = 010000000000000000000136 /* PultControls.swift */; };
		010000000000000000000037 /* RemoteIntents.swift in Sources */ = {isa = PBXBuildFile; fileRef = 010000000000000000000105 /* RemoteIntents.swift */; };
		010000000000000000000038 /* RemoteSessionActivity.swift in Sources */ = {isa = PBXBuildFile; fileRef = 010000000000000000000132 /* RemoteSessionActivity.swift */; };
		010000000000000000000039 /* PultCore.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = 010000000000000000000202 /* PultCore.framework */; };
		010000000000000000000040 /* PultWidgets.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = 010000000000000000000203 /* PultWidgets.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
```

(`037`/`038` give `RemoteIntents.swift` and `RemoteSessionActivity.swift` their second target membership — same file refs as the app.)

**PBXContainerItemProxy** — append:

```
		010000000000000000000303 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 010000000000000000000900 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 010000000000000000000403;
			remoteInfo = PultWidgets;
		};
		010000000000000000000305 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 010000000000000000000900 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 010000000000000000000402;
			remoteInfo = PultCore;
		};
```

**PBXCopyFilesBuildPhase** — append:

```
		010000000000000000000503 /* Embed Foundation Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				010000000000000000000040 /* PultWidgets.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
```

**PBXFileReference** — append:

```
		010000000000000000000134 /* PultWidgetsBundle.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PultWidgetsBundle.swift; sourceTree = "<group>"; };
		010000000000000000000135 /* RemoteLiveActivity.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RemoteLiveActivity.swift; sourceTree = "<group>"; };
		010000000000000000000136 /* PultControls.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PultControls.swift; sourceTree = "<group>"; };
		010000000000000000000137 /* Supporting/Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Supporting/Info.plist; sourceTree = "<group>"; };
		010000000000000000000138 /* Pult.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Pult.entitlements; sourceTree = "<group>"; };
		010000000000000000000139 /* PultWidgets.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = PultWidgets.entitlements; sourceTree = "<group>"; };
		010000000000000000000203 /* PultWidgets.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = PultWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; };
```

**PBXFrameworksBuildPhase** — append:

```
		010000000000000000000513 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				010000000000000000000039 /* PultCore.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

**PBXGroup** — add `010000000000000000000606 /* PultWidgets */` to the children of `010000000000000000000602 /* Sources */`, add `010000000000000000000203 /* PultWidgets.appex */` to the children of `010000000000000000000603 /* Products */`, add `010000000000000000000138 /* Pult.entitlements */` to the children of `010000000000000000000604 /* PultApp */`, and append the new group:

```
		010000000000000000000606 /* PultWidgets */ = {
			isa = PBXGroup;
			children = (
				010000000000000000000134 /* PultWidgetsBundle.swift */,
				010000000000000000000135 /* RemoteLiveActivity.swift */,
				010000000000000000000136 /* PultControls.swift */,
				010000000000000000000139 /* PultWidgets.entitlements */,
				010000000000000000000137 /* Supporting/Info.plist */,
			);
			path = PultWidgets;
			sourceTree = "<group>";
		};
```

**PBXNativeTarget** — in target `010000000000000000000401 /* Pult */`, add `010000000000000000000503 /* Embed Foundation Extensions */` after the Embed Frameworks phase and `010000000000000000000304 /* PBXTargetDependency */` to `dependencies`. Append the new target:

```
		010000000000000000000403 /* PultWidgets */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 010000000000000000000703 /* Build configuration list for PBXNativeTarget "PultWidgets" */;
			buildPhases = (
				010000000000000000000523 /* Sources */,
				010000000000000000000513 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				010000000000000000000306 /* PBXTargetDependency */,
			);
			name = PultWidgets;
			productName = PultWidgets;
			productReference = 010000000000000000000203 /* PultWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		};
```

**PBXProject** — add to `TargetAttributes`:

```
					010000000000000000000403 = {
						CreatedOnToolsVersion = 26.0;
					};
```

and append `010000000000000000000403 /* PultWidgets */,` to `targets`.

**PBXSourcesBuildPhase** — append:

```
		010000000000000000000523 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				010000000000000000000034 /* PultWidgetsBundle.swift in Sources */,
				010000000000000000000035 /* RemoteLiveActivity.swift in Sources */,
				010000000000000000000036 /* PultControls.swift in Sources */,
				010000000000000000000037 /* RemoteIntents.swift in Sources */,
				010000000000000000000038 /* RemoteSessionActivity.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

**PBXTargetDependency** — append:

```
		010000000000000000000304 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 010000000000000000000403 /* PultWidgets */;
			targetProxy = 010000000000000000000303 /* PBXContainerItemProxy */;
		};
		010000000000000000000306 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 010000000000000000000402 /* PultCore */;
			targetProxy = 010000000000000000000305 /* PBXContainerItemProxy */;
		};
```

**XCBuildConfiguration** — add to BOTH app configurations (`010000000000000000000720` and `010000000000000000000721`), alphabetically before `CODE_SIGN_STYLE`:

```
				CODE_SIGN_ENTITLEMENTS = Sources/PultApp/Pult.entitlements;
```

Append the widget configurations:

```
		010000000000000000000740 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = Sources/PultWidgets/PultWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 4HZ5WYBH8E;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Sources/PultWidgets/Supporting/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 26.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.pult.Pult.PultWidgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = 1;
			};
			name = Debug;
		};
		010000000000000000000741 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = Sources/PultWidgets/PultWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 4HZ5WYBH8E;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Sources/PultWidgets/Supporting/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 26.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.pult.Pult.PultWidgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = 1;
			};
			name = Release;
		};
```

**XCConfigurationList** — append:

```
		010000000000000000000703 /* Build configuration list for PBXNativeTarget "PultWidgets" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				010000000000000000000740 /* Debug */,
				010000000000000000000741 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

- [ ] **Step 4: Extend the Makefile checks**

Add after `PULT_CORE_SOURCES`:

```make
PULT_WIDGETS_GROUP = 010000000000000000000606
PULT_WIDGETS_SOURCES = 010000000000000000000523
```

In `metadata-check`, extend the `plutil -lint` line to also cover:

```
Sources/PultWidgets/Supporting/Info.plist Sources/PultApp/Pult.entitlements Sources/PultWidgets/PultWidgets.entitlements
```

In `xcode-project-check`, duplicate the `Sources/PultCore/*.swift` loop for the widgets directory (before `exit $$missing`):

```make
	for file in Sources/PultWidgets/*.swift; do \
		name=$$(basename "$$file"); \
		if ! grep -Fq "path = $$name;" "$(XCODE_PROJECT)"; then \
			echo "Missing Xcode file reference: $$file"; \
			missing=1; \
		fi; \
		check_section "$(PULT_WIDGETS_GROUP)" "$$name" "PultWidgets group" "$$file"; \
		check_sources_phase "$(PULT_WIDGETS_SOURCES)" "$$name" "PultWidgets target" "$$file"; \
	done; \
```

- [ ] **Step 5: Verify**

Run: `make verify`
Expected: all four sub-checks pass, including the new PultWidgets loop and the plutil lint of the new plists. Also run `plutil -lint Pult.xcodeproj/project.pbxproj` directly if verify fails, to localize pbxproj syntax errors.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: PultWidgets extension target, App Group entitlements, checks"
```

---

### Task 7: Xcode device build + lock-screen verification (manual, with the user)

No code. This validates the claims we are not allowed to make without device evidence. Requires Xcode 26+, a physical iPhone on iOS 26, and the paired Google TV on the same network.

- [ ] **Step 1: Build & run** — open `Pult.xcodeproj`, scheme `Pult Release Direct`, set signing team if needed (the App Group `group.app.pult` must be registered for both bundle IDs in the developer account), run on the iPhone. Clean build folder + delete the stale app first (bundle/entitlements changed).
- [ ] **Step 2: Migration** — existing device records and pairing survive the update (App Group + keychain migration worked). Pair fresh if this is a new install.
- [ ] **Step 3: Foreground flow** — connect to the TV in-app; the Live Activity appears. Lock the phone: the mini-remote renders on the lock screen within the height budget.
- [ ] **Step 4: Locked input** — with the phone locked (Face ID covered), press d-pad/volume/play buttons. Commands must reach the TV with no unlock prompt. Measure press-to-TV latency; cold presses (after ~1 min locked) should stay ~1 s on LAN.
- [ ] **Step 5: Controls** — add "TV Remote" to a lock-screen slot via lock-screen customization; press it while locked → Live Activity appears and connects. Add "TV Command" to Control Center and configure it to Mute; verify. Verify the Action button mapping if the device has one.
- [ ] **Step 6: Siri** — "Show my TV remote with Pult" and "Play or Pause the TV with Pult" from the locked phone.
- [ ] **Step 7: Failure UX** — unplug the TV's network, press a button while locked: status dot turns red and the message line shows the error; no unlock prompt, no crash. Reconnect and confirm recovery on next press.
- [ ] **Step 8: Record evidence** — note results per item in `Docs/` (or the README's verification section) before claiming the feature works, per AGENTS.md.

---

## Out of scope (explicitly)

Touchpad/gestures on the lock screen, hold-to-repeat volume, push-token Live Activity updates, interactive snippets (Siri-only stretch), Apple Watch, accessory widgets, IME text entry. See the spec for rationale.
