import Foundation
import Observation

@MainActor
@Observable
public final class DeviceDiscovery {
    public private(set) var devices: [DeviceRecord]
    public private(set) var discoveryState: DiscoveryState = .idle

    private let store: DeviceStore

    public init(store: DeviceStore = UserDefaultsDeviceStore()) {
        self.store = store
        self.devices = store.loadDevices()
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

public protocol DeviceStore {
    func loadDevices() -> [DeviceRecord]
    func saveDevices(_ devices: [DeviceRecord])
}

public struct UserDefaultsDeviceStore: DeviceStore {
    private let key: String
    private let defaults: UserDefaults

    public init(key: String = "pult.devices", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func loadDevices() -> [DeviceRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DeviceRecord].self, from: data)) ?? []
    }

    public func saveDevices(_ devices: [DeviceRecord]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: key)
    }
}
