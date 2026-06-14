import Foundation

public enum FramingError: Error, Equatable {
    case emptyInput
    case incompleteVarint
    case varintTooLong
    case incompleteFrame(expected: Int, actual: Int)
    case frameTooLarge(declared: UInt64)
}

public struct VarintFramer: Sendable {
    /// RemoteMessage frames are tiny (key events, IME edits, volume steps) and
    /// arrive in <=64KB transport chunks. This cap sits far above any legitimate
    /// frame so a corrupt length prefix can't over-allocate or crash.
    public static let maxFrameLength: Int = 4 * 1024 * 1024

    public init() {}

    public func frame(_ payload: Data) -> Data {
        var output = encodeVarint(UInt64(payload.count))
        output.append(payload)
        return output
    }

    public func nextFrame(from buffer: inout Data) throws -> Data? {
        guard !buffer.isEmpty else { return nil }

        let decoded = try decodeVarint(from: buffer)
        let headerLength = decoded.bytesRead
        guard let payloadLength = Int(exactly: decoded.value),
              payloadLength <= Self.maxFrameLength else {
            throw FramingError.frameTooLarge(declared: decoded.value)
        }
        let frameLength = headerLength + payloadLength

        guard buffer.count >= frameLength else {
            return nil
        }

        let payload = buffer.subdata(in: headerLength..<frameLength)
        buffer.removeSubrange(0..<frameLength)
        return payload
    }

    public func encodeVarint(_ value: UInt64) -> Data {
        var value = value
        var output = Data()

        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            output.append(byte)
        } while value != 0

        return output
    }

    public func decodeVarint(from data: Data) throws -> (value: UInt64, bytesRead: Int) {
        guard !data.isEmpty else { throw FramingError.emptyInput }

        var result: UInt64 = 0
        var shift: UInt64 = 0

        for (index, byte) in data.enumerated() {
            if index == 10 {
                throw FramingError.varintTooLong
            }

            result |= UInt64(byte & 0x7f) << shift

            if byte & 0x80 == 0 {
                return (result, index + 1)
            }

            shift += 7
        }

        throw FramingError.incompleteVarint
    }
}
