import Foundation
import Testing
@testable import PultCore

private let client = RSAPublicKeyParameters(modulus: Data([0x00, 0xC0, 0xFF, 0xEE]), exponent: Data([0x01, 0x00, 0x01]))
private let server = RSAPublicKeyParameters(modulus: Data([0xBE, 0xEF]), exponent: Data([0x01, 0x00, 0x01]))

// SHA-256(C0FFEE | 010001 | BEEF | 010001 | 2B3C), computed with an
// independent oracle (python3 hashlib).
private let expectedSecret = Data([
    0xD9, 0xCB, 0x32, 0x4D, 0xCF, 0xB6, 0x39, 0x6F,
    0x0B, 0xF6, 0xC3, 0x63, 0xE8, 0xA2, 0x10, 0xC4,
    0x34, 0x18, 0xA4, 0xFE, 0xC5, 0xC5, 0xE0, 0x13,
    0x29, 0x20, 0xB8, 0xAB, 0x73, 0x3F, 0xCD, 0x17
])

@Test
func stripsSignPaddingFromModulus() {
    #expect(client.modulus == Data([0xC0, 0xFF, 0xEE]))
    #expect(client.exponent == Data([0x01, 0x00, 0x01]))
}

@Test
func computesPairingSecretForValidCode() throws {
    let secret = try PairingSecretHasher.secret(client: client, server: server, code: PairingCode(rawValue: "D92B3C")!)
    #expect(secret == expectedSecret)
}

@Test
func rejectsCodeWithWrongCheckByte() {
    #expect(throws: PairingSecretError.checkByteMismatch) {
        _ = try PairingSecretHasher.secret(client: client, server: server, code: PairingCode(rawValue: "AA2B3C")!)
    }
}
