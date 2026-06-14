import Foundation
import Darwin
import Network
import Observation

public enum PultAppGroup {
    public static let identifier = "group.app.pult"

    /// The "group.app.pult" suite. Without the App Group entitlement this is
    /// still a real, writable domain — just private to the current process's
    /// sandbox rather than shared with the widget extension. The fallback to
    /// .standard only covers degenerate cases where the suite cannot be
    /// created at all.
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

public enum DevicePresence: Equatable, Sendable {
    case nearby
    case saved
    case manual
}

public enum DeviceReachability: Equatable, Sendable {
    case unknown
    case checking
    case reachable(Date)
    case unreachable(String, Date)

    public var isReachable: Bool {
        if case .reachable = self {
            return true
        }
        return false
    }
}

public protocol DeviceReachabilityProbing: Sendable {
    func probe(host: String, port: UInt16, timeout: Duration) async -> DeviceReachability
}

public struct NetworkPortReachabilityProbe: DeviceReachabilityProbing {
    public init() {}

    public func probe(host: String, port: UInt16, timeout: Duration = .seconds(3)) async -> DeviceReachability {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return .unreachable("Invalid port \(port).", .now)
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "app.pult.device-reachability", qos: .userInitiated)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<DeviceReachability, Never>) in
                let gate = ReachabilityContinuationGate()

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.resume {
                            connection.cancel()
                            continuation.resume(returning: .reachable(.now))
                        }
                    case let .waiting(error), let .failed(error):
                        gate.resume {
                            connection.cancel()
                            continuation.resume(returning: .unreachable(Self.describe(error), .now))
                        }
                    default:
                        break
                    }
                }

                connection.start(queue: queue)

                Task {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    gate.resume {
                        connection.cancel()
                        continuation.resume(returning: .unreachable("Timed out.", .now))
                    }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case let .posix(code):
            return String(cString: strerror(code.rawValue))
        case .dns:
            return "DNS lookup failed."
        case .tls:
            return "TLS setup failed."
        case .wifiAware:
            return "Wi-Fi Aware connection failed."
        @unknown default:
            return "Network connection failed."
        }
    }
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
        migrateLegacyDevicesIfNeeded()
        return defaults.string(forKey: selectionKey).flatMap(UUID.init(uuidString:))
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
    public private(set) var discoveredDevices: [DiscoveredDevice] = []
    public private(set) var reachabilityByHost: [String: DeviceReachability] = [:]

    public var selectedDeviceID: UUID? {
        didSet {
            guard oldValue != selectedDeviceID else { return }
            store.saveSelectedDeviceID(selectedDeviceID)
        }
    }

    private let store: DeviceStore
    private let bonjourScanner: BonjourDeviceScanner
    private let reachabilityProbe: any DeviceReachabilityProbing
    private var scanTimeoutTask: Task<Void, Never>?
    private var reachabilityTasks: [String: Task<Void, Never>] = [:]

    public init(
        store: DeviceStore = UserDefaultsDeviceStore(),
        reachabilityProbe: any DeviceReachabilityProbing = NetworkPortReachabilityProbe()
    ) {
        self.store = store
        self.devices = store.loadDevices()
        self.selectedDeviceID = store.loadSelectedDeviceID()
        self.bonjourScanner = BonjourDeviceScanner()
        self.reachabilityProbe = reachabilityProbe
        self.bonjourScanner.onChange = { [weak self] devices in
            self?.applyDiscoveredDevices(devices)
        }
        self.bonjourScanner.onFailure = { [weak self] message in
            self?.discoveryState = .failed(message)
        }
    }

    @discardableResult
    public func addManualDevice(name: String, host: String) -> DeviceRecord? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }

        let record: DeviceRecord
        if let index = devices.firstIndex(where: { $0.host == trimmedHost }) {
            devices[index].name = trimmedName.isEmpty ? devices[index].name : trimmedName
            devices[index].source = .manual
            devices[index].lastSeen = .now
            record = devices[index]
        } else {
            record = DeviceRecord(
                name: trimmedName.isEmpty ? trimmedHost : trimmedName,
                host: trimmedHost,
                source: .manual
            )
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

    @discardableResult
    public func recordSuccessfulValidation(from report: ValidationReport) -> PhysicalDeviceValidationRecord? {
        guard let validation = DeviceRecord.recordSuccessfulValidation(from: report, in: &devices) else {
            return nil
        }
        store.saveDevices(devices)
        return validation
    }

    public func moveDevices(fromOffsets source: IndexSet, toOffset destination: Int) {
        let validOffsets = source.filter { devices.indices.contains($0) }.sorted()
        guard !validOffsets.isEmpty else { return }
        let moving = validOffsets.map { devices[$0] }
        for index in validOffsets.reversed() {
            devices.remove(at: index)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), devices.count)
        devices.insert(contentsOf: moving, at: insertionIndex)
        store.saveDevices(devices)
    }

    @discardableResult
    public func deleteDevices(atOffsets offsets: IndexSet) -> [DeviceRecord] {
        let removed = offsets.sorted(by: >).compactMap { index -> DeviceRecord? in
            guard devices.indices.contains(index) else { return nil }
            return devices.remove(at: index)
        }
        if let selectedDeviceID, !devices.contains(where: { $0.id == selectedDeviceID }) {
            self.selectedDeviceID = devices.first?.id
        }
        store.saveDevices(devices)
        return removed.reversed()
    }

    @discardableResult
    public func addDiscoveredDevice(_ discoveredDevice: DiscoveredDevice) -> DeviceRecord? {
        addDevice(
            name: discoveredDevice.name,
            host: discoveredDevice.host,
            commandPort: discoveredDevice.commandPort,
            pairingPort: discoveredDevice.pairingPort,
            source: .bonjour
        )
    }

    public func refresh() async {
        startScanning()
    }

    public func startScanning() {
        scanTimeoutTask?.cancel()
        discoveryState = .scanning
        bonjourScanner.start()
        scanTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            await MainActor.run {
                guard let self, self.discoveryState == .scanning, self.discoveredDevices.isEmpty else { return }
                self.discoveryState = .manualOnly
            }
        }
    }

    public func stopScanning() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        cancelReachabilityTasks()
        bonjourScanner.stop()
        if discoveryState == .scanning {
            discoveryState = discoveredDevices.isEmpty ? .manualOnly : .idle
        }
    }

    public func presence(for device: DeviceRecord) -> DevicePresence {
        if discoveredDevices.contains(where: { Self.matches($0, device) }) {
            return .nearby
        }
        return device.source == .manual ? .manual : .saved
    }

    public func reachability(for device: DeviceRecord) -> DeviceReachability {
        reachabilityByHost[Self.hostKey(device.host)] ?? .unknown
    }

    public func reachability(for device: DiscoveredDevice) -> DeviceReachability {
        reachabilityByHost[Self.hostKey(device.host)] ?? .unknown
    }

    @discardableResult
    public func checkReachability(for device: DeviceRecord) async -> DeviceReachability {
        await checkReachability(host: device.host, port: device.commandPort)
    }

    @discardableResult
    public func checkReachability(for device: DiscoveredDevice) async -> DeviceReachability {
        await checkReachability(host: device.host, port: device.commandPort)
    }

    private func addDevice(
        name: String,
        host: String,
        commandPort: UInt16,
        pairingPort: UInt16,
        source: DeviceRecordSource
    ) -> DeviceRecord? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }
        let displayName = trimmedName.isEmpty ? trimmedHost : trimmedName

        if let index = devices.firstIndex(where: { $0.host.caseInsensitiveCompare(trimmedHost) == .orderedSame }) {
            devices[index].name = displayName
            devices[index].host = trimmedHost
            devices[index].commandPort = commandPort
            devices[index].pairingPort = pairingPort
            devices[index].lastSeen = .now
            devices[index].source = source
            store.saveDevices(devices)
            return devices[index]
        }

        let record = DeviceRecord(
            name: displayName,
            host: trimmedHost,
            commandPort: commandPort,
            pairingPort: pairingPort,
            source: source
        )
        devices.append(record)
        store.saveDevices(devices)
        return record
    }

    private func applyDiscoveredDevices(_ devices: [DiscoveredDevice]) {
        discoveredDevices = devices
        updateSavedDevices(from: devices)
        scheduleReachabilityChecks(for: devices)
        if !devices.isEmpty, discoveryState == .manualOnly {
            discoveryState = .scanning
        }
    }

    private func updateSavedDevices(from discoveredDevices: [DiscoveredDevice]) {
        var changed = false
        for discoveredDevice in discoveredDevices {
            guard let index = devices.firstIndex(where: { Self.matches(discoveredDevice, $0) }) else { continue }

            if devices[index].source == .bonjour, devices[index].name != discoveredDevice.name {
                devices[index].name = discoveredDevice.name
                changed = true
            }
            if devices[index].host != discoveredDevice.host {
                devices[index].host = discoveredDevice.host
                changed = true
            }
            if devices[index].commandPort != discoveredDevice.commandPort {
                devices[index].commandPort = discoveredDevice.commandPort
                changed = true
            }
            if devices[index].pairingPort != discoveredDevice.pairingPort {
                devices[index].pairingPort = discoveredDevice.pairingPort
                changed = true
            }
            if devices[index].lastSeen != discoveredDevice.lastSeen {
                devices[index].lastSeen = discoveredDevice.lastSeen
                changed = true
            }
        }
        if changed {
            store.saveDevices(devices)
        }
    }

    private func scheduleReachabilityChecks(for devices: [DiscoveredDevice]) {
        let activeHosts = Set(devices.map { Self.hostKey($0.host) })
        let inactiveHosts = reachabilityTasks.keys.filter { !activeHosts.contains($0) }
        for host in inactiveHosts {
            reachabilityTasks[host]?.cancel()
            reachabilityTasks.removeValue(forKey: host)
        }

        for device in devices {
            probeReachability(host: device.host, port: device.commandPort)
        }
    }

    private func probeReachability(host: String, port: UInt16) {
        let key = Self.hostKey(host)
        guard reachabilityTasks[key] == nil else { return }
        reachabilityByHost[key] = .checking
        let probe = reachabilityProbe
        reachabilityTasks[key] = Task { [weak self] in
            let result = await probe.probe(host: host, port: port, timeout: .seconds(3))
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.reachabilityByHost[key] = result
                self.reachabilityTasks[key] = nil
            }
        }
    }

    private func checkReachability(host: String, port: UInt16) async -> DeviceReachability {
        let key = Self.hostKey(host)
        reachabilityTasks[key]?.cancel()
        reachabilityTasks[key] = nil
        reachabilityByHost[key] = .checking
        let result = await reachabilityProbe.probe(host: host, port: port, timeout: .seconds(3))
        guard !Task.isCancelled else { return .unknown }
        reachabilityByHost[key] = result
        return result
    }

    private func cancelReachabilityTasks() {
        for task in reachabilityTasks.values {
            task.cancel()
        }
        reachabilityTasks.removeAll()
    }

    private static func matches(_ discoveredDevice: DiscoveredDevice, _ record: DeviceRecord) -> Bool {
        discoveredDevice.host.caseInsensitiveCompare(record.host) == .orderedSame
    }

    private static func hostKey(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private final class ReachabilityContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        body()
    }
}

public enum DiscoveryState: Equatable, Sendable {
    case idle
    case scanning
    case manualOnly
    case failed(String)
}

public struct DiscoveredDevice: Hashable, Identifiable, Sendable {
    public var id: String {
        "\(host.lowercased())|\(commandPort)|\(pairingPort)"
    }

    public var name: String
    public var host: String
    public var commandPort: UInt16
    public var pairingPort: UInt16
    public var serviceName: String
    public var serviceType: String
    public var lastSeen: Date

    public init(
        name: String,
        host: String,
        commandPort: UInt16 = 6466,
        pairingPort: UInt16 = 6467,
        serviceName: String = "",
        serviceType: String = "",
        lastSeen: Date = .now
    ) {
        self.name = name
        self.host = host
        self.commandPort = commandPort
        self.pairingPort = pairingPort
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.lastSeen = lastSeen
    }
}

private final class BonjourDeviceScanner: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private static let serviceTypes = [
        "_androidtvremote2._tcp.",
        "_androidtvremote._tcp."
    ]

    var onChange: (@MainActor @Sendable ([DiscoveredDevice]) -> Void)?
    var onFailure: (@MainActor @Sendable (String) -> Void)?

    private var browsers: [NetServiceBrowser] = []
    private var servicesByID: [ObjectIdentifier: NetService] = [:]
    private var discoveredByID: [String: DiscoveredDevice] = [:]

    func start() {
        stop()
        for serviceType in Self.serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            #if os(iOS) || os(macOS)
            browser.includesPeerToPeer = true
            #endif
            browsers.append(browser)
            browser.searchForServices(ofType: serviceType, inDomain: "local.")
        }
    }

    func stop() {
        for browser in browsers {
            browser.stop()
            browser.delegate = nil
        }
        for service in servicesByID.values {
            service.stop()
            service.delegate = nil
        }
        browsers.removeAll()
        servicesByID.removeAll()
        discoveredByID.removeAll()
        publish()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let id = ObjectIdentifier(service)
        servicesByID[id] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let id = ObjectIdentifier(service)
        servicesByID[id]?.stop()
        servicesByID[id]?.delegate = nil
        servicesByID.removeValue(forKey: id)
        let removedIDs = discoveredByID.filter { $0.value.serviceName == service.name && $0.value.serviceType == service.type }.map(\.key)
        for id in removedIDs {
            discoveredByID.removeValue(forKey: id)
        }
        if !moreComing {
            publish()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        publishFailure("Could not scan the local network for TVs.")
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = Self.hostName(for: sender) else { return }
        let ports = Self.ports(for: sender)
        let discoveredDevice = DiscoveredDevice(
            name: sender.name,
            host: host,
            commandPort: ports.command,
            pairingPort: ports.pairing,
            serviceName: sender.name,
            serviceType: sender.type
        )
        discoveredByID[discoveredDevice.id] = discoveredDevice
        publish()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        servicesByID.removeValue(forKey: ObjectIdentifier(sender))
    }

    private func publish() {
        let devices = discoveredByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        Task { @MainActor [onChange] in
            onChange?(devices)
        }
    }

    private func publishFailure(_ message: String) {
        Task { @MainActor [onFailure] in
            onFailure?(message)
        }
    }

    private static func hostName(for service: NetService) -> String? {
        if let hostName = service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
           !hostName.isEmpty {
            return hostName
        }
        return numericHost(from: service.addresses)
    }

    private static func ports(for service: NetService) -> (command: UInt16, pairing: UInt16) {
        guard let resolvedPort = UInt16(exactly: service.port), resolvedPort > 0 else {
            return (6466, 6467)
        }
        if resolvedPort == 6467 {
            return (6466, 6467)
        }
        let pairingPort = resolvedPort == UInt16.max ? 6467 : resolvedPort + 1
        return (resolvedPort, pairingPort)
    }

    private static func numericHost(from addresses: [Data]?) -> String? {
        for address in addresses ?? [] {
            var storage = sockaddr_storage()
            let copied = address.withUnsafeBytes { buffer -> Bool in
                guard let baseAddress = buffer.baseAddress else { return false }
                memcpy(&storage, baseAddress, min(MemoryLayout<sockaddr_storage>.size, address.count))
                return true
            }
            guard copied else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = withUnsafePointer(to: &storage) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    getnameinfo(
                        sockaddrPointer,
                        socklen_t(address.count),
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }
            }
            if result == 0 {
                let endIndex = host.firstIndex(of: 0) ?? host.endIndex
                return String(decoding: host[..<endIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        return nil
    }
}
