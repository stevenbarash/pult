import Foundation

public struct PairingCode: RawRepresentable, Equatable, Sendable {
    /// Character count of a v2 pairing code.
    public static let length = 6

    public let rawValue: String

    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == Self.length, trimmed.allSatisfy(\.isHexDigit) else {
            return nil
        }
        self.rawValue = trimmed
    }

    /// Uppercases the input and drops characters outside the pairing
    /// alphabet, capped at `length`. For live filtering of code entry.
    public static func sanitized(_ raw: String) -> String {
        String(raw.uppercased().filter(\.isHexDigit).prefix(length))
    }
}
