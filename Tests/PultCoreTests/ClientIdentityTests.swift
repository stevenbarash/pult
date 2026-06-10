import Foundation
import Security
import Testing
@testable import PultCore

@Test
func privateKeyAttributesCarryAccessibilityWhenProvided() {
    let attributes = KeychainClientIdentityStore.privateKeyAttributes(
        keyTag: Data("tag".utf8),
        accessibility: kSecAttrAccessibleAfterFirstUnlock
    )
    let privateAttrs = attributes[kSecPrivateKeyAttrs as String] as? [String: Any]
    #expect(privateAttrs?[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
    #expect(privateAttrs?[kSecAttrIsPermanent as String] as? Bool == true)
    #expect(attributes[kSecAttrKeySizeInBits as String] as? Int == 2048)
}

@Test
func privateKeyAttributesOmitAccessibilityWhenNil() {
    let attributes = KeychainClientIdentityStore.privateKeyAttributes(
        keyTag: Data("tag".utf8),
        accessibility: nil
    )
    let privateAttrs = attributes[kSecPrivateKeyAttrs as String] as? [String: Any]
    #expect(privateAttrs?[kSecAttrAccessible as String] == nil)
}

@Test
func certificateBaseAttributesCarryLabelAndAccessibility() {
    let attributes = KeychainClientIdentityStore.certificateBaseAttributes(
        label: "label",
        accessibility: kSecAttrAccessibleAfterFirstUnlock
    )
    #expect(attributes[kSecAttrLabel as String] as? String == "label")
    #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
}

@Test
func accessibilityUpgradeQueriesTargetBothItems() {
    let upgrades = KeychainClientIdentityStore.accessibilityUpgrades(
        keyTag: Data("tag".utf8),
        certificateLabel: "label",
        accessibility: kSecAttrAccessibleAfterFirstUnlock
    )
    #expect(upgrades.count == 2)
    #expect(upgrades[0].query[kSecClass as String] as? String == kSecClassKey as String)
    #expect(upgrades[1].query[kSecClass as String] as? String == kSecClassCertificate as String)
    for upgrade in upgrades {
        #expect(upgrade.update[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
    }
}

#if os(macOS)
@Test
func defaultAccessibilityIsNilOnMacOS() {
    #expect(KeychainClientIdentityStore.defaultAccessibility == nil)
}
#endif

@Test
func upgradeRetriesAfterLockedKeychainFailure() {
    nonisolated(unsafe) var statuses: [OSStatus] = [errSecInteractionNotAllowed, errSecInteractionNotAllowed,
                                                    errSecSuccess, errSecItemNotFound]
    nonisolated(unsafe) var callCount = 0
    let store = KeychainClientIdentityStore(
        certificateLabel: "test.upgrade.retry",
        keyTag: "test.upgrade.retry.key",
        accessibility: kSecAttrAccessibleAfterFirstUnlock,
        updateItem: { _, _ in
            callCount += 1
            return statuses.removeFirst()
        }
    )

    store.upgradeAccessibilityIfNeeded()
    #expect(callCount == 2) // locked: both updates attempted, latch NOT set

    store.upgradeAccessibilityIfNeeded()
    #expect(callCount == 4) // retried after unlock: success + not-found settle it

    store.upgradeAccessibilityIfNeeded()
    #expect(callCount == 4) // latched: no further updates
}

@Test
func upgradeRunsOnceWhenItemsSettle() {
    nonisolated(unsafe) var callCount = 0
    let store = KeychainClientIdentityStore(
        certificateLabel: "test.upgrade.once",
        keyTag: "test.upgrade.once.key",
        accessibility: kSecAttrAccessibleAfterFirstUnlock,
        updateItem: { _, _ in
            callCount += 1
            return errSecSuccess
        }
    )

    store.upgradeAccessibilityIfNeeded()
    store.upgradeAccessibilityIfNeeded()
    #expect(callCount == 2)
}

@Test
func keyUpgradeQueryTargetsOnlyPrivateKeys() {
    let upgrades = KeychainClientIdentityStore.accessibilityUpgrades(
        keyTag: Data("tag".utf8),
        certificateLabel: "label",
        accessibility: kSecAttrAccessibleAfterFirstUnlock
    )
    #expect(upgrades[0].query[kSecAttrKeyClass as String] as? String == kSecAttrKeyClassPrivate as String)
}
