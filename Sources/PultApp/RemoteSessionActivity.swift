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

        init(
            status: Status,
            message: String? = nil,
            layout: RemoteActivityLayout = .default
        ) {
            self.status = status
            self.message = message
            self.layout = layout
        }
    }

    var deviceID: UUID
    var deviceName: String
}
#endif
