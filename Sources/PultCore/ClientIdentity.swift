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

    /// Locked-screen intents must load the identity for mutual TLS, so iOS
    /// items use after-first-unlock protection. The macOS file keychain does
    /// not support data-protection classes; there accessibility stays nil.
    /// The migratory (non-ThisDeviceOnly) variant is deliberate so the identity
    /// survives encrypted backup/device migration and pairing carries over,
    /// matching the migratory default it replaces.
    public static var defaultAccessibility: CFString? {
        #if os(iOS)
        kSecAttrAccessibleAfterFirstUnlock
        #else
        nil
        #endif
    }

    private let accessibility: CFString?
    private var didUpgradeAccessibility = false

    public typealias KeychainUpdate = (_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus

    private let updateItem: KeychainUpdate

    public init(
        certificateLabel: String = "app.pult.client-identity",
        keyTag: String = "app.pult.client-key",
        accessibility: CFString? = KeychainClientIdentityStore.defaultAccessibility,
        updateItem: @escaping KeychainUpdate = { SecItemUpdate($0, $1) }
    ) {
        self.certificateLabel = certificateLabel
        self.keyTag = Data(keyTag.utf8)
        self.accessibility = accessibility
        self.updateItem = updateItem
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
        upgradeAccessibilityIfNeeded()
        if let identity = try copyIdentity() {
            return identity
        }
        try createIdentity()
        guard let identity = try copyIdentity() else {
            throw ClientIdentityError.identityUnavailable
        }
        return identity
    }

    /// Items created before the lock-screen feature carry when-unlocked
    /// protection; move them to the configured class so background intents
    /// can present the identity. Missing items (first run) are fine. A
    /// locked keychain (errSecInteractionNotAllowed) is not: leave the latch
    /// unset so the next access — typically with the phone unlocked — retries.
    func upgradeAccessibilityIfNeeded() {
        guard let accessibility, !didUpgradeAccessibility else { return }
        var allSettled = true
        for upgrade in Self.accessibilityUpgrades(
            keyTag: keyTag,
            certificateLabel: certificateLabel,
            accessibility: accessibility
        ) {
            let status = updateItem(upgrade.query as CFDictionary, upgrade.update as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                allSettled = false
            }
        }
        didUpgradeAccessibility = allSettled
    }

    private func copyIdentity() throws -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: certificateLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let item else { return nil }
            guard CFGetTypeID(item) == SecIdentityGetTypeID() else {
                throw ClientIdentityError.identityUnavailable
            }
            return (item as! SecIdentity)
        case errSecItemNotFound:
            return nil
        default:
            // An identity may exist but be unreadable right now (locked
            // keychain). Creating a replacement would orphan the certificate
            // the TV trusts, so fail the connection attempt instead.
            throw ClientIdentityError.keychainFailure(status)
        }
    }

    private func createIdentity() throws {
        let keyAttributes = Self.privateKeyAttributes(keyTag: keyTag, accessibility: accessibility)
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

        var addQuery = Self.certificateBaseAttributes(label: certificateLabel, accessibility: accessibility)
        addQuery[kSecValueRef as String] = certificate
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ClientIdentityError.keychainFailure(status)
        }
    }

    static func privateKeyAttributes(keyTag: Data, accessibility: CFString?) -> [String: Any] {
        var privateAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: keyTag
        ]
        if let accessibility {
            privateAttrs[kSecAttrAccessible as String] = accessibility
        }
        return [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: privateAttrs
        ]
    }

    static func certificateBaseAttributes(label: String, accessibility: CFString?) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label
        ]
        if let accessibility {
            attributes[kSecAttrAccessible as String] = accessibility
        }
        return attributes
    }

    static func accessibilityUpgrades(
        keyTag: Data,
        certificateLabel: String,
        accessibility: CFString
    ) -> [(query: [String: Any], update: [String: Any])] {
        let update: [String: Any] = [kSecAttrAccessible as String: accessibility]
        return [
            (
                query: [
                    kSecClass as String: kSecClassKey,
                    kSecAttrApplicationTag as String: keyTag,
                    kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                    kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
                ],
                update: update
            ),
            (
                query: [
                    kSecClass as String: kSecClassCertificate,
                    kSecAttrLabel as String: certificateLabel
                ],
                update: update
            )
        ]
    }
}
