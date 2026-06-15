#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation
import PultCore

/// Identity and state of the lock-screen remote Live Activity. Compiled into
/// both the app and the widget extension; ActivityKit requires the exact same
/// type on both sides.
struct RemoteSessionAttributes: ActivityAttributes {
    enum Status: String, Codable, Hashable {
        case connecting
        case connected
        case failed
    }

    struct ContentState: Codable, Hashable {
        var status: Status
        var message: String?
        var layout: RemoteActivityLayout

        private enum CodingKeys: String, CodingKey {
            case status
            case message
            case layout
        }

        init(
            status: Status,
            message: String? = nil,
            layout: RemoteActivityLayout = .default
        ) {
            self.status = status
            self.message = message
            self.layout = layout
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(Status.self, forKey: .status)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            layout = (try? container.decode(RemoteActivityLayout.self, forKey: .layout)) ?? .default
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encodeIfPresent(message, forKey: .message)
            try container.encode(layout, forKey: .layout)
        }
    }

    var deviceID: UUID
    var deviceName: String
}
#endif
