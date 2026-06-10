import Foundation
import PultCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
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

let discovery = DeviceDiscovery(store: MemoryDeviceStore())
let addedDevice = discovery.addManualDevice(name: "  ", host: " 192.168.1.42 ")
expect(addedDevice?.name == "192.168.1.42", "whitespace device name should fall back to host")
expect(addedDevice?.host == "192.168.1.42", "device host should be trimmed")
discovery.addManualDevice(name: "Living Room", host: "192.168.1.42")
let renamedDevice = discovery.addManualDevice(name: "   ", host: "192.168.1.42")
expect(renamedDevice?.name == "Living Room", "whitespace rename should keep the existing name")
expect(discovery.devices.count == 1, "duplicate host should update, not append")
expect(discovery.addManualDevice(name: "TV", host: "   ") == nil, "blank host should be rejected")

expect(RemoteKey.home.androidKeyCode == 3, "home key mapping failed")
expect(RemoteKey.back.androidKeyCode == 4, "back key mapping failed")
expect(RemoteKey.playPause.androidKeyCode == 85, "play/pause mapping failed")

var backoff = ReconnectionBackoff()
expect(backoff.nextDelay() == .milliseconds(400), "first backoff failed")
expect(backoff.nextDelay() == .milliseconds(800), "second backoff failed")
backoff.reset()
expect(backoff.nextDelay() == .milliseconds(400), "backoff reset failed")

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
let appLinkBytes = try remoteCodec.encode(.appLink(URL(string: "https://x")!))
expect(appLinkBytes == Data([0xD2, 0x05, 0x0B, 0x0A, 0x09]) + Data("https://x".utf8), "remote app link encoding failed")
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
do {
    _ = try remoteCodec.encode(.text("hi"))
    expect(false, "remote codec accepted unsupported text command")
} catch let error as RemoteMessageCodecError {
    expect(error == .unsupportedCommand, "remote codec wrong text error")
}

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

await session.press(.select)
sessionSent = await sessionTransport.waitForSent(count: 4)
expect(sessionSent.count >= 4 && sessionSent[3] == framer.frame(try remoteCodec.encode(.key(.select, .tap))), "session key press frame failed")

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
    kSecAttrKeySizeInBits as String: 2048
]
var keyError: Unmanaged<CFError>?
guard let checkPrivateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &keyError),
      let checkPublicKey = SecKeyCopyPublicKey(checkPrivateKey) else {
    fatalError("test RSA key generation failed: \(String(describing: keyError))")
}
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

print("PultCoreCheck passed")
