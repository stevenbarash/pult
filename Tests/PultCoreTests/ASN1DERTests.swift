import Foundation
import Security
import Testing
@testable import PultCore

@Test
func encodesObjectIdentifier() {
    #expect(
        DER.objectIdentifier([1, 2, 840, 113549, 1, 1, 11])
            == Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B])
    )
}

@Test
func encodesIntegersWithSignPadding() {
    #expect(DER.integer(Data([0xC0, 0xFF, 0xEE])) == Data([0x02, 0x04, 0x00, 0xC0, 0xFF, 0xEE]))
    #expect(DER.integer(Data([0x01, 0x00, 0x01])) == Data([0x02, 0x03, 0x01, 0x00, 0x01]))
    #expect(DER.integer(7) == Data([0x02, 0x01, 0x07]))
}

@Test
func encodesLongFormLengths() {
    let encoded = DER.encode(tag: 0x04, content: Data(repeating: 0x55, count: 200))
    #expect(encoded.prefix(3) == Data([0x04, 0x81, 0xC8]))
}

@Test
func parsesPKCS1PublicKey() throws {
    let fixture = Data([0x30, 0x0B, 0x02, 0x04, 0x00, 0xC0, 0xFF, 0xEE, 0x02, 0x03, 0x01, 0x00, 0x01])
    let parameters = try RSAPublicKeyParameters(pkcs1: fixture)
    #expect(parameters.modulus == Data([0xC0, 0xFF, 0xEE]))
    #expect(parameters.exponent == Data([0x01, 0x00, 0x01]))
}

@Test
func selfSignedCertificateRoundTripsThroughSecurityFramework() throws {
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits as String: 2048
    ]
    var error: Unmanaged<CFError>?
    let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
    let publicKey = try #require(SecKeyCopyPublicKey(privateKey))

    let certificateDER = try X509SelfSignedCertificate.makeDER(
        commonName: "Pult",
        publicKey: publicKey,
        privateKey: privateKey,
        serialNumber: 1,
        notBefore: Date(timeIntervalSince1970: 1_700_000_000),
        notAfter: Date(timeIntervalSince1970: 2_000_000_000)
    )

    let certificate = try #require(SecCertificateCreateWithData(nil, certificateDER as CFData))
    let certificateKey = try #require(SecCertificateCopyKey(certificate))
    let certificateKeyData = try #require(SecKeyCopyExternalRepresentation(certificateKey, nil) as Data?)
    let expectedKeyData = try #require(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
    #expect(certificateKeyData == expectedKeyData)

    let parameters = try RSAPublicKeyParameters(pkcs1: certificateKeyData)
    #expect(parameters.modulus.count == 256)
    #expect(parameters.exponent == Data([0x01, 0x00, 0x01]))
}
