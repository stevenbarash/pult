# Protocol Observations Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reach protocol/state parity with `tronikos/androidtvremote2` for observable Android TV Remote v2 protocol state first: feature/capability codes, configure/set-active negotiation observations, `remote_start`, IME app/edit observations, volume, ping, and voice session begin. This stage must not claim authoritative TV power state, global current app, or physical-device validation.

**Architecture:** Keep all wire protocol parsing and typed protocol observations in `PultCore`. `RemoteMessageCodec` decodes richer incoming messages while preserving existing response bytes. `RemoteSession` owns attempt-scoped observation state and updates it only for the active connection attempt. `PultApp` diagnostics render the observations as session-scoped protocol data, separate from validation reports. Documentation is updated to distinguish protocol observations from validated TV behavior.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing where available, `PultCoreCheck`, existing Android TV Remote v2 codec, existing Makefile verification targets.

---

## File Structure

Modify these files only for this stage:

```text
Sources/PultCore/RemoteMessageCodec.swift
  Add RemoteProtocolFeature, RemoteProtocolCode, RemoteDeviceInfo,
  RemoteConfigureRequest, RemoteSetActiveRequest, RemoteAppInfo,
  RemoteImeObjectObservation, RemoteEditInfoObservation,
  RemoteImeKeyInjectObservation, RemoteImeBatchEditObservation,
  RemoteProtocolObservation, RemoteProtocolNegotiation,
  RemoteSessionProtocolState, RemoteProtocolNegotiator.
  Expand IncomingRemoteMessage payloads.
  Decode configure/set-active/remote_start/IME observations.
  Preserve 622 configure and set-active response bytes.

Sources/PultCore/RemoteSession.swift
  Add attempt-scoped protocolState.
  Update state from richer IncomingRemoteMessage cases.
  Reset observations on new attempts, disconnects, and current-attempt failures.
  Keep stale attempt updates out of active state.

Sources/PultCoreCheck/main.swift
  Add smoke coverage for richer decode and protocol state preservation.

Tests/PultCoreTests/RemoteMessageCodecTests.swift
  Add richer codec tests for protocol observations and response stability.

Tests/PultCoreTests/RemoteSessionTests.swift
  Add richer session-state tests and reset/stale-attempt coverage.

Sources/PultApp/RemoteDiagnosticsFormatting.swift
  Add diagnostic formatting for protocol observation types.

Sources/PultApp/DiagnosticsAndValidationView.swift
  Add Protocol Observations UI section and copied diagnostics block.

Docs/LatencyMeasurementMethodology.md
Docs/ProductStrategy.md
Docs/superpowers/specs/2026-06-15-warm-live-session-design.md
appideas.md
Docs/ProtocolSources.md
Docs/Observability.md
Docs/PhysicalDeviceValidationChecklist.md
README.md
  Replace stale "not exposed" language with protocol-observation language.
```

Do not add a new Swift source file in this pass. Keeping changes inside existing Swift files avoids Xcode project membership churn and lets `make xcode-project-check` remain a verification guard rather than an implementation task.

---

## Task 1: Add Codec Tests For Rich Protocol Observations

- [ ] Open [RemoteMessageCodecTests.swift](/Users/nyetwork/Developer/pult/Tests/PultCoreTests/RemoteMessageCodecTests.swift).

- [ ] Replace the existing `.configure` and `.setActive` expectations inside `decodesIncomingMessages` with typed payload expectations, and use `remoteConfigureFrame(...)` / `remoteSetActiveFrame(...)` helpers instead of the current raw configure and set-active `Data` literals:

```swift
case let .configure(request):
    #expect(request.code?.rawValue == 64)
    #expect(request.code?.features == [.volume])
    #expect(request.deviceInfo?.vendor == "Google")
    #expect(request.deviceInfo?.model == "TV")
    #expect(request.deviceInfo?.packageName == "com.google.android.tv.remote.service")
    #expect(request.deviceInfo?.appVersion == "5.2.473254133")
default:
    Issue.record("Expected configure request")
```

```swift
case let .setActive(request):
    #expect(request.active?.rawValue == 622)
    #expect(request.active?.features.contains(.volume) == true)
    #expect(request.active?.features.contains(.appLink) == true)
default:
    Issue.record("Expected set-active request")
```

- [ ] Add this test to the same test type:

```swift
@Test("Protocol feature codes decode known and unknown bits")
func protocolFeatureCodeDecoding() {
    let code = RemoteProtocolCode(rawValue: 622)

    #expect(code.features.contains(.key))
    #expect(code.features.contains(.ime))
    #expect(code.features.contains(.voice))
    #expect(code.features.contains(.unknown1))
    #expect(code.features.contains(.powerCommandCapability))
    #expect(code.features.contains(.volume))
    #expect(code.features.contains(.appLink))
    #expect(!code.features.contains(.ping))
    #expect(code.unknownBits == 0)
    #expect(code.labels == ["key", "ime", "voice", "unknown1", "powerCommandCapability", "volume", "appLink"])

    let unknown = RemoteProtocolCode(rawValue: 1024 + 64)
    #expect(unknown.features == [.volume])
    #expect(unknown.unknownBits == 1024)
    #expect(unknown.labels == ["volume", "unknown(1024)"])
}
```

- [ ] Add this test to prove `remote_start` is optional-field aware and not an invented power state:

```swift
@Test("Remote start decodes only when started field is present")
func remoteStartRequiresStartedField() throws {
    switch try codec.decode(remoteStartFrame(started: true)) {
    case .started(true):
        break
    default:
        Issue.record("Expected started(true)")
    }

    switch try codec.decode(remoteStartFrame(started: false)) {
    case .started(false):
        break
    default:
        Issue.record("Expected started(false)")
    }

    switch try codec.decode(remoteStartWithoutStartedFieldFrame()) {
    case .other:
        break
    default:
        Issue.record("Expected remote_start without started field to decode as other")
    }
}
```

- [ ] Add this test for IME app and edit observations:

```swift
@Test("IME key inject and batch edit preserve app and edit observations")
func imeObservationsPreserveAppAndEdits() throws {
    switch try codec.decode(remoteImeKeyInjectFrame(
        packageName: "com.netflix.ninja",
        appLabel: "Netflix",
        counter: 42,
        value: "search",
        selectionStart: 6,
        selectionEnd: 6
    )) {
    case let .imeKeyInject(observation):
        #expect(observation.appInfo?.appPackage == "com.netflix.ninja")
        #expect(observation.appInfo?.label == "Netflix")
        #expect(observation.textFieldStatus?.counter == 42)
        #expect(observation.textFieldStatus?.value == "search")
        #expect(observation.textFieldStatus?.selectionStart == 6)
        #expect(observation.textFieldStatus?.selectionEnd == 6)
    default:
        Issue.record("Expected IME key-inject observation")
    }

    switch try codec.decode(remoteImeBatchEditFrame(
        imeCounter: 3,
        fieldCounter: 43,
        edits: [
            RemoteImeObjectFixture(value: "sea", selectionStart: 3, selectionEnd: 3),
            RemoteImeObjectFixture(value: "search", selectionStart: 6, selectionEnd: 6)
        ]
    )) {
    case let .imeBatchEdit(observation):
        #expect(observation.imeCounter == 3)
        #expect(observation.fieldCounter == 43)
        #expect(observation.edits.count == 2)
        #expect(observation.edits[0].object?.value == "sea")
        #expect(observation.edits[1].object?.value == "search")
        #expect(observation.derivedTextFieldStatus?.imeCounter == 3)
        #expect(observation.derivedTextFieldStatus?.counter == 43)
        #expect(observation.derivedTextFieldStatus?.value == "search")
    default:
        Issue.record("Expected IME batch edit observation")
    }
}
```

- [ ] Add these helper fixtures near the existing private frame helpers:

```swift
private struct RemoteImeObjectFixture {
    let value: String
    let selectionStart: UInt64
    let selectionEnd: UInt64
}

private func remoteConfigureFrame(
    code: UInt64 = 64,
    vendor: String = "Google",
    model: String = "TV",
    packageName: String = "com.google.android.tv.remote.service",
    appVersion: String = "5.2.473254133"
) -> Data {
    var deviceInfo = ProtobufEncoder()
    deviceInfo.appendString(field: 1, model)
    deviceInfo.appendString(field: 2, vendor)
    deviceInfo.appendVarint(field: 3, 1)
    deviceInfo.appendString(field: 4, "1")
    deviceInfo.appendString(field: 5, packageName)
    deviceInfo.appendString(field: 6, appVersion)

    var configure = ProtobufEncoder()
    configure.appendVarint(field: 1, code)
    configure.appendMessage(field: 2, deviceInfo.data)

    var message = ProtobufEncoder()
    message.appendMessage(field: 1, configure.data)
    return message.data
}

private func remoteSetActiveFrame(code: UInt64?) -> Data {
    var setActive = ProtobufEncoder()
    if let code {
        setActive.appendVarint(field: 1, code)
    }

    var message = ProtobufEncoder()
    message.appendMessage(field: 2, setActive.data)
    return message.data
}

private func remoteStartFrame(started: Bool) -> Data {
    var start = ProtobufEncoder()
    start.appendVarint(field: 1, started ? 1 : 0)

    var message = ProtobufEncoder()
    message.appendMessage(field: 40, start.data)
    return message.data
}

private func remoteStartWithoutStartedFieldFrame() -> Data {
    var start = ProtobufEncoder()
    start.appendVarint(field: 2, 1)

    var message = ProtobufEncoder()
    message.appendMessage(field: 40, start.data)
    return message.data
}

private func remoteImeKeyInjectFrame(
    packageName: String,
    appLabel: String,
    counter: UInt64,
    value: String,
    selectionStart: UInt64,
    selectionEnd: UInt64
) -> Data {
    var app = ProtobufEncoder()
    app.appendVarint(field: 1, 1)
    app.appendString(field: 10, appLabel)
    app.appendString(field: 12, packageName)

    var status = ProtobufEncoder()
    status.appendVarint(field: 1, counter)
    status.appendString(field: 2, value)
    status.appendVarint(field: 3, selectionStart)
    status.appendVarint(field: 4, selectionEnd)

    var keyInject = ProtobufEncoder()
    keyInject.appendMessage(field: 1, app.data)
    keyInject.appendMessage(field: 2, status.data)

    var message = ProtobufEncoder()
    message.appendMessage(field: 20, keyInject.data)
    return message.data
}

private func remoteImeBatchEditFrame(
    imeCounter: UInt64,
    fieldCounter: UInt64,
    edits: [RemoteImeObjectFixture]
) -> Data {
    var batchEdit = ProtobufEncoder()
    batchEdit.appendVarint(field: 1, imeCounter)
    batchEdit.appendVarint(field: 2, fieldCounter)
    for edit in edits {
        var object = ProtobufEncoder()
        object.appendVarint(field: 1, edit.selectionStart)
        object.appendVarint(field: 2, edit.selectionEnd)
        object.appendString(field: 3, edit.value)

        var editInfo = ProtobufEncoder()
        editInfo.appendVarint(field: 1, 1)
        editInfo.appendMessage(field: 2, object.data)

        batchEdit.appendMessage(field: 3, editInfo.data)
    }

    var message = ProtobufEncoder()
    message.appendMessage(field: 21, batchEdit.data)
    return message.data
}
```

- [ ] Run:

```sh
swift test --filter RemoteMessageCodecTests
```

Expected result before implementation:

```text
FAIL: cannot find type RemoteProtocolCode
```

If this environment reports `no such module 'Testing'`, record that as the known local Swift Testing toolchain issue and continue to the implementation plus `PultCoreCheck` task.

---

## Task 2: Implement Rich Codec Types And Decode Paths

- [ ] Open [RemoteMessageCodec.swift](/Users/nyetwork/Developer/pult/Sources/PultCore/RemoteMessageCodec.swift).

- [ ] Add these types after `RemoteClientInfo` and before `AndroidTVRemoteMessageCodec`:

```swift
public struct RemoteProtocolFeature: OptionSet, Equatable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let ping = Self(rawValue: 1)
    public static let key = Self(rawValue: 2)
    public static let ime = Self(rawValue: 4)
    public static let voice = Self(rawValue: 8)
    public static let unknown1 = Self(rawValue: 16)
    public static let powerCommandCapability = Self(rawValue: 32)
    public static let volume = Self(rawValue: 64)
    public static let appLink = Self(rawValue: 512)

    public static let knownMask: UInt64 = [
        Self.ping.rawValue,
        Self.key.rawValue,
        Self.ime.rawValue,
        Self.voice.rawValue,
        Self.unknown1.rawValue,
        Self.powerCommandCapability.rawValue,
        Self.volume.rawValue,
        Self.appLink.rawValue
    ].reduce(0, |)

    public var labels: [String] {
        var result: [String] = []
        if contains(.ping) { result.append("ping") }
        if contains(.key) { result.append("key") }
        if contains(.ime) { result.append("ime") }
        if contains(.voice) { result.append("voice") }
        if contains(.unknown1) { result.append("unknown1") }
        if contains(.powerCommandCapability) { result.append("powerCommandCapability") }
        if contains(.volume) { result.append("volume") }
        if contains(.appLink) { result.append("appLink") }
        return result
    }
}

public struct RemoteProtocolCode: Equatable, Sendable {
    public var rawValue: UInt64
    public var features: RemoteProtocolFeature
    public var unknownBits: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
        features = RemoteProtocolFeature(rawValue: rawValue & RemoteProtocolFeature.knownMask)
        unknownBits = rawValue & ~RemoteProtocolFeature.knownMask
    }

    public var labels: [String] {
        var result = features.labels
        if unknownBits != 0 {
            result.append("unknown(\(unknownBits))")
        }
        return result
    }
}

public struct RemoteDeviceInfo: Equatable, Sendable {
    public var model: String?
    public var vendor: String?
    public var unknown1: Int?
    public var unknown2: String?
    public var packageName: String?
    public var appVersion: String?

    public init(model: String?, vendor: String?, unknown1: Int?, unknown2: String?, packageName: String?, appVersion: String?) {
        self.model = model
        self.vendor = vendor
        self.unknown1 = unknown1
        self.unknown2 = unknown2
        self.packageName = packageName
        self.appVersion = appVersion
    }
}

public struct RemoteConfigureRequest: Equatable, Sendable {
    public var code: RemoteProtocolCode?
    public var deviceInfo: RemoteDeviceInfo?
}

public struct RemoteSetActiveRequest: Equatable, Sendable {
    public var active: RemoteProtocolCode?
}

public struct RemoteAppInfo: Equatable, Sendable {
    public var counter: Int?
    public var unknownInt2: Int?
    public var unknownInt3: Int?
    public var unknownString4: String?
    public var unknownInt7: Int?
    public var unknownInt8: Int?
    public var label: String?
    public var appPackage: String?
    public var unknownInt13: Int?
}

public struct RemoteImeObjectObservation: Equatable, Sendable {
    public var value: String
    public var selectionStart: Int
    public var selectionEnd: Int
}

public struct RemoteEditInfoObservation: Equatable, Sendable {
    public var editType: Int
    public var object: RemoteImeObjectObservation?
}

public struct RemoteImeKeyInjectObservation: Equatable, Sendable {
    public var appInfo: RemoteAppInfo?
    public var textFieldStatus: RemoteTextFieldStatus?
}

public struct RemoteImeBatchEditObservation: Equatable, Sendable {
    public var imeCounter: Int
    public var fieldCounter: Int
    public var edits: [RemoteEditInfoObservation]

    public var derivedTextFieldStatus: RemoteTextFieldStatus? {
        guard let last = edits.last?.object else { return nil }
        return RemoteTextFieldStatus(
            imeCounter: max(imeCounter, 1),
            counter: fieldCounter,
            value: last.value,
            selectionStart: last.selectionStart,
            selectionEnd: last.selectionEnd
        )
    }
}

public struct RemoteProtocolObservation<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value
    public var observedAt: Date
    public var deviceID: UUID?
    public var connectionAttempt: Int
    public var source: String

    public init(
        value: Value,
        observedAt: Date = Date(),
        deviceID: UUID?,
        connectionAttempt: Int,
        source: String
    ) {
        self.value = value
        self.observedAt = observedAt
        self.deviceID = deviceID
        self.connectionAttempt = connectionAttempt
        self.source = source
    }
}

public struct RemoteProtocolNegotiation: Equatable, Sendable {
    public var inboundConfigureCode: RemoteProtocolObservation<RemoteProtocolCode>?
    public var outboundConfigureCode: RemoteProtocolObservation<RemoteProtocolCode>?
    public var inboundSetActiveCode: RemoteProtocolObservation<RemoteProtocolCode>?
    public var outboundSetActiveCode: RemoteProtocolObservation<RemoteProtocolCode>?
}

public struct RemoteSessionProtocolState: Equatable, Sendable {
    public var negotiation = RemoteProtocolNegotiation()
    public var deviceInfo: RemoteProtocolObservation<RemoteDeviceInfo>?
    public var remoteStart: RemoteProtocolObservation<Bool>?
    public var imeApp: RemoteProtocolObservation<RemoteAppInfo>?
    public var lastImeBatchEdit: RemoteProtocolObservation<RemoteImeBatchEditObservation>?
    public var lastImeKeyInject: RemoteProtocolObservation<RemoteImeKeyInjectObservation>?

    public init() {}
}

public struct RemoteProtocolNegotiator: Equatable, Sendable {
    public static let defaultClientResponseRawCode: UInt64 = 622

    public var clientResponseCode: RemoteProtocolCode

    public init(clientResponseCode: RemoteProtocolCode = RemoteProtocolCode(rawValue: Self.defaultClientResponseRawCode)) {
        self.clientResponseCode = clientResponseCode
    }
}
```

- [ ] Replace the first two cases of `IncomingRemoteMessage` and add IME cases:

```swift
public enum IncomingRemoteMessage: Equatable, Sendable {
    case configure(RemoteConfigureRequest)
    case setActive(RemoteSetActiveRequest)
    case pingRequest(UInt64)
    case error
    case started(Bool)
    case volume(level: UInt64, maximum: UInt64, muted: Bool)
    case textFieldStatus(RemoteTextFieldStatus)
    case imeKeyInject(RemoteImeKeyInjectObservation)
    case imeBatchEdit(RemoteImeBatchEditObservation)
    case voiceBegin(sessionID: Int)
    case other
}
```

- [ ] Expose the preserved 622 response code without changing the encoded response bytes:

```swift
public var clientResponseCode: RemoteProtocolCode {
    RemoteProtocolCode(rawValue: Self.activeCode)
}
```

Place this inside `AndroidTVRemoteMessageCodec`.

- [ ] Update the `activeCode` comment to remove the overconfident phrase "Active-client marker". Use this wording:

```swift
// Observed client response code used by AOSP-compatible v2 remotes for
// configure and set-active responses. Keep the byte sequence stable until
// physical-device evidence proves a different negotiation is required.
private static let activeCode: UInt64 = RemoteProtocolNegotiator.defaultClientResponseRawCode
```

- [ ] Update `decode(_:)` switch mappings so configure, set-active, `remote_start`, IME key-inject, IME show, and IME batch edit use richer helpers:

```swift
case FieldNumber.configure:
    return .configure(try decodeConfigure(field.bytes))
case FieldNumber.setActive:
    return .setActive(try decodeSetActive(field.bytes))
case FieldNumber.start:
    guard let started = try optionalFirstVarint(field: 1, in: field.bytes) else {
        return .other
    }
    return .started(started == 1)
case FieldNumber.imeKeyInject:
    return .imeKeyInject(try decodeImeKeyInject(field.bytes))
case FieldNumber.imeShowRequest:
    if let status = try textFieldStatus(fromContainer: field.bytes) {
        return .textFieldStatus(status)
    }
    return .other
case FieldNumber.imeBatchEdit:
    return .imeBatchEdit(try decodeImeBatchEdit(field.bytes))
```

- [ ] Add private decode helpers in `AndroidTVRemoteMessageCodec`. They must be pure and must not mutate session state:

```swift
private func decodeConfigure(_ payload: Data) throws -> RemoteConfigureRequest {
    let deviceInfoPayload = try optionalFirstLengthDelimited(field: 2, in: payload)
    RemoteConfigureRequest(
        code: try optionalFirstVarint(field: 1, in: payload).map(RemoteProtocolCode.init(rawValue:)),
        deviceInfo: try deviceInfoPayload.map(decodeRemoteDeviceInfo)
    )
}

private func decodeRemoteDeviceInfo(_ payload: Data) throws -> RemoteDeviceInfo {
    RemoteDeviceInfo(
        model: try optionalFirstString(field: 1, in: payload),
        vendor: try optionalFirstString(field: 2, in: payload),
        unknown1: try optionalFirstVarint(field: 3, in: payload).map(Int.init),
        unknown2: try optionalFirstString(field: 4, in: payload),
        packageName: try optionalFirstString(field: 5, in: payload),
        appVersion: try optionalFirstString(field: 6, in: payload)
    )
}

private func decodeSetActive(_ payload: Data) throws -> RemoteSetActiveRequest {
    RemoteSetActiveRequest(active: try optionalFirstVarint(field: 1, in: payload).map(RemoteProtocolCode.init(rawValue:)))
}

private func decodeImeKeyInject(_ payload: Data) throws -> RemoteImeKeyInjectObservation {
    let appPayload = try optionalFirstLengthDelimited(field: 1, in: payload)
    let statusPayload = try optionalFirstLengthDelimited(field: 2, in: payload)
    return RemoteImeKeyInjectObservation(
        appInfo: try appPayload.map(decodeRemoteAppInfo),
        textFieldStatus: try statusPayload.map(textFieldStatus(from:))
    )
}

private func decodeRemoteAppInfo(_ payload: Data) throws -> RemoteAppInfo {
    RemoteAppInfo(
        counter: try optionalFirstVarint(field: 1, in: payload).map(Int.init),
        unknownInt2: try optionalFirstVarint(field: 2, in: payload).map(Int.init),
        unknownInt3: try optionalFirstVarint(field: 3, in: payload).map(Int.init),
        unknownString4: try optionalFirstString(field: 4, in: payload),
        unknownInt7: try optionalFirstVarint(field: 7, in: payload).map(Int.init),
        unknownInt8: try optionalFirstVarint(field: 8, in: payload).map(Int.init),
        label: try optionalFirstString(field: 10, in: payload),
        appPackage: try optionalFirstString(field: 12, in: payload),
        unknownInt13: try optionalFirstVarint(field: 13, in: payload).map(Int.init)
    )
}

private func decodeImeBatchEdit(_ payload: Data) throws -> RemoteImeBatchEditObservation {
    let imeCounter = Int(try optionalFirstVarint(field: 1, in: payload) ?? 1)
    let fieldCounter = Int(try optionalFirstVarint(field: 2, in: payload) ?? 0)
    let edits = try repeatedLengthDelimited(field: 3, in: payload).map { editPayload in
        RemoteEditInfoObservation(
            editType: Int(try optionalFirstVarint(field: 1, in: editPayload) ?? 0),
            object: try optionalFirstLengthDelimited(field: 2, in: editPayload).map(decodeImeObject)
        )
    }
    return RemoteImeBatchEditObservation(imeCounter: imeCounter, fieldCounter: fieldCounter, edits: edits)
}

private func decodeImeObject(_ payload: Data) throws -> RemoteImeObjectObservation {
    RemoteImeObjectObservation(
        value: try optionalFirstString(field: 3, in: payload) ?? "",
        selectionStart: Int(try optionalFirstVarint(field: 1, in: payload) ?? 0),
        selectionEnd: Int(try optionalFirstVarint(field: 2, in: payload) ?? 0)
    )
}
```

- [ ] Add the generic low-level helpers needed by those decoders, using the existing proto field reader instead of string slicing:

```swift
private func optionalFirstVarint(field target: Int, in payload: Data) throws -> UInt64? {
    var reader = ProtobufFieldReader(data: payload)
    while let field = try reader.nextField() {
        if field.number == target, field.wireType == .varint {
            return field.varint
        }
    }
    return nil
}

private func optionalFirstString(field target: Int, in payload: Data) throws -> String? {
    guard let bytes = try optionalFirstLengthDelimited(field: target, in: payload) else {
        return nil
    }
    return String(data: bytes, encoding: .utf8)
}

private func optionalFirstLengthDelimited(field target: Int, in payload: Data) throws -> Data? {
    var reader = ProtobufFieldReader(data: payload)
    while let field = try reader.nextField() {
        if field.number == target, field.wireType == .lengthDelimited {
            return field.bytes
        }
    }
    return nil
}

private func repeatedLengthDelimited(field target: Int, in payload: Data) throws -> [Data] {
    var result: [Data] = []
    var reader = ProtobufFieldReader(data: payload)
    while let field = try reader.nextField() {
        if field.number == target, field.wireType == .lengthDelimited {
            result.append(field.bytes)
        }
    }
    return result
}
```

These helpers must live next to the existing `firstVarint(field:in:)` helper and must reuse `ProtobufFieldReader`.

- [ ] Update existing tests that pattern-match `.textFieldStatus` for batch-edit frames to expect `.imeBatchEdit` and inspect `derivedTextFieldStatus`.

- [ ] Run:

```sh
swift test --filter RemoteMessageCodecTests
```

Expected result with a full Swift Testing toolchain:

```text
PASS RemoteMessageCodecTests
```

If local Swift Testing is unavailable, continue and use `make core-check` after Task 5.

---

## Task 3: Add RemoteSession Protocol-State Tests

- [ ] Open [RemoteSessionTests.swift](/Users/nyetwork/Developer/pult/Tests/PultCoreTests/RemoteSessionTests.swift).

- [ ] Add this test for negotiation and `remote_start` state:

```swift
@MainActor
@Test("Session stores attempt-scoped protocol observations")
func sessionStoresProtocolObservations() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    let device = DeviceRecord(name: "TV", host: "192.168.1.10")

    await transport.enqueueIncoming(framer.frame(remoteConfigureFrame(code: 64)))
    await transport.enqueueIncoming(framer.frame(remoteSetActiveFrame(code: 622)))
    await transport.enqueueIncoming(framer.frame(remoteStartFrame(started: true)))
    await session.connect(to: device)

    let sent = await transport.waitForSent(count: 2)
    for _ in 0..<100 where session.protocolState.remoteStart == nil {
        try? await Task.sleep(for: .milliseconds(5))
    }

    #expect(session.protocolState.negotiation.inboundConfigureCode?.value.rawValue == 64)
    #expect(session.protocolState.negotiation.outboundConfigureCode?.value.rawValue == 622)
    #expect(session.protocolState.negotiation.inboundSetActiveCode?.value.rawValue == 622)
    #expect(session.protocolState.negotiation.outboundSetActiveCode?.value.rawValue == 622)
    #expect(session.protocolState.remoteStart?.value == true)
    #expect(sent.count >= 2)
    #expect(sent[0] == framer.frame(codec.encodeConfigureResponse()))
    #expect(sent[1] == framer.frame(codec.encodeSetActiveResponse()))
}
```

- [ ] Add this test for IME app/edit observations while preserving existing text-field behavior:

```swift
@MainActor
@Test("Session stores IME app and batch observations")
func sessionStoresImeProtocolObservations() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    let device = DeviceRecord(name: "TV", host: "192.168.1.10")

    await transport.enqueueIncoming(framer.frame(remoteConfigureFrame(code: 64)))
    await transport.enqueueIncoming(framer.frame(remoteImeKeyInjectFrame(
        packageName: "com.netflix.ninja",
        appLabel: "Netflix",
        counter: 9,
        value: "dark",
        selectionStart: 4,
        selectionEnd: 4
    )))
    await transport.enqueueIncoming(framer.frame(remoteImeBatchEditFrame(
        imeCounter: 3,
        fieldCounter: 10,
        edits: [
            RemoteImeObjectFixture(value: "dark ma", selectionStart: 7, selectionEnd: 7),
            RemoteImeObjectFixture(value: "dark matter", selectionStart: 11, selectionEnd: 11)
        ]
    )))
    await session.connect(to: device)

    for _ in 0..<100 where session.textFieldStatus?.counter != 10 {
        try? await Task.sleep(for: .milliseconds(5))
    }

    #expect(session.protocolState.imeApp?.value.appPackage == "com.netflix.ninja")
    #expect(session.protocolState.imeApp?.value.label == "Netflix")
    #expect(session.protocolState.lastImeKeyInject?.value.textFieldStatus?.value == "dark")
    #expect(session.protocolState.lastImeBatchEdit?.value.imeCounter == 3)
    #expect(session.protocolState.lastImeBatchEdit?.value.fieldCounter == 10)
    #expect(session.protocolState.lastImeBatchEdit?.value.edits.last?.object?.value == "dark matter")
    #expect(session.textFieldStatus?.imeCounter == 3)
    #expect(session.textFieldStatus?.counter == 10)
    #expect(session.textFieldStatus?.value == "dark matter")
}
```

- [ ] Add this reset coverage:

```swift
@MainActor
@Test("Protocol observations reset on disconnect")
func protocolObservationsResetOnDisconnect() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    let device = DeviceRecord(name: "TV", host: "192.168.1.10")

    await transport.enqueueIncoming(framer.frame(remoteConfigureFrame(code: 64)))
    await transport.enqueueIncoming(framer.frame(remoteSetActiveFrame(code: 622)))
    await transport.enqueueIncoming(framer.frame(remoteStartFrame(started: true)))
    await session.connect(to: device)
    for _ in 0..<100 where session.protocolState.remoteStart == nil {
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(session.protocolState.remoteStart?.value == true)

    session.disconnect()

    #expect(session.protocolState == RemoteSessionProtocolState())
    #expect(session.textFieldStatus == nil)
    #expect(session.volumeStatus == nil)
}
```

- [ ] Add this same-device in-flight join coverage:

```swift
@MainActor
@Test("Joining same-device connection does not reset protocol observations")
func sameDeviceJoinDoesNotResetProtocolObservations() async {
    let transport = MockTransport()
    let session = RemoteSession(transport: transport)
    let device = DeviceRecord(name: "TV", host: "192.168.1.10")

    let first = Task { await session.connect(to: device) }
    let second = Task { await session.connect(to: device) }
    try? await Task.sleep(for: .milliseconds(20))
    await transport.enqueueIncoming(framer.frame(remoteConfigureFrame(code: 64)))
    await transport.enqueueIncoming(framer.frame(remoteStartFrame(started: true)))

    await first.value
    await second.value
    for _ in 0..<100 where session.protocolState.remoteStart == nil {
        try? await Task.sleep(for: .milliseconds(5))
    }

    #expect(session.protocolState.negotiation.inboundConfigureCode?.value.rawValue == 64)
    #expect(session.protocolState.remoteStart?.value == true)
    let dialCount = await transport.connectCount
    #expect(dialCount == 1)
}
```

- [ ] Reuse or add the IME frame helpers from `RemoteMessageCodecTests.swift`. Keep helper names identical where practical to reduce fixture drift.

- [ ] Run:

```sh
swift test --filter RemoteSessionTests
```

Expected result before implementation:

```text
FAIL: value of type RemoteSession has no member protocolState
```

If local Swift Testing is unavailable, continue and use `make core-check` after Task 5.

---

## Task 4: Implement Attempt-Scoped RemoteSession Protocol State

- [ ] Open [RemoteSession.swift](/Users/nyetwork/Developer/pult/Sources/PultCore/RemoteSession.swift).

- [ ] Add a public read-only property near the other session state:

```swift
public private(set) var protocolState = RemoteSessionProtocolState()
```

- [ ] Add a private negotiator property near the codec:

```swift
private let protocolNegotiator = RemoteProtocolNegotiator()
```

- [ ] Add a reset helper:

```swift
private func resetProtocolState() {
    protocolState = RemoteSessionProtocolState()
}
```

- [ ] Add an observation helper so every stored protocol fact carries the active session identity:

```swift
private func observe<Value: Equatable & Sendable>(
    _ value: Value,
    source: String,
    attempt: Int
) -> RemoteProtocolObservation<Value> {
    RemoteProtocolObservation(
        value: value,
        deviceID: device?.id,
        connectionAttempt: attempt,
        source: source
    )
}
```

- [ ] In the new-attempt path of `connect(to:)`, reset protocol state at the same time existing text/volume/timing state is cleared. Do not reset in the same-device in-flight join path.

- [ ] In `disconnect()`, call `resetProtocolState()` with the existing text/volume/IME reset.

- [ ] In the current-attempt failure path, call `resetProtocolState()` after confirming the failure belongs to the active attempt. Preserve stale-attempt protection.

- [ ] Update `handle(_:attempt:)` cases exactly by behavior:

```swift
case let .configure(request):
    if let code = request.code {
        protocolState.negotiation.inboundConfigureCode = observe(code, source: "remote_configure.code1", attempt: attempt)
    }
    if let deviceInfo = request.deviceInfo {
        protocolState.deviceInfo = observe(deviceInfo, source: "remote_configure.device_info", attempt: attempt)
    }
    try await send(codec.encodeConfigureResponse())
    guard attempt == connectAttempt else { return }
    protocolState.negotiation.outboundConfigureCode = observe(protocolNegotiator.clientResponseCode, source: "client.remote_configure.code1", attempt: attempt)
    connectionState = .connected

case let .setActive(request):
    if let code = request.active {
        protocolState.negotiation.inboundSetActiveCode = observe(code, source: "remote_set_active.active", attempt: attempt)
    }
    try await send(codec.encodeSetActiveResponse())
    guard attempt == connectAttempt else { return }
    protocolState.negotiation.outboundSetActiveCode = observe(protocolNegotiator.clientResponseCode, source: "client.remote_set_active.active", attempt: attempt)

case let .started(started):
    protocolState.remoteStart = observe(started, source: "remote_start.started", attempt: attempt)

case let .imeKeyInject(observation):
    if let appInfo = observation.appInfo {
        protocolState.imeApp = observe(appInfo, source: "remote_ime_key_inject.app_info", attempt: attempt)
    }
    protocolState.lastImeKeyInject = observe(observation, source: "remote_ime_key_inject", attempt: attempt)
    if let status = observation.textFieldStatus {
        nextImeCounter = max(nextImeCounter, status.imeCounter, 1)
        textFieldStatus = status
    }

case let .imeBatchEdit(observation):
    protocolState.lastImeBatchEdit = observe(observation, source: "remote_ime_batch_edit", attempt: attempt)
    if let status = observation.derivedTextFieldStatus {
        nextImeCounter = max(nextImeCounter, status.imeCounter, 1)
        textFieldStatus = status
    }
```

Keep existing `.textFieldStatus`, `.volume`, `.pingRequest`, `.voiceBegin`, `.error`, and `.other` behavior intact except for pattern-match syntax needed by the enum changes.

- [ ] After every `try await send(...)` in `handle(_:attempt:)`, keep or add `guard attempt == connectAttempt else { return }` before mutating state that represents the current session.

- [ ] Run:

```sh
swift test --filter RemoteSessionTests
```

Expected result with a full Swift Testing toolchain:

```text
PASS RemoteSessionTests
```

If local Swift Testing is unavailable, continue and use `make core-check` after Task 5.

---

## Task 5: Add PultCoreCheck Smoke Coverage

- [ ] Open [main.swift](/Users/nyetwork/Developer/pult/Sources/PultCoreCheck/main.swift).

- [ ] Add codec smoke checks near the existing remote codec checks:

```swift
let featureCode = RemoteProtocolCode(rawValue: 622)
expect(featureCode.labels == ["key", "ime", "voice", "unknown1", "powerCommandCapability", "volume", "appLink"], "feature code 622 decodes expected labels")
expect(featureCode.unknownBits == 0, "feature code 622 has no unknown bits")

switch try remoteCodec.decode(remoteConfigureFrame(code: 64)) {
case let .configure(request):
    expect(request.code?.rawValue == 64, "configure code is preserved")
    expect(request.code?.features == [.volume], "configure code 64 maps to volume")
default:
    fatalError("configure frame did not decode as configure request")
}

switch try remoteCodec.decode(remoteStartWithoutStartedFieldFrame()) {
case .other:
    break
default:
    fatalError("remote_start without started field must not invent false")
}
```

- [ ] Add session smoke checks near existing session checks:

```swift
let protocolTransport = MockRemoteTransport()
let protocolSession = RemoteSession(transport: protocolTransport)
await protocolTransport.enqueueIncoming(framer.frame(remoteConfigureFrame(code: 64)))
await protocolTransport.enqueueIncoming(framer.frame(remoteSetActiveFrame(code: 622)))
await protocolTransport.enqueueIncoming(framer.frame(remoteStartFrame(started: true)))
await protocolSession.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
let protocolSent = await protocolTransport.waitForSent(count: 2)
for _ in 0..<100 where protocolSession.protocolState.remoteStart == nil {
    try? await Task.sleep(for: .milliseconds(5))
}
expect(protocolSession.protocolState.negotiation.inboundConfigureCode?.value.rawValue == 64, "session stores inbound configure code")
expect(protocolSession.protocolState.negotiation.outboundConfigureCode?.value.rawValue == 622, "session stores outbound configure code")
expect(protocolSession.protocolState.remoteStart?.value == true, "session stores remote_start observation")
expect(protocolSent.count >= 2, "protocol session should send configure and set-active responses")
expect(protocolSent[0] == framer.frame(remoteCodec.encodeConfigureResponse()), "protocol session configure response bytes changed")
expect(protocolSent[1] == framer.frame(remoteCodec.encodeSetActiveResponse()), "protocol session set-active response bytes changed")
```

- [ ] Add `remoteConfigureFrame`, `remoteSetActiveFrame`, `remoteStartFrame`, and `remoteStartWithoutStartedFieldFrame` near the existing `remoteImeShowRequestFrame` helper, using the exact `ProtobufEncoder` helper bodies from Task 1.

- [ ] Run:

```sh
make core-check
```

Expected result:

```text
PultCoreCheck passed
```

The exact final success text may differ; the command must exit 0.

---

## Task 6: Surface Protocol Observations In Diagnostics

- [ ] Open [RemoteDiagnosticsFormatting.swift](/Users/nyetwork/Developer/pult/Sources/PultApp/RemoteDiagnosticsFormatting.swift).

- [ ] Add formatting extensions that do not imply validation:

```swift
extension RemoteProtocolCode {
    var diagnosticText: String {
        let labelText = labels.isEmpty ? "no known features" : labels.joined(separator: ", ")
        return "\(rawValue) (\(labelText))"
    }
}

extension RemoteDeviceInfo {
    var diagnosticText: String {
        [
            model.map { "model: \($0)" },
            vendor.map { "vendor: \($0)" },
            unknown1.map { "unknown1: \($0)" },
            unknown2.map { "unknown2: \($0)" },
            packageName.map { "package: \($0)" },
            appVersion.map { "version: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        .nonEmpty ?? "Not observed this session"
    }
}

extension RemoteSessionProtocolState {
    var diagnosticLines: [String] {
        [
            "Configure from TV: \(negotiation.inboundConfigureCode?.value.diagnosticText ?? "Not observed this session")",
            "Configure response: \(negotiation.outboundConfigureCode?.value.diagnosticText ?? "Not sent this session")",
            "Set-active from TV: \(negotiation.inboundSetActiveCode?.value.diagnosticText ?? "Not observed this session")",
            "Set-active response: \(negotiation.outboundSetActiveCode?.value.diagnosticText ?? "Not sent this session")",
            "Device info: \(deviceInfo?.value.diagnosticText ?? "Not observed this session")",
            "Remote start: \(remoteStart.map { $0.value ? "started=true" : "started=false" } ?? "Not observed this session")",
            "IME app observation: \(imeApp?.value.diagnosticText ?? "Not observed this session")",
            "Last IME batch: \(lastImeBatchEdit?.value.diagnosticText ?? "Not observed this session")"
        ]
    }
}

extension RemoteAppInfo {
    var diagnosticText: String {
        [
            appPackage.map { "package: \($0)" },
            label.map { "label: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        .nonEmpty ?? "Not observed this session"
    }
}

extension RemoteImeBatchEditObservation {
    var diagnosticText: String {
        guard let status = derivedTextFieldStatus else {
            return "imeCounter=\(imeCounter), fieldCounter=\(fieldCounter), edits=0"
        }
        return "imeCounter=\(imeCounter), fieldCounter=\(fieldCounter), edits=\(edits.count), textLength=\(status.value.count), selection=\(status.selectionStart)-\(status.selectionEnd)"
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
```

If a `String.nonEmpty` helper already exists, use the existing helper and do not duplicate it.

- [ ] Open [DiagnosticsAndValidationView.swift](/Users/nyetwork/Developer/pult/Sources/PultApp/DiagnosticsAndValidationView.swift).

- [ ] Add a Protocol Observations section below the existing Session section and above validation/report controls:

```swift
Section {
    DiagnosticValueRow(
        "Session TV",
        value: model.session.device?.name ?? "No active session",
        systemImage: "tv"
    )
    ForEach(model.session.protocolState.diagnosticLines, id: \.self) { line in
        DiagnosticValueRow(lineTitle(line), value: lineValue(line), systemImage: "waveform.path.ecg")
    }
} header: {
    Text("Protocol Observations")
} footer: {
    Text("Session-scoped protocol observations from the TV. These are diagnostics, not physical validation evidence.")
}
```

- [ ] Add small private helpers in the view file to split `Title: Value` lines:

```swift
private func lineTitle(_ line: String) -> String {
    guard let separator = line.firstIndex(of: ":") else { return line }
    return String(line[..<separator])
}

private func lineValue(_ line: String) -> String {
    guard let separator = line.firstIndex(of: ":") else { return "" }
    let valueStart = line.index(after: separator)
    return String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
}
```

- [ ] Convert `diagnosticsText` from a directly returned array expression to a local `var lines = [...]`, then append the protocol block before returning:

```swift
private var diagnosticsText: String {
    var lines = [
        "Pult Diagnostics",
        "TV: \(model.selectedDevice?.name ?? "None")",
        "Host: \(model.selectedDevice?.host ?? "None")",
        "Command Port: \(selectedDevicePort(\.commandPort))",
        "Pairing Port: \(selectedDevicePort(\.pairingPort))",
        "Paired: \(model.selectedDevice?.isPaired == true ? "Yes" : "No")",
        "Connection: \(model.session.connectionState.diagnosticText)",
        "Last Sent: \(format(model.session.lastSentAt))",
        "Last Received: \(format(model.session.lastReceivedAt))",
        "Last Error: \(model.session.lastError ?? "None")",
        "Volume: \(model.session.volumeStatus?.diagnosticText ?? "No TV update yet")",
        "Text Field: \(model.session.textFieldStatus.map(textFieldSummary) ?? "No focused field")",
        "Discovery: \(model.discovery.discoveryState.diagnosticText)",
        "Selected Source: \(selectedDevicePresenceText)",
        "Reachability: \(selectedDeviceReachabilityText)",
        "Saved TVs: \(model.discovery.devices.count)",
        "Nearby TVs: \(model.discovery.discoveredDevices.count)",
        "Validation State: \(validationClaimState.label)",
        "Last Successful Validation: \(latestSuccessfulValidation.map(validationSummary) ?? "None")",
        "Last Validation Report: \(latestValidationReport?.summary ?? "Not run for this TV")",
        "Checklist: \(completedIDs.count)/\(ValidationChecklistSection.totalItemCount)"
    ]

    lines.append("")
    lines.append("Protocol Observations (not validation evidence):")
    lines.append("- Session TV: \(model.session.device?.name ?? "No active session")")
    for line in model.session.protocolState.diagnosticLines {
        lines.append("- \(line)")
    }
    return lines.joined(separator: "\n")
}
```

- [ ] Run:

```sh
make build
```

Expected result:

```text
Build complete
```

The exact final wording may differ; the command must exit 0.

---

## Task 7: Update Documentation And Claim Boundaries

- [ ] Replace stale "not exposed" language with protocol-observation language in [Docs/LatencyMeasurementMethodology.md](/Users/nyetwork/Developer/pult/Docs/LatencyMeasurementMethodology.md):

Use this wording for the limitations section:

```markdown
Protocol observations include configure/set-active feature codes, volume status, IME text-field/app observations when the TV publishes them, and `remote_start.started` when present. Pult treats these as session-scoped diagnostics. They are not authoritative proof of TV power state, foreground app, or now-playing state.
```

- [ ] Update [Docs/ProductStrategy.md](/Users/nyetwork/Developer/pult/Docs/ProductStrategy.md):

Replace claims that the protocol exposes only commands plus volume with:

```markdown
The protocol exposes commands, volume, handshake feature codes, IME field/app observations, and `remote_start.started` when the TV publishes it. Product surfaces may show these as diagnostics, but not as validated foreground-app, power-state, or now-playing truth.
```

Replace "DON'T CHASE" items that say app name and power light do not exist with:

```markdown
Do not build product promises around app name, now-playing, or power-state truth. IME app observations and `remote_start.started` are useful diagnostics, not authoritative TV state.
```

- [ ] Update [appideas.md](/Users/nyetwork/Developer/pult/appideas.md):

Replace the parked-state paragraph with:

```markdown
Pult can now keep session-scoped protocol observations such as feature codes, volume, IME app/text-field observations, and `remote_start.started`. Keep them in diagnostics unless physical validation proves a specific TV behavior. Do not present IME app as global current app or `remote_start` as power state.
```

- [ ] Update [Docs/ProtocolSources.md](/Users/nyetwork/Developer/pult/Docs/ProtocolSources.md):

Replace the old codec wording with:

```markdown
Pult implements the Android TV Remote v2 codec in `Sources/PultCore/RemoteMessageCodec.swift`, using the vendored protocol references in this directory plus observed behavior from compatible clients. Configure and set-active responses currently preserve the observed client response code `622`; this is treated as an implementation constant until physical-device evidence proves a different negotiation is required.
```

Add a short feature-code reference:

```markdown
Known feature bits observed in compatible clients:

- `1`: ping
- `2`: key
- `4`: IME
- `8`: voice
- `16`: unknown/reserved
- `32`: power command capability
- `64`: volume
- `512`: app link
```

- [ ] Update [Docs/Observability.md](/Users/nyetwork/Developer/pult/Docs/Observability.md):

Add:

```markdown
Diagnostics include a "Protocol Observations (not validation evidence)" block. These rows are useful for debugging handshake, IME, and transport behavior, but they must not be used as proof that a TV's foreground app, power state, or now-playing state was validated.
```

- [ ] Update [Docs/PhysicalDeviceValidationChecklist.md](/Users/nyetwork/Developer/pult/Docs/PhysicalDeviceValidationChecklist.md):

Add a checklist note:

```markdown
- Protocol observations may be copied into a validation report as diagnostics. A validation area passes only when the human/device test records that behavior directly; feature codes, IME app observations, and `remote_start.started` alone do not pass any validation area.
```

- [ ] Update [Docs/superpowers/specs/2026-06-15-warm-live-session-design.md](/Users/nyetwork/Developer/pult/Docs/superpowers/specs/2026-06-15-warm-live-session-design.md) only if it repeats stale no-state claims. Preserve its latency scope.

- [ ] Update [README.md](/Users/nyetwork/Developer/pult/README.md) only if scope bullets still claim the protocol lacks IME app or remote-start observations.

- [ ] Run the stale-claim scan:

```sh
rg -n "current-app|current app|app name|power-state|power/standby|no .*power|no .*app|now-playing" README.md Docs appideas.md
```

Expected result: every remaining match is either historical context, an explicit non-goal, or language that says observations are diagnostics rather than validation evidence.

---

## Task 8: Full Verification

- [ ] Run the core smoke check:

```sh
make core-check
```

Expected result: exits 0.

- [ ] Run the app/core build:

```sh
make build
```

Expected result: exits 0.

- [ ] Run the default repository verification:

```sh
make verify
```

Expected result: exits 0.

- [ ] Run Swift Testing if the local toolchain supports it:

```sh
swift test
```

Expected result with a full Swift Testing toolchain: exits 0.

Known acceptable local failure: `no such module 'Testing'` from command-line-tool-only environments after `make build` and `make core-check` pass.

- [ ] Inspect the final diff:

```sh
git diff -- Sources/PultCore/RemoteMessageCodec.swift Sources/PultCore/RemoteSession.swift Sources/PultCoreCheck/main.swift Tests/PultCoreTests/RemoteMessageCodecTests.swift Tests/PultCoreTests/RemoteSessionTests.swift Sources/PultApp/RemoteDiagnosticsFormatting.swift Sources/PultApp/DiagnosticsAndValidationView.swift Docs README.md appideas.md
```

Check specifically:

- [ ] Configure and set-active response bytes are unchanged.
- [ ] `remote_start` missing `started` does not become `false`.
- [ ] IME app observations are labeled as IME observations, not current app.
- [ ] Feature bit `32` is named power command capability, not power state.
- [ ] Diagnostics block says "not validation evidence".
- [ ] Validation docs do not mark any new physical-TV area as passed.

- [ ] Commit the implementation:

```sh
git status --short
git add Sources/PultCore/RemoteMessageCodec.swift Sources/PultCore/RemoteSession.swift Sources/PultCoreCheck/main.swift Tests/PultCoreTests/RemoteMessageCodecTests.swift Tests/PultCoreTests/RemoteSessionTests.swift Sources/PultApp/RemoteDiagnosticsFormatting.swift Sources/PultApp/DiagnosticsAndValidationView.swift Docs/LatencyMeasurementMethodology.md Docs/ProductStrategy.md Docs/superpowers/specs/2026-06-15-warm-live-session-design.md Docs/ProtocolSources.md Docs/Observability.md Docs/PhysicalDeviceValidationChecklist.md README.md appideas.md
git commit -m "Add protocol observation state parity"
```

Do not stage unrelated files.

---

## Completion Criteria

- [ ] Protocol feature codes decode into known labels and unknown bit masks.
- [ ] Configure and set-active inbound requests preserve code/device payloads.
- [ ] Configure and set-active outbound responses still encode the observed `622` response.
- [ ] `remote_start.started` is retained only when present.
- [ ] IME app, key-inject, and batch-edit observations are retained without claiming global current app.
- [ ] RemoteSession resets protocol observations with connection lifecycle boundaries.
- [ ] Diagnostics show protocol observations in a clearly labeled non-validation section.
- [ ] Docs no longer say the protocol categorically lacks app/power-related observations.
- [ ] Docs still reject foreground-app, power-state, and now-playing product claims without physical validation.
- [ ] `make core-check`, `make build`, and `make verify` pass, or any failure is documented with the exact toolchain reason.
