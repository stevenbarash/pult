import Foundation

/// Android TV Remote Service v2 pairing envelope (`pairing.PairingMessage`).
/// Field numbers follow Docs/Protocol/pairingmessage.proto.
public struct PairingMessage: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case ok
        case error
        case badConfiguration
        case badSecret
        case unrecognized(UInt64)

        init(rawValue: UInt64) {
            switch rawValue {
            case 200: self = .ok
            case 400: self = .error
            case 401: self = .badConfiguration
            case 402: self = .badSecret
            default: self = .unrecognized(rawValue)
            }
        }
    }

    public enum Kind: Equatable, Sendable {
        case request(serviceName: String, clientName: String)
        case requestAck(serverName: String)
        case option
        case configuration
        case configurationAck
        case secret(Data)
        case secretAck(Data)
        case unrecognized
    }

    public var status: Status
    public var kind: Kind

    public init(status: Status, kind: Kind) {
        self.status = status
        self.kind = kind
    }
}

public enum PairingMessageCodingError: Error, Equatable {
    case malformedMessage
}

public enum PairingMessageCoder {
    private enum FieldNumber {
        static let protocolVersion = 1
        static let status = 2
        static let request = 10
        static let requestAck = 11
        static let option = 20
        static let configuration = 30
        static let configurationAck = 31
        static let secret = 40
        static let secretAck = 41
    }

    private static let protocolVersion: UInt64 = 2
    private static let statusOK: UInt64 = 200
    private static let encodingTypeHexadecimal: UInt64 = 3
    private static let codeSymbolLength: UInt64 = 6
    private static let roleTypeInput: UInt64 = 1

    public static func encodeRequest(serviceName: String, clientName: String) -> Data {
        var request = ProtobufEncoder()
        request.appendString(field: 1, serviceName)
        request.appendString(field: 2, clientName)
        return envelope(field: FieldNumber.request, payload: request.data)
    }

    public static func encodeOption() -> Data {
        var encoding = ProtobufEncoder()
        encoding.appendVarint(field: 1, encodingTypeHexadecimal)
        encoding.appendVarint(field: 2, codeSymbolLength)

        var option = ProtobufEncoder()
        option.appendMessage(field: 1, encoding.data)
        option.appendVarint(field: 3, roleTypeInput)
        return envelope(field: FieldNumber.option, payload: option.data)
    }

    public static func encodeConfiguration() -> Data {
        var encoding = ProtobufEncoder()
        encoding.appendVarint(field: 1, encodingTypeHexadecimal)
        encoding.appendVarint(field: 2, codeSymbolLength)

        var configuration = ProtobufEncoder()
        configuration.appendMessage(field: 1, encoding.data)
        configuration.appendVarint(field: 2, roleTypeInput)
        return envelope(field: FieldNumber.configuration, payload: configuration.data)
    }

    public static func encodeSecret(_ secret: Data) -> Data {
        var secretMessage = ProtobufEncoder()
        secretMessage.appendBytes(field: 1, secret)
        return envelope(field: FieldNumber.secret, payload: secretMessage.data)
    }

    public static func decode(_ data: Data) throws -> PairingMessage {
        var reader = ProtobufFieldReader(data: data)
        var status = PairingMessage.Status.unrecognized(0)
        var kind = PairingMessage.Kind.unrecognized

        do {
            while let field = try reader.nextField() {
                switch field.number {
                case FieldNumber.status:
                    status = PairingMessage.Status(rawValue: field.varint)
                case FieldNumber.request:
                    kind = .request(
                        serviceName: try string(field: 1, in: field.bytes),
                        clientName: try string(field: 2, in: field.bytes)
                    )
                case FieldNumber.requestAck:
                    kind = .requestAck(serverName: try string(field: 1, in: field.bytes))
                case FieldNumber.option:
                    kind = .option
                case FieldNumber.configuration:
                    kind = .configuration
                case FieldNumber.configurationAck:
                    kind = .configurationAck
                case FieldNumber.secret:
                    kind = .secret(try bytes(field: 1, in: field.bytes))
                case FieldNumber.secretAck:
                    kind = .secretAck(try bytes(field: 1, in: field.bytes))
                default:
                    break
                }
            }
        } catch is ProtobufCodingError {
            throw PairingMessageCodingError.malformedMessage
        }

        return PairingMessage(status: status, kind: kind)
    }

    private static func envelope(field: Int, payload: Data) -> Data {
        var message = ProtobufEncoder()
        message.appendVarint(field: FieldNumber.protocolVersion, protocolVersion)
        message.appendVarint(field: FieldNumber.status, statusOK)
        message.appendMessage(field: field, payload)
        return message.data
    }

    private static func string(field number: Int, in payload: Data) throws -> String {
        String(decoding: try bytes(field: number, in: payload), as: UTF8.self)
    }

    private static func bytes(field number: Int, in payload: Data) throws -> Data {
        var reader = ProtobufFieldReader(data: payload)
        while let field = try reader.nextField() {
            if field.number == number, field.wireType == .lengthDelimited {
                return field.bytes
            }
        }
        return Data()
    }
}
