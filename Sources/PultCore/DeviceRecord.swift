import Foundation

public enum DeviceRecordSource: String, Codable, Hashable, Sendable {
    case manual
    case bonjour
}

public struct DeviceRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var commandPort: UInt16
    public var pairingPort: UInt16
    public var lastSeen: Date
    public var isPaired: Bool
    public var source: DeviceRecordSource
    public var lastSuccessfulValidation: PhysicalDeviceValidationRecord?

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        commandPort: UInt16 = 6466,
        pairingPort: UInt16 = 6467,
        lastSeen: Date = .now,
        isPaired: Bool = false,
        source: DeviceRecordSource = .manual,
        lastSuccessfulValidation: PhysicalDeviceValidationRecord? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.commandPort = commandPort
        self.pairingPort = pairingPort
        self.lastSeen = lastSeen
        self.isPaired = isPaired
        self.source = source
        self.lastSuccessfulValidation = lastSuccessfulValidation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        commandPort = try container.decode(UInt16.self, forKey: .commandPort)
        pairingPort = try container.decode(UInt16.self, forKey: .pairingPort)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        // Records saved before pairing support lack this key.
        isPaired = try container.decodeIfPresent(Bool.self, forKey: .isPaired) ?? false
        // Records saved before Bonjour source tracking are manual/cache entries.
        source = try container.decodeIfPresent(DeviceRecordSource.self, forKey: .source) ?? .manual
        // Records saved before physical-device validation tracking have not
        // been validated until a successful report is explicitly stored.
        lastSuccessfulValidation = try container.decodeIfPresent(
            PhysicalDeviceValidationRecord.self,
            forKey: .lastSuccessfulValidation
        )
    }

    public var validationClaimState: DeviceValidationClaimState {
        if let lastSuccessfulValidation {
            return .validated(lastSuccessfulValidation)
        }
        return .unvalidated
    }

    public var isValidatedOnPhysicalDevice: Bool {
        lastSuccessfulValidation != nil
    }

    @discardableResult
    public mutating func recordSuccessfulValidation(_ validation: PhysicalDeviceValidationRecord) -> Bool {
        guard validation.deviceID == id else { return false }
        lastSuccessfulValidation = validation
        return true
    }

    @discardableResult
    public mutating func recordSuccessfulValidation(from report: ValidationReport) -> Bool {
        guard let validation = report.physicalDeviceValidation else { return false }
        return recordSuccessfulValidation(validation)
    }

    public func recordingSuccessfulValidation(from report: ValidationReport) -> DeviceRecord? {
        var copy = self
        guard copy.recordSuccessfulValidation(from: report) else { return nil }
        return copy
    }

    @discardableResult
    public static func recordSuccessfulValidation(
        from report: ValidationReport,
        in devices: inout [DeviceRecord]
    ) -> PhysicalDeviceValidationRecord? {
        guard let deviceID = report.deviceID,
              let index = devices.firstIndex(where: { $0.id == deviceID }),
              devices[index].recordSuccessfulValidation(from: report) else {
            return nil
        }
        return devices[index].lastSuccessfulValidation
    }
}

public extension DeviceStore {
    @discardableResult
    func saveSuccessfulValidation(from report: ValidationReport) -> PhysicalDeviceValidationRecord? {
        var devices = loadDevices()
        guard let validation = DeviceRecord.recordSuccessfulValidation(from: report, in: &devices) else {
            return nil
        }
        saveDevices(devices)
        return validation
    }
}
