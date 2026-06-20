import Foundation

public enum RemoteCommand: Equatable, Sendable {
    case key(RemoteKey, KeyAction)
    case text(RemoteTextEdit)
    case appLink(URL)
    case voiceBegin(sessionID: Int)
    case voicePayload(sessionID: Int, samples: Data)
    case voiceEnd(sessionID: Int)
}

public struct RemoteTextEdit: Equatable, Sendable {
    public var imeCounter: Int
    public var fieldCounter: Int
    public var text: String

    public init(imeCounter: Int, fieldCounter: Int, text: String) {
        self.imeCounter = imeCounter
        self.fieldCounter = fieldCounter
        self.text = text
    }

    public init(imeCounter: Int, fieldCounter: Int, insert: UInt32) {
        let scalar = UnicodeScalar(insert).map(String.init) ?? ""
        self.init(imeCounter: imeCounter, fieldCounter: fieldCounter, text: scalar)
    }
}

public struct RemoteTextFieldStatus: Equatable, Sendable {
    public var imeCounter: Int
    public var counter: Int
    public var value: String
    public var selectionStart: Int
    public var selectionEnd: Int
    public var unknown5: Int
    public var label: String

    public init(
        imeCounter: Int = 1,
        counter: Int,
        value: String = "",
        selectionStart: Int = 0,
        selectionEnd: Int = 0,
        unknown5: Int = 0,
        label: String = ""
    ) {
        self.imeCounter = imeCounter
        self.counter = counter
        self.value = value
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
        self.unknown5 = unknown5
        self.label = label
    }
}

/// Messages the TV sends on the command channel that the client must react to
/// or surface. Cases the remote does not need are collapsed into `other`.
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

public protocol RemoteMessageCodec: Sendable {
    func encode(_ command: RemoteCommand) throws -> Data
    func decode(_ payload: Data) throws -> IncomingRemoteMessage
    func encodeConfigureResponse() -> Data
    func encodeSetActiveResponse() -> Data
    func encodePingResponse(_ value: UInt64) -> Data
}

public enum RemoteMessageCodecError: Error, Equatable {
    case unsupportedCommand
}

public struct RemoteClientInfo: Equatable, Sendable {
    public var model: String
    public var vendor: String
    public var packageName: String
    public var appVersion: String

    public init(
        model: String = "Pult",
        vendor: String = "Pult",
        packageName: String = "app.pult",
        appVersion: String = "1.0"
    ) {
        self.model = model
        self.vendor = vendor
        self.packageName = packageName
        self.appVersion = appVersion
    }
}

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

    public init(
        model: String? = nil,
        vendor: String? = nil,
        unknown1: Int? = nil,
        unknown2: String? = nil,
        packageName: String? = nil,
        appVersion: String? = nil
    ) {
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

    public init(code: RemoteProtocolCode? = nil, deviceInfo: RemoteDeviceInfo? = nil) {
        self.code = code
        self.deviceInfo = deviceInfo
    }
}

public struct RemoteSetActiveRequest: Equatable, Sendable {
    public var active: RemoteProtocolCode?

    public init(active: RemoteProtocolCode? = nil) {
        self.active = active
    }
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

    public init(
        counter: Int? = nil,
        unknownInt2: Int? = nil,
        unknownInt3: Int? = nil,
        unknownString4: String? = nil,
        unknownInt7: Int? = nil,
        unknownInt8: Int? = nil,
        label: String? = nil,
        appPackage: String? = nil,
        unknownInt13: Int? = nil
    ) {
        self.counter = counter
        self.unknownInt2 = unknownInt2
        self.unknownInt3 = unknownInt3
        self.unknownString4 = unknownString4
        self.unknownInt7 = unknownInt7
        self.unknownInt8 = unknownInt8
        self.label = label
        self.appPackage = appPackage
        self.unknownInt13 = unknownInt13
    }
}

public struct RemoteImeObjectObservation: Equatable, Sendable {
    public var value: String?
    public var selectionStart: Int?
    public var selectionEnd: Int?

    public init(value: String? = nil, selectionStart: Int? = nil, selectionEnd: Int? = nil) {
        self.value = value
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
    }
}

public struct RemoteEditInfoObservation: Equatable, Sendable {
    public var editType: Int?
    public var object: RemoteImeObjectObservation?

    public init(editType: Int? = nil, object: RemoteImeObjectObservation? = nil) {
        self.editType = editType
        self.object = object
    }
}

public struct RemoteImeKeyInjectObservation: Equatable, Sendable {
    public var appInfo: RemoteAppInfo?
    public var textFieldStatus: RemoteTextFieldStatus?

    public init(appInfo: RemoteAppInfo? = nil, textFieldStatus: RemoteTextFieldStatus? = nil) {
        self.appInfo = appInfo
        self.textFieldStatus = textFieldStatus
    }
}

public struct RemoteImeBatchEditObservation: Equatable, Sendable {
    public var imeCounter: Int?
    public var fieldCounter: Int?
    public var edits: [RemoteEditInfoObservation]

    public init(imeCounter: Int? = nil, fieldCounter: Int? = nil, edits: [RemoteEditInfoObservation] = []) {
        self.imeCounter = imeCounter
        self.fieldCounter = fieldCounter
        self.edits = edits
    }

    public var derivedTextFieldStatus: RemoteTextFieldStatus? {
        guard
            let imeCounter,
            let fieldCounter,
            let object = edits.compactMap(\.object).last,
            let value = object.value,
            let selectionStart = object.selectionStart,
            let selectionEnd = object.selectionEnd
        else {
            return nil
        }

        return RemoteTextFieldStatus(
            imeCounter: max(imeCounter, 1),
            counter: fieldCounter,
            value: value,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd
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
        deviceID: UUID? = nil,
        connectionAttempt: Int = 0,
        source: String = ""
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

    public init(
        inboundConfigureCode: RemoteProtocolObservation<RemoteProtocolCode>? = nil,
        outboundConfigureCode: RemoteProtocolObservation<RemoteProtocolCode>? = nil,
        inboundSetActiveCode: RemoteProtocolObservation<RemoteProtocolCode>? = nil,
        outboundSetActiveCode: RemoteProtocolObservation<RemoteProtocolCode>? = nil
    ) {
        self.inboundConfigureCode = inboundConfigureCode
        self.outboundConfigureCode = outboundConfigureCode
        self.inboundSetActiveCode = inboundSetActiveCode
        self.outboundSetActiveCode = outboundSetActiveCode
    }
}

public struct RemoteSessionProtocolState: Equatable, Sendable {
    public var negotiation: RemoteProtocolNegotiation
    public var deviceInfo: RemoteProtocolObservation<RemoteDeviceInfo>?
    public var remoteStart: RemoteProtocolObservation<Bool>?
    public var imeApp: RemoteProtocolObservation<RemoteAppInfo>?
    public var lastImeBatchEdit: RemoteProtocolObservation<RemoteImeBatchEditObservation>?
    public var lastImeKeyInject: RemoteProtocolObservation<RemoteImeKeyInjectObservation>?

    public init(
        negotiation: RemoteProtocolNegotiation = RemoteProtocolNegotiation(),
        deviceInfo: RemoteProtocolObservation<RemoteDeviceInfo>? = nil,
        remoteStart: RemoteProtocolObservation<Bool>? = nil,
        imeApp: RemoteProtocolObservation<RemoteAppInfo>? = nil,
        lastImeBatchEdit: RemoteProtocolObservation<RemoteImeBatchEditObservation>? = nil,
        lastImeKeyInject: RemoteProtocolObservation<RemoteImeKeyInjectObservation>? = nil
    ) {
        self.negotiation = negotiation
        self.deviceInfo = deviceInfo
        self.remoteStart = remoteStart
        self.imeApp = imeApp
        self.lastImeBatchEdit = lastImeBatchEdit
        self.lastImeKeyInject = lastImeKeyInject
    }
}

public struct RemoteProtocolNegotiator: Equatable, Sendable {
    public static let defaultClientResponseRawCode: UInt64 = 622

    public var clientResponseCode: RemoteProtocolCode

    public init(clientResponseCode: RemoteProtocolCode = RemoteProtocolCode(rawValue: Self.defaultClientResponseRawCode)) {
        self.clientResponseCode = clientResponseCode
    }
}

/// `remote.RemoteMessage` wire codec for Android TV Remote Service v2.
/// Field numbers follow Docs/Protocol/remotemessage.proto.
public struct AndroidTVRemoteMessageCodec: RemoteMessageCodec {
    public let clientInfo: RemoteClientInfo

    public init(clientInfo: RemoteClientInfo = RemoteClientInfo()) {
        self.clientInfo = clientInfo
    }

    private enum FieldNumber {
        static let configure = 1
        static let setActive = 2
        static let error = 3
        static let pingRequest = 8
        static let pingResponse = 9
        static let keyInject = 10
        static let imeKeyInject = 20
        static let imeBatchEdit = 21
        static let imeShowRequest = 22
        static let voiceBegin = 30
        static let voicePayload = 31
        static let voiceEnd = 32
        static let start = 40
        static let setVolumeLevel = 50
        static let appLinkLaunchRequest = 90
    }

    // Observed client response code used by AOSP-compatible v2 remotes for
    // configure and set-active responses. Keep the byte sequence stable until
    // physical-device evidence proves a different negotiation is required.
    private static let activeCode: UInt64 = RemoteProtocolNegotiator.defaultClientResponseRawCode

    public var clientResponseCode: RemoteProtocolCode {
        RemoteProtocolCode(rawValue: Self.activeCode)
    }

    public func encode(_ command: RemoteCommand) throws -> Data {
        switch command {
        case let .key(key, action):
            var inject = ProtobufEncoder()
            inject.appendVarint(field: 1, UInt64(key.androidKeyCode))
            inject.appendVarint(field: 2, UInt64(action.rawValue))
            return message(field: FieldNumber.keyInject, payload: inject.data)
        case let .appLink(url):
            var launch = ProtobufEncoder()
            launch.appendString(field: 1, url.absoluteString)
            return message(field: FieldNumber.appLinkLaunchRequest, payload: launch.data)
        case let .text(edit):
            var textObject = ProtobufEncoder()
            let insertionOffset = UInt64(max(edit.text.count - 1, 0))
            textObject.appendVarint(field: 1, insertionOffset)
            textObject.appendVarint(field: 2, insertionOffset)
            textObject.appendString(field: 3, edit.text)

            var editInfo = ProtobufEncoder()
            editInfo.appendVarint(field: 1, 1)
            editInfo.appendMessage(field: 2, textObject.data)

            var batchEdit = ProtobufEncoder()
            batchEdit.appendVarint(field: 1, UInt64(edit.imeCounter))
            batchEdit.appendVarint(field: 2, UInt64(edit.fieldCounter))
            batchEdit.appendMessage(field: 3, editInfo.data)
            return message(field: FieldNumber.imeBatchEdit, payload: batchEdit.data)
        case let .voiceBegin(sessionID):
            var begin = ProtobufEncoder()
            begin.appendVarint(field: 1, UInt64(sessionID))
            return message(field: FieldNumber.voiceBegin, payload: begin.data)
        case let .voicePayload(sessionID, samples):
            var payload = ProtobufEncoder()
            payload.appendVarint(field: 1, UInt64(sessionID))
            payload.appendBytes(field: 2, samples)
            return message(field: FieldNumber.voicePayload, payload: payload.data)
        case let .voiceEnd(sessionID):
            var end = ProtobufEncoder()
            end.appendVarint(field: 1, UInt64(sessionID))
            return message(field: FieldNumber.voiceEnd, payload: end.data)
        }
    }

    public func decode(_ payload: Data) throws -> IncomingRemoteMessage {
        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            switch field.number {
            case FieldNumber.configure:
                return .configure(try decodeConfigure(field.bytes))
            case FieldNumber.setActive:
                return .setActive(try decodeSetActive(field.bytes))
            case FieldNumber.error:
                return .error
            case FieldNumber.pingRequest:
                return .pingRequest(try firstVarint(field: 1, in: field.bytes) ?? 0)
            case FieldNumber.start:
                guard let started = try optionalFirstVarint(field: 1, in: field.bytes) else {
                    return .other
                }
                return .started(started == 1)
            case FieldNumber.setVolumeLevel:
                return .volume(
                    level: try firstVarint(field: 7, in: field.bytes) ?? 0,
                    maximum: try firstVarint(field: 6, in: field.bytes) ?? 0,
                    muted: try firstVarint(field: 8, in: field.bytes) == 1
                )
            case FieldNumber.imeKeyInject:
                return .imeKeyInject(try decodeImeKeyInject(field.bytes))
            case FieldNumber.imeShowRequest:
                if let status = try textFieldStatus(fromContainer: field.bytes) {
                    return .textFieldStatus(status)
                }
                return .other
            case FieldNumber.imeBatchEdit:
                return .imeBatchEdit(try decodeImeBatchEdit(field.bytes))
            case FieldNumber.voiceBegin:
                return .voiceBegin(sessionID: Int(try firstVarint(field: 1, in: field.bytes) ?? 0))
            default:
                continue
            }
        }
        return .other
    }

    public func encodeConfigureResponse() -> Data {
        var deviceInfo = ProtobufEncoder()
        deviceInfo.appendString(field: 1, clientInfo.model)
        deviceInfo.appendString(field: 2, clientInfo.vendor)
        deviceInfo.appendVarint(field: 3, 1)
        deviceInfo.appendString(field: 4, "1")
        deviceInfo.appendString(field: 5, clientInfo.packageName)
        deviceInfo.appendString(field: 6, clientInfo.appVersion)

        var configure = ProtobufEncoder()
        configure.appendVarint(field: 1, Self.activeCode)
        configure.appendMessage(field: 2, deviceInfo.data)
        return message(field: FieldNumber.configure, payload: configure.data)
    }

    public func encodeSetActiveResponse() -> Data {
        var setActive = ProtobufEncoder()
        setActive.appendVarint(field: 1, Self.activeCode)
        return message(field: FieldNumber.setActive, payload: setActive.data)
    }

    public func encodePingResponse(_ value: UInt64) -> Data {
        var response = ProtobufEncoder()
        response.appendVarint(field: 1, value)
        return message(field: FieldNumber.pingResponse, payload: response.data)
    }

    private func message(field: Int, payload: Data) -> Data {
        var encoder = ProtobufEncoder()
        encoder.appendMessage(field: field, payload)
        return encoder.data
    }

    private func firstVarint(field number: Int, in payload: Data) throws -> UInt64? {
        try optionalFirstVarint(field: number, in: payload)
    }

    private func decodeConfigure(_ payload: Data) throws -> RemoteConfigureRequest {
        let deviceInfoPayload = try optionalFirstLengthDelimited(field: 2, in: payload)
        return RemoteConfigureRequest(
            code: try optionalFirstVarint(field: 1, in: payload).map(RemoteProtocolCode.init(rawValue:)),
            deviceInfo: try decodeOptionalNested(deviceInfoPayload, using: decodeRemoteDeviceInfo)
        )
    }

    private func decodeRemoteDeviceInfo(_ payload: Data) throws -> RemoteDeviceInfo {
        RemoteDeviceInfo(
            model: try optionalFirstString(field: 1, in: payload),
            vendor: try optionalFirstString(field: 2, in: payload),
            unknown1: try optionalFirstVarint(field: 3, in: payload).map { Int($0) },
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
            appInfo: try decodeOptionalNested(appPayload, using: decodeRemoteAppInfo),
            textFieldStatus: try decodeOptionalNestedObservation(statusPayload, using: textFieldStatusObservation(from:))
        )
    }

    private func decodeRemoteAppInfo(_ payload: Data) throws -> RemoteAppInfo {
        RemoteAppInfo(
            counter: try optionalFirstVarint(field: 1, in: payload).map { Int($0) },
            unknownInt2: try optionalFirstVarint(field: 2, in: payload).map { Int($0) },
            unknownInt3: try optionalFirstVarint(field: 3, in: payload).map { Int($0) },
            unknownString4: try optionalFirstString(field: 4, in: payload),
            unknownInt7: try optionalFirstVarint(field: 7, in: payload).map { Int($0) },
            unknownInt8: try optionalFirstVarint(field: 8, in: payload).map { Int($0) },
            label: try optionalFirstString(field: 10, in: payload),
            appPackage: try optionalFirstString(field: 12, in: payload),
            unknownInt13: try optionalFirstVarint(field: 13, in: payload).map { Int($0) }
        )
    }

    private func decodeImeBatchEdit(_ payload: Data) throws -> RemoteImeBatchEditObservation {
        let imeCounter = try optionalFirstVarint(field: 1, in: payload).map { Int($0) }
        let fieldCounter = try optionalFirstVarint(field: 2, in: payload).map { Int($0) }
        let edits = try repeatedLengthDelimited(field: 3, in: payload).map { editPayload in
            let objectPayload = try optionalFirstLengthDelimited(field: 2, in: editPayload)
            return RemoteEditInfoObservation(
                editType: try optionalFirstVarint(field: 1, in: editPayload).map { Int($0) },
                object: try decodeOptionalNested(objectPayload, using: decodeImeObject)
            )
        }
        return RemoteImeBatchEditObservation(imeCounter: imeCounter, fieldCounter: fieldCounter, edits: edits)
    }

    private func decodeImeObject(_ payload: Data) throws -> RemoteImeObjectObservation {
        RemoteImeObjectObservation(
            value: try optionalFirstString(field: 3, in: payload),
            selectionStart: try optionalFirstVarint(field: 1, in: payload).map { Int($0) },
            selectionEnd: try optionalFirstVarint(field: 2, in: payload).map { Int($0) }
        )
    }

    private func decodeOptionalNested<Value>(
        _ payload: Data?,
        using decoder: (Data) throws -> Value
    ) throws -> Value? {
        guard let payload else { return nil }
        do {
            return try decoder(payload)
        } catch is ProtobufCodingError {
            return nil
        } catch {
            throw error
        }
    }

    private func decodeOptionalNestedObservation<Value>(
        _ payload: Data?,
        using decoder: (Data) throws -> Value?
    ) throws -> Value? {
        guard let payload else { return nil }
        do {
            return try decoder(payload)
        } catch is ProtobufCodingError {
            return nil
        } catch {
            throw error
        }
    }

    private func textFieldStatusObservation(from payload: Data) throws -> RemoteTextFieldStatus? {
        var counter: Int?
        var value: String?
        var selectionStart: Int?
        var selectionEnd: Int?
        var unknown5 = 0
        var label = ""

        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            switch field.number {
            case 1 where field.wireType == .varint:
                counter = Int(field.varint)
            case 2 where field.wireType == .lengthDelimited:
                value = String(decoding: field.bytes, as: UTF8.self)
            case 3 where field.wireType == .varint:
                selectionStart = Int(field.varint)
            case 4 where field.wireType == .varint:
                selectionEnd = Int(field.varint)
            case 5 where field.wireType == .varint:
                unknown5 = Int(field.varint)
            case 6 where field.wireType == .lengthDelimited:
                label = String(decoding: field.bytes, as: UTF8.self)
            default:
                continue
            }
        }

        guard
            let counter,
            let value,
            let selectionStart,
            let selectionEnd
        else {
            return nil
        }

        return RemoteTextFieldStatus(
            imeCounter: 1,
            counter: counter,
            value: value,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            unknown5: unknown5,
            label: label
        )
    }

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
        return String(decoding: bytes, as: UTF8.self)
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

    private func textFieldStatus(fromContainer payload: Data) throws -> RemoteTextFieldStatus? {
        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            if field.number == 2, field.wireType == .lengthDelimited {
                return try textFieldStatus(from: field.bytes)
            }
        }
        return nil
    }

    private func textFieldStatus(fromBatchEdit payload: Data) throws -> RemoteTextFieldStatus {
        var imeCounter = 1
        var fieldCounter = 0
        var value = ""
        var selectionStart = 0
        var selectionEnd = 0

        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            switch field.number {
            case 1 where field.wireType == .varint:
                imeCounter = Int(field.varint)
            case 2 where field.wireType == .varint:
                fieldCounter = Int(field.varint)
            case 3 where field.wireType == .lengthDelimited:
                if let object = try textObject(fromEditInfo: field.bytes) {
                    value = object.value
                    selectionStart = object.selectionStart
                    selectionEnd = object.selectionEnd
                }
            default:
                continue
            }
        }

        return RemoteTextFieldStatus(
            imeCounter: max(imeCounter, 1),
            counter: fieldCounter,
            value: value,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd
        )
    }

    private func textObject(fromEditInfo payload: Data) throws -> (selectionStart: Int, selectionEnd: Int, value: String)? {
        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            if field.number == 2, field.wireType == .lengthDelimited {
                return try textObject(from: field.bytes)
            }
        }
        return nil
    }

    private func textObject(from payload: Data) throws -> (selectionStart: Int, selectionEnd: Int, value: String) {
        var selectionStart = 0
        var selectionEnd = 0
        var value = ""

        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            switch field.number {
            case 1 where field.wireType == .varint:
                selectionStart = Int(field.varint)
            case 2 where field.wireType == .varint:
                selectionEnd = Int(field.varint)
            case 3 where field.wireType == .lengthDelimited:
                value = String(decoding: field.bytes, as: UTF8.self)
            default:
                continue
            }
        }

        return (selectionStart, selectionEnd, value)
    }

    private func textFieldStatus(from payload: Data) throws -> RemoteTextFieldStatus {
        var counter = 0
        var value = ""
        var selectionStart = 0
        var selectionEnd = 0
        var unknown5 = 0
        var label = ""

        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            switch field.number {
            case 1 where field.wireType == .varint:
                counter = Int(field.varint)
            case 2 where field.wireType == .lengthDelimited:
                value = String(decoding: field.bytes, as: UTF8.self)
            case 3 where field.wireType == .varint:
                selectionStart = Int(field.varint)
            case 4 where field.wireType == .varint:
                selectionEnd = Int(field.varint)
            case 5 where field.wireType == .varint:
                unknown5 = Int(field.varint)
            case 6 where field.wireType == .lengthDelimited:
                label = String(decoding: field.bytes, as: UTF8.self)
            default:
                continue
            }
        }

        return RemoteTextFieldStatus(
            imeCounter: 1,
            counter: counter,
            value: value,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            unknown5: unknown5,
            label: label
        )
    }
}
