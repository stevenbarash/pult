import Foundation

public enum RemoteCommand: Equatable, Sendable {
    case key(RemoteKey, KeyAction)
    case text(RemoteTextEdit)
    case appLink(URL)
}

public struct RemoteTextEdit: Equatable, Sendable {
    public var imeCounter: Int
    public var fieldCounter: Int
    public var insert: UInt32

    public init(imeCounter: Int, fieldCounter: Int, insert: UInt32) {
        self.imeCounter = imeCounter
        self.fieldCounter = fieldCounter
        self.insert = insert
    }
}

public struct RemoteTextFieldStatus: Equatable, Sendable {
    public var counter: Int
    public var value: String
    public var selectionStart: Int
    public var selectionEnd: Int
    public var unknown5: Int
    public var label: String

    public init(
        counter: Int,
        value: String = "",
        selectionStart: Int = 0,
        selectionEnd: Int = 0,
        unknown5: Int = 0,
        label: String = ""
    ) {
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
    case configure
    case setActive
    case pingRequest(UInt64)
    case error
    case started(Bool)
    case volume(level: UInt64, maximum: UInt64, muted: Bool)
    case textFieldStatus(RemoteTextFieldStatus)
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
        static let start = 40
        static let setVolumeLevel = 50
        static let appLinkLaunchRequest = 90
    }

    /// Active-client marker the reference remotes send in configure/set-active.
    private static let activeCode: UInt64 = 622

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
            var editInfo = ProtobufEncoder()
            editInfo.appendVarint(field: 2, UInt64(edit.insert))

            var batchEdit = ProtobufEncoder()
            batchEdit.appendVarint(field: 1, UInt64(edit.imeCounter))
            batchEdit.appendVarint(field: 2, UInt64(edit.fieldCounter))
            batchEdit.appendMessage(field: 3, editInfo.data)
            return message(field: FieldNumber.imeBatchEdit, payload: batchEdit.data)
        }
    }

    public func decode(_ payload: Data) throws -> IncomingRemoteMessage {
        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            switch field.number {
            case FieldNumber.configure:
                return .configure
            case FieldNumber.setActive:
                return .setActive
            case FieldNumber.error:
                return .error
            case FieldNumber.pingRequest:
                return .pingRequest(try firstVarint(field: 1, in: field.bytes) ?? 0)
            case FieldNumber.start:
                return .started(try firstVarint(field: 1, in: field.bytes) == 1)
            case FieldNumber.setVolumeLevel:
                return .volume(
                    level: try firstVarint(field: 7, in: field.bytes) ?? 0,
                    maximum: try firstVarint(field: 6, in: field.bytes) ?? 0,
                    muted: try firstVarint(field: 8, in: field.bytes) == 1
                )
            case FieldNumber.imeKeyInject, FieldNumber.imeShowRequest:
                if let status = try textFieldStatus(fromContainer: field.bytes) {
                    return .textFieldStatus(status)
                }
                return .other
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
        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            if field.number == number, field.wireType == .varint {
                return field.varint
            }
        }
        return nil
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
            counter: counter,
            value: value,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            unknown5: unknown5,
            label: label
        )
    }
}
