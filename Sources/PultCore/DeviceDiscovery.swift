import Foundation
import Observation

public enum PultAppGroup {
    public static let identifier = "group.app.pult"

    /// The shared suite when the App Group entitlement is present; standard
    /// defaults otherwise (SwiftPM checks, simulator without entitlements).
    public static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

public protocol DeviceStore {
    func loadDevices() -> [DeviceRecord]
    func saveDevices(_ devices: [DeviceRecord])
    func loadSelectedDeviceID() -> UUID?
    func saveSelectedDeviceID(_ id: UUID?)
}

public struct UserDefaultsDeviceStore: DeviceStore {
    private let key: String
    private let selectionKey: String
    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults

    public init(
        key: String = "pult.devices",
        selectionKey: String = "pult.selectedDevice",
        defaults: UserDefaults = PultAppGroup.sharedDefaults(),
        legacyDefaults: UserDefaults = .standard
    ) {
        self.key = key
        self.selectionKey = selectionKey
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
    }

    public func loadDevices() -> [DeviceRecord] {
        migrateLegacyDevicesIfNeeded()
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DeviceRecord].self, from: data)) ?? []
    }

    public func saveDevices(_ devices: [DeviceRecord]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: key)
    }

    public func loadSelectedDeviceID() -> UUID? {
        defaults.string(forKey: selectionKey).flatMap(UUID.init(uuidString:))
    }

    public func saveSelectedDeviceID(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: selectionKey)
        } else {
            defaults.removeObject(forKey: selectionKey)
        }
    }

    /// Devices saved before the App Group move live in standard defaults.
    /// Copy them into the shared suite the first time it is empty; a marker
    /// is unnecessary because a populated (or intentionally emptied) suite
    /// always has data for the key afterwards.
    private func migrateLegacyDevicesIfNeeded() {
        guard defaults !== legacyDefaults,
              defaults.data(forKey: key) == nil,
              let legacy = legacyDefaults.data(forKey: key) else { return }
        defaults.set(legacy, forKey: key)
        if defaults.string(forKey: selectionKey) == nil,
           let legacySelection = legacyDefaults.string(forKey: selectionKey) {
            defaults.set(legacySelection, forKey: selectionKey)
        }
    }
}

@MainActor
@Observable
public final class DeviceDiscovery {
    public private(set) var devices: [DeviceRecord]
    public private(set) var discoveryState: DiscoveryState = .idle

    public var selectedDeviceID: UUID? {
        didSet {
            guard oldValue != selectedDeviceID else { return }
            store.saveSelectedDeviceID(selectedDeviceID)
        }
    }

    private let store: DeviceStore

    public init(store: DeviceStore = UserDefaultsDeviceStore()) {
        self.store = store
        self.devices = store.loadDevices()
        self.selectedDeviceID = store.loadSelectedDeviceID()
    }

    @discardableResult
    public func addManualDevice(name: String, host: String) -> DeviceRecord? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }

        let record: DeviceRecord
        if let index = devices.firstIndex(where: { $0.host == trimmedHost }) {
            devices[index].name = trimmedName.isEmpty ? devices[index].name : trimmedName
            devices[index].lastSeen = .now
            record = devices[index]
        } else {
            record = DeviceRecord(name: trimmedName.isEmpty ? trimmedHost : trimmedName, host: trimmedHost)
            devices.append(record)
        }

        store.saveDevices(devices)
        return record
    }

    public func markPaired(_ device: DeviceRecord) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].isPaired = true
        devices[index].lastSeen = .now
        store.saveDevices(devices)
    }

    public func refresh() async {
        discoveryState = .manualOnly
    }
}

public enum DiscoveryState: Equatable, Sendable {
    case idle
    case scanning
    case manualOnly
    case failed(String)
}
