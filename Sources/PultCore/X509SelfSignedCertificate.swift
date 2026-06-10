import Foundation
import Security

public enum X509CertificateError: Error {
    case publicKeyExportFailed
    case signingFailed
}

/// Builds the minimal self-signed RSA certificate the Android TV pairing
/// protocol expects the client to present during the TLS handshake.
public enum X509SelfSignedCertificate {
    private static let sha256WithRSAEncryption: [UInt64] = [1, 2, 840, 113549, 1, 1, 11]
    private static let rsaEncryption: [UInt64] = [1, 2, 840, 113549, 1, 1, 1]
    private static let commonNameOID: [UInt64] = [2, 5, 4, 3]

    public static func makeDER(
        commonName: String,
        publicKey: SecKey,
        privateKey: SecKey,
        serialNumber: UInt64,
        notBefore: Date,
        notAfter: Date
    ) throws -> Data {
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw X509CertificateError.publicKeyExportFailed
        }

        let signatureAlgorithm = DER.sequence([
            DER.objectIdentifier(sha256WithRSAEncryption),
            DER.null
        ])
        let name = DER.sequence([
            DER.set([
                DER.sequence([
                    DER.objectIdentifier(commonNameOID),
                    DER.utf8String(commonName)
                ])
            ])
        ])
        let subjectPublicKeyInfo = DER.sequence([
            DER.sequence([
                DER.objectIdentifier(rsaEncryption),
                DER.null
            ]),
            DER.bitString(publicKeyData)
        ])
        let tbsCertificate = DER.sequence([
            DER.integer(serialNumber),
            signatureAlgorithm,
            name,
            DER.sequence([
                DER.utcTime(notBefore),
                DER.utcTime(notAfter)
            ]),
            name,
            subjectPublicKeyInfo
        ])

        var signingError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbsCertificate as CFData,
            &signingError
        ) as Data? else {
            throw X509CertificateError.signingFailed
        }

        return DER.sequence([
            tbsCertificate,
            signatureAlgorithm,
            DER.bitString(signature)
        ])
    }
}
