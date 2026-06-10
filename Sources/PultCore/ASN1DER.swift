import Foundation

public enum ASN1ParsingError: Error, Equatable {
    case malformed
}

/// Minimal DER encoder for the X.509 structures the client identity needs.
public enum DER {
    public static func encode(tag: UInt8, content: Data) -> Data {
        var output = Data([tag])
        output.append(length(content.count))
        output.append(content)
        return output
    }

    public static func sequence(_ parts: [Data]) -> Data {
        encode(tag: 0x30, content: joined(parts))
    }

    public static func set(_ parts: [Data]) -> Data {
        encode(tag: 0x31, content: joined(parts))
    }

    /// Encodes a big-endian unsigned magnitude as an INTEGER, adding the
    /// leading sign byte when the high bit is set.
    public static func integer(_ magnitude: Data) -> Data {
        var content = magnitude
        while content.count > 1, content.first == 0x00, let second = content.dropFirst().first, second & 0x80 == 0 {
            content = content.dropFirst()
        }
        if content.isEmpty {
            content = Data([0x00])
        }
        if let first = content.first, first & 0x80 != 0 {
            content = Data([0x00]) + content
        }
        return encode(tag: 0x02, content: Data(content))
    }

    public static func integer(_ value: UInt64) -> Data {
        var bytes: [UInt8] = []
        var value = value
        repeat {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        } while value != 0
        return integer(Data(bytes))
    }

    public static func bitString(_ content: Data) -> Data {
        encode(tag: 0x03, content: Data([0x00]) + content)
    }

    public static func objectIdentifier(_ components: [UInt64]) -> Data {
        guard components.count >= 2 else { return encode(tag: 0x06, content: Data()) }
        var content = Data([UInt8(components[0] * 40 + components[1])])
        for component in components.dropFirst(2) {
            content.append(base128(component))
        }
        return encode(tag: 0x06, content: content)
    }

    public static var null: Data {
        Data([0x05, 0x00])
    }

    public static func utf8String(_ value: String) -> Data {
        encode(tag: 0x0C, content: Data(value.utf8))
    }

    public static func utcTime(_ date: Date) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let formatted = String(
            format: "%02d%02d%02d%02d%02d%02dZ",
            parts.year! % 100, parts.month!, parts.day!, parts.hour!, parts.minute!, parts.second!
        )
        return encode(tag: 0x17, content: Data(formatted.utf8))
    }

    private static func joined(_ parts: [Data]) -> Data {
        parts.reduce(into: Data()) { $0.append($1) }
    }

    private static func length(_ count: Int) -> Data {
        if count < 0x80 {
            return Data([UInt8(count)])
        }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }

    private static func base128(_ value: UInt64) -> Data {
        var groups: [UInt8] = [UInt8(value & 0x7F)]
        var value = value >> 7
        while value > 0 {
            groups.insert(UInt8(value & 0x7F) | 0x80, at: 0)
            value >>= 7
        }
        return Data(groups)
    }
}

/// Iterates sibling TLV elements of a DER-encoded payload.
public struct DERReader {
    private var remaining: Data

    public init(_ data: Data) {
        remaining = data
    }

    public mutating func next() throws -> (tag: UInt8, content: Data)? {
        guard let tag = remaining.first else { return nil }
        remaining = remaining.dropFirst()

        guard let lengthByte = remaining.first else { throw ASN1ParsingError.malformed }
        remaining = remaining.dropFirst()

        var length = Int(lengthByte)
        if lengthByte & 0x80 != 0 {
            let byteCount = Int(lengthByte & 0x7F)
            guard byteCount > 0, byteCount <= 8, remaining.count >= byteCount else {
                throw ASN1ParsingError.malformed
            }
            length = remaining.prefix(byteCount).reduce(0) { $0 << 8 | Int($1) }
            remaining = remaining.dropFirst(byteCount)
        }

        guard remaining.count >= length else { throw ASN1ParsingError.malformed }
        let content = Data(remaining.prefix(length))
        remaining = remaining.dropFirst(length)
        return (tag, content)
    }
}

public extension RSAPublicKeyParameters {
    /// Parses a PKCS#1 `RSAPublicKey` (SEQUENCE { modulus INTEGER, exponent
    /// INTEGER }) as produced by `SecKeyCopyExternalRepresentation` for RSA.
    init(pkcs1 der: Data) throws {
        var outer = DERReader(der)
        guard let sequence = try outer.next(), sequence.tag == 0x30 else {
            throw ASN1ParsingError.malformed
        }
        var inner = DERReader(sequence.content)
        guard let modulus = try inner.next(), modulus.tag == 0x02,
              let exponent = try inner.next(), exponent.tag == 0x02 else {
            throw ASN1ParsingError.malformed
        }
        self.init(modulus: modulus.content, exponent: exponent.content)
    }
}
