import Foundation

public enum ProtobufWireType: UInt8, Equatable, Sendable {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

public enum ProtobufCodingError: Error, Equatable {
    case truncatedField
    case unsupportedWireType(UInt8)
    case malformedVarint
}

/// Minimal protobuf wire-format writer covering the field shapes used by the
/// Android TV Remote Service v2 pairing and remote messages.
public struct ProtobufEncoder: Sendable {
    public private(set) var data: Data

    public init() {
        data = Data()
    }

    public mutating func appendVarint(field: Int, _ value: UInt64) {
        appendTag(field: field, wireType: .varint)
        appendRawVarint(value)
    }

    public mutating func appendString(field: Int, _ value: String) {
        appendBytes(field: field, Data(value.utf8))
    }

    public mutating func appendBytes(field: Int, _ value: Data) {
        appendTag(field: field, wireType: .lengthDelimited)
        appendRawVarint(UInt64(value.count))
        data.append(value)
    }

    public mutating func appendMessage(field: Int, _ message: Data) {
        appendBytes(field: field, message)
    }

    private mutating func appendTag(field: Int, wireType: ProtobufWireType) {
        appendRawVarint(UInt64(field) << 3 | UInt64(wireType.rawValue))
    }

    private mutating func appendRawVarint(_ value: UInt64) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while value != 0
    }
}

public struct ProtobufField: Equatable, Sendable {
    public let number: Int
    public let wireType: ProtobufWireType
    public let varint: UInt64
    public let bytes: Data

    public init(number: Int, wireType: ProtobufWireType, varint: UInt64 = 0, bytes: Data = Data()) {
        self.number = number
        self.wireType = wireType
        self.varint = varint
        self.bytes = bytes
    }
}

/// Iterates the fields of one serialized protobuf message payload.
public struct ProtobufFieldReader: Sendable {
    private var remaining: Data

    public init(data: Data) {
        remaining = data
    }

    public mutating func nextField() throws -> ProtobufField? {
        guard !remaining.isEmpty else { return nil }

        let tag = try readVarint()
        let rawWireType = UInt8(tag & 0x7)
        guard let wireType = ProtobufWireType(rawValue: rawWireType) else {
            throw ProtobufCodingError.unsupportedWireType(rawWireType)
        }
        let number = Int(tag >> 3)

        switch wireType {
        case .varint:
            return ProtobufField(number: number, wireType: wireType, varint: try readVarint())
        case .lengthDelimited:
            let length = Int(try readVarint())
            guard remaining.count >= length else {
                throw ProtobufCodingError.truncatedField
            }
            let payload = remaining.prefix(length)
            remaining = remaining.dropFirst(length)
            return ProtobufField(number: number, wireType: wireType, bytes: Data(payload))
        case .fixed64, .fixed32:
            let width = wireType == .fixed64 ? 8 : 4
            guard remaining.count >= width else {
                throw ProtobufCodingError.truncatedField
            }
            var value: UInt64 = 0
            for (index, byte) in remaining.prefix(width).enumerated() {
                value |= UInt64(byte) << (8 * index)
            }
            remaining = remaining.dropFirst(width)
            return ProtobufField(number: number, wireType: wireType, varint: value)
        }
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while let byte = remaining.first {
            remaining = remaining.dropFirst()
            if shift >= 64 {
                throw ProtobufCodingError.malformedVarint
            }
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }

        throw ProtobufCodingError.malformedVarint
    }
}
