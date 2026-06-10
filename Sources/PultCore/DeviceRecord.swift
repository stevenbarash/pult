import Foundation

public struct DeviceRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var commandPort: UInt16
    public var pairingPort: UInt16
    public var lastSeen: Date
    public var isPaired: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        commandPort: UInt16 = 6466,
        pairingPort: UInt16 = 6467,
        lastSeen: Date = .now,
        isPaired: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.commandPort = commandPort
        self.pairingPort = pairingPort
        self.lastSeen = lastSeen
        self.isPaired = isPaired
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
    }
}
