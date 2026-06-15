import Foundation

public enum RemoteActivityLayout: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case hybrid
    case media

    public static let `default`: RemoteActivityLayout = .hybrid

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .hybrid: "Hybrid"
        case .media: "Media"
        }
    }

    public var settingsDescription: String {
        switch self {
        case .hybrid:
            "D-pad stays visible while play/pause, mute, and volume get larger Lock Screen targets."
        case .media:
            "Playback, mute, and volume take priority for watching without browsing TV menus."
        }
    }
}

public struct RemoteActivityLayoutStore {
    public static let key = "pult.remoteActivityLayout"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = PultAppGroup.sharedDefaults()) {
        self.defaults = defaults
    }

    public func load() -> RemoteActivityLayout {
        guard let rawValue = defaults.string(forKey: Self.key),
              let layout = RemoteActivityLayout(rawValue: rawValue) else {
            return .default
        }
        return layout
    }

    public func save(_ layout: RemoteActivityLayout) {
        defaults.set(layout.rawValue, forKey: Self.key)
    }
}
