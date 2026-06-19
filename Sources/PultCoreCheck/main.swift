import Foundation
import PultCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

func remoteImeShowRequestFrame(
    counter: Int,
    value: String = "",
    selectionStart: Int = 0,
    selectionEnd: Int = 0,
    label: String = ""
) -> Data {
    var status = ProtobufEncoder()
    status.appendVarint(field: 1, UInt64(counter))
    status.appendString(field: 2, value)
    status.appendVarint(field: 3, UInt64(selectionStart))
    status.appendVarint(field: 4, UInt64(selectionEnd))
    status.appendVarint(field: 5, 0)
    status.appendString(field: 6, label)

    var showRequest = ProtobufEncoder()
    showRequest.appendMessage(field: 2, status.data)

    var message = ProtobufEncoder()
    message.appendMessage(field: 22, showRequest.data)
    return message.data
}

let framer = VarintFramer()
expect(framer.encodeVarint(0) == Data([0x00]), "zero varint failed")
expect(framer.encodeVarint(127) == Data([0x7f]), "127 varint failed")
expect(framer.encodeVarint(128) == Data([0x80, 0x01]), "128 varint failed")
expect(framer.encodeVarint(16_384) == Data([0x80, 0x80, 0x01]), "16384 varint failed")

var buffer = Data()
buffer.append(framer.frame(Data("first".utf8)))
buffer.append(framer.frame(Data("second".utf8)))
let firstFrame = try framer.nextFrame(from: &buffer)
let secondFrame = try framer.nextFrame(from: &buffer)
expect(firstFrame == Data("first".utf8), "first frame failed")
expect(secondFrame == Data("second".utf8), "second frame failed")
expect(buffer.isEmpty, "frame buffer not drained")

expect(PairingCode(rawValue: "a1b2c3")?.rawValue == "A1B2C3", "pairing code normalization failed")
expect(PairingCode(rawValue: "A1B2CZ") == nil, "pairing code invalid character accepted")
expect(PairingCode.sanitized(" a1b2c3z9 ") == "A1B2C3", "pairing code sanitize failed")
expect(PairingCode.sanitized("zz") == "", "pairing code sanitize kept invalid characters")
expect(PairingCode.length == 6, "pairing code length unexpected")

final class MemoryDeviceStore: DeviceStore {
    var records: [DeviceRecord] = []
    var selectedID: UUID?
    func loadDevices() -> [DeviceRecord] { records }
    func saveDevices(_ devices: [DeviceRecord]) { records = devices }
    func loadSelectedDeviceID() -> UUID? { selectedID }
    func saveSelectedDeviceID(_ id: UUID?) { selectedID = id }
}

struct StaticReachabilityProbe: DeviceReachabilityProbing {
    var result: DeviceReachability

    func probe(host: String, port: UInt16, timeout: Duration) async -> DeviceReachability {
        result
    }
}

final class CollectingAppTelemetryRecorder: AppTelemetryRecording, @unchecked Sendable {
    private(set) var events: [AppTelemetryEvent] = []

    func record(_ event: AppTelemetryEvent) {
        events.append(event)
    }
}

actor FailingConnectRemoteTransport: RemoteTransport {
    private(set) var connectCount = 0

    func connect(to host: String, port: UInt16) async throws {
        connectCount += 1
        throw RemoteTransportError.connectionFailed
    }

    func send(_ data: Data) async throws {}

    func receive() async throws -> Data {
        throw RemoteTransportError.disconnected
    }

    func close() async {}

    func peerRSAPublicKeyParameters() async throws -> RSAPublicKeyParameters? {
        nil
    }
}

let discovery = DeviceDiscovery(store: MemoryDeviceStore())
let addedDevice = discovery.addManualDevice(name: "  ", host: " 192.168.1.42 ")
expect(addedDevice?.name == "192.168.1.42", "whitespace device name should fall back to host")
expect(addedDevice?.host == "192.168.1.42", "device host should be trimmed")
expect(addedDevice?.source == .manual, "manual device source failed")
discovery.addManualDevice(name: "Living Room", host: "192.168.1.42")
let renamedDevice = discovery.addManualDevice(name: "   ", host: "192.168.1.42")
expect(renamedDevice?.name == "Living Room", "whitespace rename should keep the existing name")
expect(discovery.devices.count == 1, "duplicate host should update, not append")
expect(discovery.addManualDevice(name: "TV", host: "   ") == nil, "blank host should be rejected")
let discoveredDevice = DiscoveredDevice(
    name: "Bedroom TV",
    host: "bedroom-tv.local",
    commandPort: 6466,
    pairingPort: 6467,
    serviceName: "Bedroom TV",
    serviceType: "_androidtvremote2._tcp."
)
let savedDiscoveredDevice = discovery.addDiscoveredDevice(discoveredDevice)
expect(savedDiscoveredDevice?.name == "Bedroom TV", "discovered device name failed")
expect(savedDiscoveredDevice?.host == "bedroom-tv.local", "discovered device host failed")
expect(savedDiscoveredDevice?.commandPort == 6466, "discovered command port failed")
expect(savedDiscoveredDevice?.source == .bonjour, "discovered device source failed")
expect(discovery.devices.count == 2, "discovered device should append")
expect(discovery.presence(for: savedDiscoveredDevice!) == .saved, "saved Bonjour device presence failed")

let reachableDiscovery = DeviceDiscovery(
    store: MemoryDeviceStore(),
    reachabilityProbe: StaticReachabilityProbe(result: .reachable(Date(timeIntervalSince1970: 0)))
)
let reachableDevice = reachableDiscovery.addManualDevice(name: "Reachable TV", host: "10.0.0.5")!
let reachableResult = await reachableDiscovery.checkReachability(for: reachableDevice)
expect(reachableResult.isReachable, "reachability probe result failed")
expect(reachableDiscovery.reachability(for: reachableDevice).isReachable, "reachability state failed")

expect(RemoteKey.home.androidKeyCode == 3, "home key mapping failed")
expect(RemoteKey.back.androidKeyCode == 4, "back key mapping failed")
expect(RemoteKey.playPause.androidKeyCode == 85, "play/pause mapping failed")
expect(RemoteKey.voiceSearch.androidKeyCode == 231, "voice search mapping failed")
expect(RemoteKey.search.androidKeyCode == 84, "search mapping failed")
expect(RemoteKey.enter.androidKeyCode == 66, "enter key mapping failed")
expect(RemoteKey.delete.androidKeyCode == 67, "delete key mapping failed")
expect(RemoteKey.volumeUp.displayTitle == "Volume Up", "volume title failed")
expect(RemoteKey.volumeUp.systemImage == "speaker.plus", "volume system image failed")
expect(RemoteKey.playPause.searchAliases.contains("play pause"), "play/pause aliases failed")
expect(RemoteKey.voiceSearch.searchAliases.contains("google assistant"), "voice search aliases failed")
expect(RemoteKey.search.searchAliases.contains("text search"), "search aliases failed")
expect(RemoteCommandPlan.catalog.first?.action == .key(.up), "command catalog order failed")
expect(RemoteCommandPlan.catalog.contains { $0.action == .openKeyboard }, "keyboard plan missing")
expect(RemoteCommandPlan.catalog.contains { $0.action == .showFavoriteApps }, "favorite apps plan missing")
expect(RemoteCommandPlan.plan(for: "play pause")?.remoteKey == .playPause, "play/pause plan failed")
expect(RemoteCommandPlan.plan(for: "Play/Pause")?.remoteKey == .playPause, "play/pause punctuation plan failed")
expect(RemoteCommandPlan.plan(for: "volume up")?.remoteKey == .volumeUp, "volume up plan failed")
expect(RemoteCommandPlan.plan(for: "please turn it down")?.remoteKey == .volumeDown, "volume down phrase plan failed")
expect(RemoteCommandPlan.plan(for: "go home")?.remoteKey == .home, "home phrase plan failed")
expect(RemoteCommandPlan.plan(for: "voice search")?.remoteKey == .voiceSearch, "voice search phrase plan failed")
expect(RemoteCommandPlan.plan(for: "google assistant")?.remoteKey == .voiceSearch, "google assistant phrase plan failed")
expect(RemoteCommandPlan.plan(for: "text search")?.remoteKey == .search, "search phrase plan failed")
expect(RemoteCommandPlan.plan(for: "open keyboard")?.action == .openKeyboard, "keyboard phrase plan failed")
expect(RemoteCommandPlan.plan(for: "favorite apps")?.action == .showFavoriteApps, "favorite apps phrase plan failed")
expect(RemoteCommandPlan.plan(for: "summarize this show") == nil, "unsupported phrase should not plan")
expect(
    RemoteCommandPlan.suggestions(matching: "", limit: 2).map(\.action) == [.key(.up), .key(.down)],
    "empty command suggestions failed"
)
expect(
    RemoteCommandPlan.suggestions(matching: "vol", limit: 2).map(\.action) == [.key(.volumeUp), .key(.volumeDown)],
    "volume command suggestions failed"
)
expect(
    RemoteCommandPlan.suggestions(matching: "voice").first?.action == .key(.voiceSearch),
    "voice search command suggestions failed"
)
expect(
    RemoteCommandPlan.suggestions(matching: "search").first?.action == .key(.search),
    "search command suggestions failed"
)
expect(
    RemoteCommandPlan.suggestions(matching: "keyboard").first?.action == .openKeyboard,
    "keyboard command suggestions failed"
)
expect(
    RemoteCommandPlan.suggestions(matching: "favorite").first?.action == .showFavoriteApps,
    "favorite command suggestions failed"
)

let telemetryEvent = AppTelemetryEvent(
    category: .remoteSession,
    action: "connect",
    outcome: .succeeded,
    metadata: [
        "transport": .public("mtls"),
        "host": .private("192.168.1.10")
    ]
)
expect(
    telemetryEvent.logMetadataDescription == "transport=mtls",
    "telemetry log metadata should include only public fields"
)
expect(
    !telemetryEvent.logMetadataDescription.contains("192.168.1.10"),
    "telemetry log metadata should not expose private values"
)

let sessionTelemetry = CollectingAppTelemetryRecorder()
let telemetryTransport = MockRemoteTransport()
let telemetrySession = RemoteSession(
    transport: telemetryTransport,
    telemetryRecorder: sessionTelemetry
)
await telemetryTransport.enqueueIncoming(framer.frame(Data([0x0A, 0x02, 0x08, 0x01])))
await telemetrySession.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
expect(
    sessionTelemetry.events.contains {
        $0.category == .remoteSession
            && $0.action == "connect"
            && $0.outcome == .succeeded
            && !$0.logMetadataDescription.contains("192.168.1.10")
    },
    "remote session connect should emit privacy-safe telemetry"
)

var backoff = ReconnectionBackoff()
expect(backoff.nextDelay() == .milliseconds(400), "first backoff failed")
expect(backoff.nextDelay() == .milliseconds(800), "second backoff failed")
backoff.reset()
expect(backoff.nextDelay() == .milliseconds(400), "backoff reset failed")

var validationRun = ValidationRunState(startedAt: Date(timeIntervalSince1970: 100))
expect(validationRun.items.count == 11, "validation definition item count changed unexpectedly")
expect(validationRun.items.map(\.id).contains(ValidationRunStepID.favoriteApp), "favorite app validation step missing")
expect(
    validationRun.update(ValidationRunStepID.selectedTV, status: .passed, note: "Selected.", at: Date(timeIntervalSince1970: 101)),
    "validation update should find selected TV row"
)
validationRun.skipPending(reason: "Stopped early.", at: Date(timeIntervalSince1970: 102))
expect(validationRun.summary == "1 passed, 0 failed, 0 need review, 10 skipped", "validation summary failed")
let validationReport = validationRun.makeReport(for: reachableDevice, updatedAt: Date(timeIntervalSince1970: 103))
expect(validationReport.deviceID == reachableDevice.id, "validation report device ID failed")
expect(validationReport.deviceName == "Reachable TV", "validation report device name failed")
expect(!validationReport.isSuccessfulPhysicalValidation, "skipped validation should not count as physically validated")

var successfulValidationRun = ValidationRunState(startedAt: Date(timeIntervalSince1970: 110))
for item in successfulValidationRun.items {
    expect(
        successfulValidationRun.update(item.id, status: .passed, note: "Checked.", at: Date(timeIntervalSince1970: 111)),
        "successful validation update should find \(item.id)"
    )
}
let successfulValidationReport = successfulValidationRun.makeReport(
    for: reachableDevice,
    updatedAt: Date(timeIntervalSince1970: 112)
)
expect(successfulValidationReport.isSuccessfulPhysicalValidation, "complete validation should count as physically validated")
expect(successfulValidationReport.physicalDeviceValidation?.deviceName == "Reachable TV", "physical validation device name failed")
expect(
    successfulValidationReport.physicalDeviceValidation?.passedAreas.map(\.id).contains(ValidationRunStepID.dpad) == true,
    "physical validation passed areas missing d-pad"
)
var validatedDevice = reachableDevice
expect(!validatedDevice.isValidatedOnPhysicalDevice, "device should not be physically validated by default")
expect(
    validatedDevice.recordSuccessfulValidation(from: successfulValidationReport),
    "device should record successful physical validation"
)
expect(validatedDevice.validationClaimState.label == "Validated", "device validation claim state failed")
expect(
    validatedDevice.lastSuccessfulValidation?.validatedAt == Date(timeIntervalSince1970: 112),
    "device validation timestamp failed"
)
let validatedDeviceData = try JSONEncoder().encode(validatedDevice)
let decodedValidatedDevice = try JSONDecoder().decode(DeviceRecord.self, from: validatedDeviceData)
expect(decodedValidatedDevice.isValidatedOnPhysicalDevice, "device validation did not round-trip")
expect(
    decodedValidatedDevice.lastSuccessfulValidation?.passedAreas.map(\.id).contains(ValidationRunStepID.volume) == true,
    "device validation passed areas did not round-trip"
)
let legacyDeviceData = try JSONEncoder().encode(DeviceRecord(name: "Legacy TV", host: "10.0.0.8"))
let decodedLegacyDevice = try JSONDecoder().decode(DeviceRecord.self, from: legacyDeviceData)
expect(!decodedLegacyDevice.isValidatedOnPhysicalDevice, "legacy device should decode as unvalidated")
var validationDevices = [reachableDevice]
expect(
    DeviceRecord.recordSuccessfulValidation(from: successfulValidationReport, in: &validationDevices)?.host == "10.0.0.5",
    "device array validation recorder failed"
)
let validationDeviceStore = MemoryDeviceStore()
validationDeviceStore.saveDevices([reachableDevice])
expect(
    validationDeviceStore.saveSuccessfulValidation(from: successfulValidationReport)?.deviceID == reachableDevice.id,
    "device store validation recorder failed"
)
expect(
    validationDeviceStore.loadDevices().first?.lastSuccessfulValidation?.deviceName == "Reachable TV",
    "device store validation recorder did not persist"
)
expect(
    reachableDiscovery.recordSuccessfulValidation(from: successfulValidationReport)?.deviceID == reachableDevice.id,
    "discovery validation recorder failed"
)
expect(
    reachableDiscovery.devices.first?.lastSuccessfulValidation?.validatedAt == Date(timeIntervalSince1970: 112),
    "discovery validation recorder did not update saved device"
)
expect(ValidationChecklistSection.totalItemCount == 16, "validation checklist count failed")

let emptyValidationModel = RemoteControlModel(
    discovery: DeviceDiscovery(store: MemoryDeviceStore()),
    session: RemoteSession(transport: MockRemoteTransport())
)
var runnerValidationRun = ValidationRunState(startedAt: Date(timeIntervalSince1970: 200))
await RemoteValidationRunner.run(
    model: emptyValidationModel,
    options: RemoteValidationRunOptions(
        discoveryPresenceTimeout: .milliseconds(1),
        discoveryPollInterval: .milliseconds(1),
        favoriteAppAvailable: false
    ),
    update: { id, status, note in
        runnerValidationRun.update(id, status: status, note: note, at: Date(timeIntervalSince1970: 201))
    },
    skipPending: { reason in
        runnerValidationRun.skipPending(reason: reason, at: Date(timeIntervalSince1970: 201))
    }
)
expect(
    runnerValidationRun.items.first { $0.id == ValidationRunStepID.selectedTV }?.status == .failed,
    "validation runner should fail when no TV is selected"
)
expect(runnerValidationRun.summary == "0 passed, 1 failed, 0 need review, 10 skipped", "validation runner summary failed")

let layoutDefaults = UserDefaults(suiteName: "pult.corecheck.remote-activity-layout")!
layoutDefaults.removePersistentDomain(forName: "pult.corecheck.remote-activity-layout")
let layoutStore = RemoteActivityLayoutStore(defaults: layoutDefaults)
expect(layoutStore.load() == .hybrid, "remote activity layout should default to hybrid")
layoutDefaults.set("future-layout", forKey: RemoteActivityLayoutStore.key)
expect(layoutStore.load() == .hybrid, "invalid remote activity layout should fall back to hybrid")
layoutStore.save(.media)
expect(
    layoutDefaults.string(forKey: RemoteActivityLayoutStore.key) == RemoteActivityLayout.media.rawValue,
    "remote activity layout should persist raw value"
)
expect(layoutStore.load() == .media, "remote activity layout save failed")
expect(RemoteActivityLayout.hybrid.displayTitle == "Hybrid", "remote activity layout hybrid title failed")
expect(RemoteActivityLayout.media.displayTitle == "Media", "remote activity layout title failed")
expect(
    RemoteActivityLayout.hybrid.settingsDescription.contains("D-pad"),
    "remote activity layout hybrid settings copy failed"
)
expect(
    RemoteActivityLayout.media.settingsDescription.contains("Playback"),
    "remote activity layout media settings copy failed"
)

var protoEncoder = ProtobufEncoder()
protoEncoder.appendVarint(field: 1, 2)
protoEncoder.appendVarint(field: 2, 200)
expect(protoEncoder.data == Data([0x08, 0x02, 0x10, 0xC8, 0x01]), "protobuf varint fields failed")

var protoInner = ProtobufEncoder()
protoInner.appendString(field: 1, "svc")
expect(protoInner.data == Data([0x0A, 0x03, 0x73, 0x76, 0x63]), "protobuf string field failed")

var protoOuter = ProtobufEncoder()
protoOuter.appendMessage(field: 10, protoInner.data)
expect(protoOuter.data == Data([0x52, 0x05, 0x0A, 0x03, 0x73, 0x76, 0x63]), "protobuf message field failed")

var protoBytes = ProtobufEncoder()
protoBytes.appendBytes(field: 1, Data([0xDE, 0xAD]))
expect(protoBytes.data == Data([0x0A, 0x02, 0xDE, 0xAD]), "protobuf bytes field failed")

var protoReader = ProtobufFieldReader(data: protoEncoder.data + protoOuter.data)
let protoField1 = try protoReader.nextField()
expect(protoField1 == ProtobufField(number: 1, wireType: .varint, varint: 2), "protobuf reader varint field failed")
let protoField2 = try protoReader.nextField()
expect(protoField2 == ProtobufField(number: 2, wireType: .varint, varint: 200), "protobuf reader second varint failed")
let protoField3 = try protoReader.nextField()
expect(protoField3 == ProtobufField(number: 10, wireType: .lengthDelimited, bytes: protoInner.data), "protobuf reader message field failed")
let protoFieldEnd = try protoReader.nextField()
expect(protoFieldEnd == nil, "protobuf reader end failed")

let pairingRequestBytes = PairingMessageCoder.encodeRequest(serviceName: "svc", clientName: "cli")
expect(
    pairingRequestBytes == Data([
        0x08, 0x02, 0x10, 0xC8, 0x01, 0x52, 0x0A,
        0x0A, 0x03, 0x73, 0x76, 0x63, 0x12, 0x03, 0x63, 0x6C, 0x69
    ]),
    "pairing request encoding failed"
)
expect(
    PairingMessageCoder.encodeOption() == Data([
        0x08, 0x02, 0x10, 0xC8, 0x01, 0xA2, 0x01, 0x08,
        0x0A, 0x04, 0x08, 0x03, 0x10, 0x06, 0x18, 0x01
    ]),
    "pairing option encoding failed"
)
expect(
    PairingMessageCoder.encodeConfiguration() == Data([
        0x08, 0x02, 0x10, 0xC8, 0x01, 0xF2, 0x01, 0x08,
        0x0A, 0x04, 0x08, 0x03, 0x10, 0x06, 0x10, 0x01
    ]),
    "pairing configuration encoding failed"
)
expect(
    PairingMessageCoder.encodeSecret(Data([0xAB, 0xCD])) == Data([
        0x08, 0x02, 0x10, 0xC8, 0x01, 0xC2, 0x02, 0x04,
        0x0A, 0x02, 0xAB, 0xCD
    ]),
    "pairing secret encoding failed"
)

let pairingAck = try PairingMessageCoder.decode(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0x5A, 0x04, 0x0A, 0x02, 0x74, 0x76]))
expect(pairingAck == PairingMessage(status: .ok, kind: .requestAck(serverName: "tv")), "pairing request ack decoding failed")
let pairingConfigurationAck = try PairingMessageCoder.decode(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0xFA, 0x01, 0x00]))
expect(pairingConfigurationAck == PairingMessage(status: .ok, kind: .configurationAck), "pairing configuration ack decoding failed")
let pairingSecretAck = try PairingMessageCoder.decode(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0xCA, 0x02, 0x04, 0x0A, 0x02, 0xAB, 0xCD]))
expect(pairingSecretAck == PairingMessage(status: .ok, kind: .secretAck(Data([0xAB, 0xCD]))), "pairing secret ack decoding failed")
let pairingBadSecret = try PairingMessageCoder.decode(Data([0x08, 0x02, 0x10, 0x92, 0x03]))
expect(pairingBadSecret.status == .badSecret, "pairing bad secret status decoding failed")

let clientParams = RSAPublicKeyParameters(modulus: Data([0x00, 0xC0, 0xFF, 0xEE]), exponent: Data([0x01, 0x00, 0x01]))
expect(clientParams.modulus == Data([0xC0, 0xFF, 0xEE]), "modulus sign byte stripping failed")
let serverParams = RSAPublicKeyParameters(modulus: Data([0xBE, 0xEF]), exponent: Data([0x01, 0x00, 0x01]))
let pairingSecret = try PairingSecretHasher.secret(
    client: clientParams,
    server: serverParams,
    code: PairingCode(rawValue: "D92B3C")!
)
expect(
    pairingSecret == Data([
        0xD9, 0xCB, 0x32, 0x4D, 0xCF, 0xB6, 0x39, 0x6F,
        0x0B, 0xF6, 0xC3, 0x63, 0xE8, 0xA2, 0x10, 0xC4,
        0x34, 0x18, 0xA4, 0xFE, 0xC5, 0xC5, 0xE0, 0x13,
        0x29, 0x20, 0xB8, 0xAB, 0x73, 0x3F, 0xCD, 0x17
    ]),
    "pairing secret hash failed"
)
do {
    _ = try PairingSecretHasher.secret(client: clientParams, server: serverParams, code: PairingCode(rawValue: "AA2B3C")!)
    expect(false, "pairing secret accepted bad check byte")
} catch let error as PairingSecretError {
    expect(error == .checkByteMismatch, "pairing secret wrong error")
}

let remoteCodec = AndroidTVRemoteMessageCodec()
let keyInjectBytes = try remoteCodec.encode(.key(.home, .tap))
expect(keyInjectBytes == Data([0x52, 0x04, 0x08, 0x03, 0x10, 0x03]), "remote key inject encoding failed")
let longPressStartBytes = try remoteCodec.encode(.key(.select, .press))
expect(longPressStartBytes == Data([0x52, 0x04, 0x08, 0x17, 0x10, 0x01]), "remote long key start encoding failed")
let longPressEndBytes = try remoteCodec.encode(.key(.select, .release))
expect(longPressEndBytes == Data([0x52, 0x04, 0x08, 0x17, 0x10, 0x02]), "remote long key end encoding failed")
let appLinkBytes = try remoteCodec.encode(.appLink(URL(string: "https://x")!))
expect(appLinkBytes == Data([0xD2, 0x05, 0x0B, 0x0A, 0x09]) + Data("https://x".utf8), "remote app link encoding failed")
let textEditBytes = try remoteCodec.encode(.text(RemoteTextEdit(imeCounter: 1, fieldCounter: 7, insert: 65)))
expect(textEditBytes == Data([0xAA, 0x01, 0x08, 0x08, 0x01, 0x10, 0x07, 0x1A, 0x02, 0x10, 0x41]), "remote text edit encoding failed")
expect(remoteCodec.encodePingResponse(5) == Data([0x4A, 0x02, 0x08, 0x05]), "remote ping response encoding failed")
expect(remoteCodec.encodeSetActiveResponse() == Data([0x12, 0x03, 0x08, 0xEE, 0x04]), "remote set active encoding failed")
expect(
    remoteCodec.encodeConfigureResponse() == Data([
        0x0A, 0x25, 0x08, 0xEE, 0x04, 0x12, 0x20,
        0x0A, 0x04, 0x50, 0x75, 0x6C, 0x74,
        0x12, 0x04, 0x50, 0x75, 0x6C, 0x74,
        0x18, 0x01,
        0x22, 0x01, 0x31,
        0x2A, 0x08, 0x61, 0x70, 0x70, 0x2E, 0x70, 0x75, 0x6C, 0x74,
        0x32, 0x03, 0x31, 0x2E, 0x30
    ]),
    "remote configure encoding failed"
)

let decodedConfigure = try remoteCodec.decode(Data([0x0A, 0x02, 0x08, 0x01]))
expect(decodedConfigure == .configure, "remote configure decoding failed")
let decodedSetActive = try remoteCodec.decode(Data([0x12, 0x00]))
expect(decodedSetActive == .setActive, "remote set active decoding failed")
let decodedPing = try remoteCodec.decode(Data([0x42, 0x02, 0x08, 0x2A]))
expect(decodedPing == .pingRequest(42), "remote ping request decoding failed")
let decodedStart = try remoteCodec.decode(Data([0xC2, 0x02, 0x02, 0x08, 0x01]))
expect(decodedStart == .started(true), "remote start decoding failed")
let decodedVolume = try remoteCodec.decode(Data([0x92, 0x03, 0x06, 0x30, 0x64, 0x38, 0x19, 0x40, 0x01]))
expect(decodedVolume == .volume(level: 25, maximum: 100, muted: true), "remote volume decoding failed")
let decodedImeStatus = try remoteCodec.decode(remoteImeShowRequestFrame(counter: 9, value: "ab", selectionStart: 1, selectionEnd: 2, label: "Search"))
expect(
    decodedImeStatus == .textFieldStatus(
        RemoteTextFieldStatus(counter: 9, value: "ab", selectionStart: 1, selectionEnd: 2, label: "Search")
    ),
    "remote IME status decoding failed"
)

let sessionTransport = MockRemoteTransport()
let session = RemoteSession(transport: sessionTransport)
await sessionTransport.enqueueIncoming(framer.frame(Data([0x0A, 0x02, 0x08, 0x01])))
await session.connect(to: DeviceRecord(name: "TV", host: "192.168.1.10"))
let sessionEndpoint = await sessionTransport.endpoint
expect(sessionEndpoint?.host == "192.168.1.10", "session host failed")
expect(sessionEndpoint?.port == 6466, "session port failed")
expect(session.connectionState == .connected, "session did not reach connected after configure")
var sessionSent = await sessionTransport.waitForSent(count: 1)
expect(sessionSent.first == framer.frame(remoteCodec.encodeConfigureResponse()), "session configure response failed")

await sessionTransport.enqueueIncoming(framer.frame(Data([0x12, 0x00])))
sessionSent = await sessionTransport.waitForSent(count: 2)
expect(sessionSent.count >= 2 && sessionSent[1] == framer.frame(remoteCodec.encodeSetActiveResponse()), "session set active response failed")

await sessionTransport.enqueueIncoming(framer.frame(Data([0x42, 0x02, 0x08, 0x2A])))
sessionSent = await sessionTransport.waitForSent(count: 3)
expect(sessionSent.count >= 3 && sessionSent[2] == framer.frame(remoteCodec.encodePingResponse(42)), "session ping response failed")
expect(session.lastReceivedAt != nil, "session should record received protocol frames")
expect(session.lastSentAt != nil, "session should record sent protocol frames")

await sessionTransport.enqueueIncoming(framer.frame(Data([0x92, 0x03, 0x06, 0x30, 0x64, 0x38, 0x19, 0x40, 0x01])))
var volumeAttempts = 0
while session.volumeStatus == nil, volumeAttempts < 2000 {
    volumeAttempts += 1
    try? await Task.sleep(for: .milliseconds(1))
}
expect(session.volumeStatus == RemoteVolumeStatus(level: 25, maximum: 100, muted: true), "session volume status failed")
expect(session.volumeStatus?.normalizedLevel == 0.25, "session volume normalized level failed")

await session.press(.select)
sessionSent = await sessionTransport.waitForSent(count: 4)
expect(sessionSent.count >= 4 && sessionSent[3] == framer.frame(try remoteCodec.encode(.key(.select, .tap))), "session key press frame failed")

await session.sendKey(.select, action: .press)
await session.sendKey(.select, action: .release)
sessionSent = await sessionTransport.waitForSent(count: 6)
expect(
    sessionSent.count >= 6
        && sessionSent[4] == framer.frame(try remoteCodec.encode(.key(.select, .press)))
        && sessionSent[5] == framer.frame(try remoteCodec.encode(.key(.select, .release))),
    "session long key frames failed"
)

await sessionTransport.enqueueIncoming(framer.frame(remoteImeShowRequestFrame(counter: 5, value: "", label: "Search")))
var imeAttempts = 0
while session.textFieldStatus?.counter != 5, imeAttempts < 2000 {
    imeAttempts += 1
    try? await Task.sleep(for: .milliseconds(1))
}
expect(session.textFieldStatus?.label == "Search", "session did not track IME status")
let didSendText = await session.sendText("Hi")
expect(didSendText, "session text send failed")
sessionSent = await sessionTransport.waitForSent(count: 8)
let expectedTextH = framer.frame(try remoteCodec.encode(.text(RemoteTextEdit(imeCounter: 1, fieldCounter: 5, insert: 72))))
let expectedTextI = framer.frame(try remoteCodec.encode(.text(RemoteTextEdit(imeCounter: 2, fieldCounter: 5, insert: 105))))
expect(
    sessionSent.count >= 8
        && sessionSent[6] == expectedTextH
        && sessionSent[7] == expectedTextI,
    "session text edit frames failed"
)

// Overlapping connects to the same device must join one attempt.
let joinTransport = MockRemoteTransport()
let joinSession = RemoteSession(transport: joinTransport)
let joinDevice = DeviceRecord(name: "TV", host: "10.0.0.1")
let firstConnect = Task { await joinSession.connect(to: joinDevice) }
let secondConnect = Task { await joinSession.connect(to: joinDevice) }
try? await Task.sleep(for: .milliseconds(20))
await joinTransport.enqueueIncoming(framer.frame(Data([0x0A, 0x02, 0x08, 0x01])))
await firstConnect.value
await secondConnect.value
expect(joinSession.connectionState == .connected, "joined connect did not reach connected")
let joinDialCount = await joinTransport.connectCount
expect(joinDialCount == 1, "overlapping connects dialed the transport twice")

// Switching devices must abandon the stale handshake, not fail the new one.
let switchTransport = MockRemoteTransport()
let switchSession = RemoteSession(transport: switchTransport, configureTimeout: .milliseconds(80))
let staleConnect = Task { await switchSession.connect(to: DeviceRecord(name: "A", host: "10.0.0.1")) }
try? await Task.sleep(for: .milliseconds(20))
let switchDeviceB = DeviceRecord(name: "B", host: "10.0.0.2")
let freshConnect = Task { await switchSession.connect(to: switchDeviceB) }
try? await Task.sleep(for: .milliseconds(20))
await switchTransport.enqueueIncoming(framer.frame(Data([0x0A, 0x02, 0x08, 0x01])))
await freshConnect.value
await staleConnect.value
try? await Task.sleep(for: .milliseconds(150))
expect(switchSession.connectionState == .connected, "stale attempt overwrote the new connection")
expect(switchSession.device?.id == switchDeviceB.id, "session device should be the new target")

let foregroundRefreshStore = MemoryDeviceStore()
let foregroundRefreshDevice = DeviceRecord(name: "Refresh TV", host: "10.0.0.3", isPaired: true)
foregroundRefreshStore.saveDevices([foregroundRefreshDevice])
foregroundRefreshStore.saveSelectedDeviceID(foregroundRefreshDevice.id)
let foregroundRefreshTransport = MockRemoteTransport()
let foregroundRefreshModel = RemoteControlModel(
    discovery: DeviceDiscovery(store: foregroundRefreshStore),
    session: RemoteSession(transport: foregroundRefreshTransport, configureTimeout: .milliseconds(200))
)
await foregroundRefreshTransport.enqueueIncoming(framer.frame(Data([0x0A, 0x02, 0x08, 0x01])))
await foregroundRefreshModel.ensureConnected()
expect(foregroundRefreshModel.session.connectionState == .connected, "foreground refresh setup did not connect")
let foregroundRefresh = Task { await foregroundRefreshModel.ensureConnected(staleAfter: 0) }
try? await Task.sleep(for: .milliseconds(20))
await foregroundRefreshTransport.enqueueIncoming(framer.frame(Data([0x0A, 0x02, 0x08, 0x01])))
await foregroundRefresh.value
expect(foregroundRefreshModel.session.connectionState == .connected, "foreground refresh did not stay connected")
let foregroundRefreshDialCount = await foregroundRefreshTransport.connectCount
expect(foregroundRefreshDialCount == 2, "foreground refresh should redial an idle connected session")

let failedInitialConnectStore = MemoryDeviceStore()
let failedInitialConnectDevice = DeviceRecord(name: "Offline TV", host: "10.0.0.4", isPaired: true)
failedInitialConnectStore.saveDevices([failedInitialConnectDevice])
failedInitialConnectStore.saveSelectedDeviceID(failedInitialConnectDevice.id)
let failedInitialConnectTransport = FailingConnectRemoteTransport()
let failedInitialConnectModel = RemoteControlModel(
    discovery: DeviceDiscovery(store: failedInitialConnectStore),
    session: RemoteSession(transport: failedInitialConnectTransport, configureTimeout: .milliseconds(50))
)
let failedInitialConnectOutcome = await failedInitialConnectModel.performHeadlessCommand(.home)
if case let .failed(message) = failedInitialConnectOutcome {
    expect(message.contains("Offline TV"), "initial connect failure should report the TV name")
} else {
    expect(false, "initial connect failure should fail the command")
}
let failedInitialConnectDialCount = await failedInitialConnectTransport.connectCount
expect(failedInitialConnectDialCount == 1, "initial connect failure should not redial before a send")

let pairingTransport = MockRemoteTransport()
let pairingSession = PairingSession(transport: pairingTransport, serviceName: "svc", clientName: "cli")
await pairingTransport.enqueueIncoming(framer.frame(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0x5A, 0x04, 0x0A, 0x02, 0x74, 0x76])))
await pairingTransport.enqueueIncoming(framer.frame(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0xA2, 0x01, 0x00])))
await pairingTransport.enqueueIncoming(framer.frame(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0xFA, 0x01, 0x00])))
try await pairingSession.start(
    for: DeviceRecord(name: "TV", host: "192.168.1.10"),
    clientParameters: clientParams
)
let pairingEndpoint = await pairingTransport.endpoint
expect(pairingEndpoint?.port == 6467, "pairing port failed")
var pairingSent = await pairingTransport.sentPayloads()
expect(pairingSent.count == 3, "pairing handshake frame count failed")
expect(pairingSent[0] == framer.frame(PairingMessageCoder.encodeRequest(serviceName: "svc", clientName: "cli")), "pairing request frame failed")
expect(pairingSent[1] == framer.frame(PairingMessageCoder.encodeOption()), "pairing option frame failed")
expect(pairingSent[2] == framer.frame(PairingMessageCoder.encodeConfiguration()), "pairing configuration frame failed")

await pairingTransport.setPeerParameters(serverParams)
await pairingTransport.enqueueIncoming(framer.frame(Data([0x08, 0x02, 0x10, 0xC8, 0x01, 0xCA, 0x02, 0x02, 0x0A, 0x00])))
try await pairingSession.submit(code: PairingCode(rawValue: "D92B3C")!)
pairingSent = await pairingTransport.sentPayloads()
expect(pairingSent.count == 4, "pairing secret frame count failed")
expect(pairingSent[3] == framer.frame(PairingMessageCoder.encodeSecret(pairingSecret)), "pairing secret frame failed")

expect(
    DER.objectIdentifier([1, 2, 840, 113549, 1, 1, 11]) == Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]),
    "DER object identifier encoding failed"
)
expect(DER.integer(Data([0xC0, 0xFF, 0xEE])) == Data([0x02, 0x04, 0x00, 0xC0, 0xFF, 0xEE]), "DER signed-padding integer failed")
expect(DER.integer(Data([0x01, 0x00, 0x01])) == Data([0x02, 0x03, 0x01, 0x00, 0x01]), "DER integer failed")
expect(DER.integer(7) == Data([0x02, 0x01, 0x07]), "DER scalar integer failed")
expect(DER.null == Data([0x05, 0x00]), "DER null failed")
expect(DER.bitString(Data([0xAB])) == Data([0x03, 0x02, 0x00, 0xAB]), "DER bit string failed")
expect(DER.utf8String("Pult") == Data([0x0C, 0x04, 0x50, 0x75, 0x6C, 0x74]), "DER utf8 string failed")
expect(
    DER.sequence([DER.integer(7)]) == Data([0x30, 0x03, 0x02, 0x01, 0x07]),
    "DER sequence failed"
)
let derLong = DER.encode(tag: 0x04, content: Data(repeating: 0x55, count: 200))
expect(derLong.prefix(3) == Data([0x04, 0x81, 0xC8]), "DER long-form length failed")

let pkcs1Fixture = Data([0x30, 0x0B, 0x02, 0x04, 0x00, 0xC0, 0xFF, 0xEE, 0x02, 0x03, 0x01, 0x00, 0x01])
let parsedParams = try RSAPublicKeyParameters(pkcs1: pkcs1Fixture)
expect(parsedParams == clientParams, "PKCS#1 public key parsing failed")

let keyAttributes: [String: Any] = [
    kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
    kSecAttrKeySizeInBits as String: 2048,
    kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: false
    ]
]
var keyError: Unmanaged<CFError>?
if let checkPrivateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &keyError),
   let checkPublicKey = SecKeyCopyPublicKey(checkPrivateKey) {
    let certificateDER = try X509SelfSignedCertificate.makeDER(
        commonName: "Pult",
        publicKey: checkPublicKey,
        privateKey: checkPrivateKey,
        serialNumber: 1,
        notBefore: Date(timeIntervalSince1970: 1_700_000_000),
        notAfter: Date(timeIntervalSince1970: 2_000_000_000)
    )
    guard let parsedCertificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
        fatalError("generated certificate failed Security framework parsing")
    }
    guard let certificateKey = SecCertificateCopyKey(parsedCertificate),
          let certificateKeyData = SecKeyCopyExternalRepresentation(certificateKey, nil) as Data?,
          let expectedKeyData = SecKeyCopyExternalRepresentation(checkPublicKey, nil) as Data? else {
        fatalError("generated certificate public key extraction failed")
    }
    expect(certificateKeyData == expectedKeyData, "certificate public key mismatch")
    let certificateParams = try RSAPublicKeyParameters(pkcs1: certificateKeyData)
    expect(certificateParams.modulus.count == 256, "certificate modulus size unexpected")
    expect(certificateParams.exponent == Data([0x01, 0x00, 0x01]), "certificate exponent unexpected")
} else {
    let description = keyError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
    print("Skipping certificate fixture: RSA key generation unavailable (\(description))")
}

print("PultCoreCheck passed")
