import Foundation
import PultCore

@MainActor
final class SharedIntentCommandQueue {
    static let shared = SharedIntentCommandQueue()
    static let didEnqueueCommand = Notification.Name("SharedIntentCommandQueue.didEnqueueCommand")
    private(set) var pendingKeys: [RemoteKey] = []

    private init() {}

    func enqueue(_ key: RemoteKey) {
        pendingKeys.append(key)
        NotificationCenter.default.post(name: Self.didEnqueueCommand, object: nil)
    }

    func drain() -> [RemoteKey] {
        defer { pendingKeys.removeAll() }
        return pendingKeys
    }
}
