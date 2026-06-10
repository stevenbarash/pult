import Foundation

public enum RemoteCommand: Equatable, Sendable {
    case key(RemoteKey, KeyAction)
    case text(String)
    case appLink(URL)
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
        case .text:
            // v2 text entry needs the IME counter state pushed by the TV;
            // not implemented yet.
            throw RemoteMessageCodecError.unsupportedCommand
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
}
