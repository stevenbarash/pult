import Foundation
import Security

public enum ClientIdentityError: Error {
    case keyGenerationFailed(String)
    case certificateCreationFailed
    case keychainFailure(OSStatus)
    case identityUnavailable
}

public protocol ClientIdentityProviding: Sendable {
    func identity() throws -> SecIdentity
    func publicKeyParameters() throws -> RSAPublicKeyParameters
}

/// Creates and persists the app's RSA client identity (private key plus
/// self-signed certificate) in the keychain. The TV remembers this
/// certificate after pairing, so the same identity must be presented on every
/// later connection.
public final class KeychainClientIdentityStore: ClientIdentityProviding, @unchecked Sendable {
    public static let shared = KeychainClientIdentityStore()

    private let certificateLabel: String
    private let keyTag: Data
    private let lock = NSLock()

    public init(
        certificateLabel: String = "app.pult.client-identity",
        keyTag: String = "app.pult.client-key"
    ) {
        self.certificateLabel = certificateLabel
        self.keyTag = Data(keyTag.utf8)
    }

    public func identity() throws -> SecIdentity {
        lock.lock()
        defer { lock.unlock() }
        return try loadOrCreateIdentity()
    }

    public func publicKeyParameters() throws -> RSAPublicKeyParameters {
        lock.lock()
        defer { lock.unlock() }

        let identity = try loadOrCreateIdentity()
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate,
              let key = SecCertificateCopyKey(certificate),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            throw ClientIdentityError.identityUnavailable
        }
        return try RSAPublicKeyParameters(pkcs1: keyData)
    }

    private func loadOrCreateIdentity() throws -> SecIdentity {
        if let identity = copyIdentity() {
            return identity
        }
        try createIdentity()
        guard let identity = copyIdentity() else {
            throw ClientIdentityError.identityUnavailable
        }
        return identity
    }

    private func copyIdentity() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: certificateLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let item else { return nil }
        return (item as! SecIdentity)
    }

    private func createIdentity() throws {
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag
            ]
        ]
        var keyError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &keyError),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            let description = keyError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            throw ClientIdentityError.keyGenerationFailed(description)
        }

        let now = Date()
        let certificateDER = try X509SelfSignedCertificate.makeDER(
            commonName: "Pult",
            publicKey: publicKey,
            privateKey: privateKey,
            serialNumber: UInt64.random(in: 1...UInt64.max),
            notBefore: now.addingTimeInterval(-86_400),
            notAfter: now.addingTimeInterval(10 * 365 * 86_400)
        )
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw ClientIdentityError.certificateCreationFailed
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: certificateLabel
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ClientIdentityError.keychainFailure(status)
        }
    }
}
