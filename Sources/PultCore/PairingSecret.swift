import Foundation
import CryptoKit

/// Big-endian RSA public key magnitude values with sign padding stripped,
/// matching the byte layout the Android TV pairing secret hash expects.
public struct RSAPublicKeyParameters: Equatable, Sendable {
    public var modulus: Data
    public var exponent: Data

    public init(modulus: Data, exponent: Data) {
        self.modulus = Self.strippingSignPadding(modulus)
        self.exponent = Self.strippingSignPadding(exponent)
    }

    private static func strippingSignPadding(_ magnitude: Data) -> Data {
        var magnitude = magnitude
        while magnitude.first == 0x00 {
            magnitude = magnitude.dropFirst()
        }
        return Data(magnitude)
    }
}

public enum PairingSecretError: Error, Equatable {
    case checkByteMismatch
}

/// Computes the pairing secret for the 6-hex-digit code shown on the TV:
/// SHA-256(client modulus | client exponent | server modulus | server exponent | nonce),
/// where the code is check-byte (2 hex digits) + nonce (4 hex digits) and the
/// check byte must equal the first byte of the digest.
public enum PairingSecretHasher {
    public static func secret(
        client: RSAPublicKeyParameters,
        server: RSAPublicKeyParameters,
        code: PairingCode
    ) throws -> Data {
        let codeBytes = bytes(fromHex: code.rawValue)
        let checkByte = codeBytes[0]
        let nonce = codeBytes.dropFirst()

        var hasher = SHA256()
        hasher.update(data: client.modulus)
        hasher.update(data: client.exponent)
        hasher.update(data: server.modulus)
        hasher.update(data: server.exponent)
        hasher.update(data: Data(nonce))
        let digest = Data(hasher.finalize())

        guard digest.first == checkByte else {
            throw PairingSecretError.checkByteMismatch
        }
        return digest
    }

    private static func bytes(fromHex hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var iterator = hex.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            bytes.append(UInt8(String([high, low]), radix: 16) ?? 0)
        }
        return bytes
    }
}
