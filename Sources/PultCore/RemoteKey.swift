import Foundation

public enum RemoteKey: String, CaseIterable, Sendable, Identifiable {
    case up
    case down
    case left
    case right
    case select
    case back
    case home
    case voiceSearch
    case search
    case power
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case rewind
    case fastForward
    case enter
    case delete

    public var id: String { rawValue }

    public var androidKeyCode: Int {
        switch self {
        case .up: 19
        case .down: 20
        case .left: 21
        case .right: 22
        case .select: 23
        case .back: 4
        case .home: 3
        case .voiceSearch: 231
        case .search: 84
        case .power: 26
        case .volumeUp: 24
        case .volumeDown: 25
        case .mute: 164
        case .playPause: 85
        case .rewind: 89
        case .fastForward: 90
        case .enter: 66
        case .delete: 67
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .voiceSearch: "Voice search"
        case .search: "Search"
        case .power: "Power"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        case .playPause: "Play or pause"
        case .rewind: "Rewind"
        case .fastForward: "Fast forward"
        case .enter: "Enter"
        case .delete: "Delete"
        }
    }

    public var displayTitle: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .voiceSearch: "Voice Search"
        case .search: "Search"
        case .power: "Power"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .playPause: "Play or Pause"
        case .rewind: "Rewind"
        case .fastForward: "Fast Forward"
        case .enter: "Enter"
        case .delete: "Delete"
        }
    }

    public var systemImage: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .select: "smallcircle.filled.circle"
        case .back: "arrow.uturn.backward"
        case .home: "house"
        case .voiceSearch: "mic.fill"
        case .search: "magnifyingglass"
        case .power: "power"
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .mute: "speaker.slash"
        case .playPause: "playpause"
        case .rewind: "backward"
        case .fastForward: "forward"
        case .enter: "return"
        case .delete: "delete.left"
        }
    }

    public var searchAliases: [String] {
        switch self {
        case .up:
            ["arrow up", "move up", "navigate up"]
        case .down:
            ["arrow down", "move down", "navigate down"]
        case .left:
            ["arrow left", "move left", "navigate left"]
        case .right:
            ["arrow right", "move right", "navigate right"]
        case .select:
            ["ok", "confirm", "choose"]
        case .back:
            ["back button", "go back", "return back", "escape"]
        case .home:
            ["go home", "home screen", "tv home"]
        case .voiceSearch:
            ["voice", "voice assist", "google assistant", "assistant", "microphone", "mic", "talk to tv"]
        case .search:
            ["text search", "tv search", "find", "find on tv"]
        case .power:
            ["power toggle", "turn tv on", "turn tv off", "sleep", "wake"]
        case .volumeUp:
            ["volume up", "turn it up", "turn up volume", "raise volume", "increase volume", "louder"]
        case .volumeDown:
            ["volume down", "turn it down", "turn down volume", "lower volume", "decrease volume", "quieter"]
        case .mute:
            ["unmute", "toggle mute", "silence"]
        case .playPause:
            ["play pause", "pause play", "pause", "play", "toggle playback", "media"]
        case .rewind:
            ["backward", "skip back", "go back media"]
        case .fastForward:
            ["forward", "skip forward", "go forward media"]
        case .enter:
            ["keyboard enter", "submit", "done"]
        case .delete:
            ["backspace", "keyboard delete", "remove character"]
        }
    }
}

public struct RemoteCommandPlan: Hashable, Identifiable, Sendable {
    public enum Action: Hashable, Sendable {
        case key(RemoteKey)
        case openKeyboard
        case showFavoriteApps

        public var id: String {
            switch self {
            case let .key(key): "key.\(key.rawValue)"
            case .openKeyboard: "openKeyboard"
            case .showFavoriteApps: "showFavoriteApps"
            }
        }
    }

    public var action: Action
    public var title: String
    public var systemImage: String
    public var searchAliases: [String]

    public var id: String { action.id }

    public var remoteKey: RemoteKey? {
        if case let .key(key) = action {
            return key
        }
        return nil
    }

    public init(action: Action, title: String, systemImage: String, searchAliases: [String]) {
        self.action = action
        self.title = title
        self.systemImage = systemImage
        self.searchAliases = searchAliases
    }

    public static let catalog: [RemoteCommandPlan] = {
        RemoteKey.allCases.map(RemoteCommandPlan.init(key:)) + [
            RemoteCommandPlan(
                action: .openKeyboard,
                title: "Keyboard",
                systemImage: "keyboard",
                searchAliases: [
                    "open keyboard",
                    "show keyboard",
                    "text entry",
                    "type text",
                    "type on tv",
                    "search text"
                ]
            ),
            RemoteCommandPlan(
                action: .showFavoriteApps,
                title: "Favorite Apps",
                systemImage: "square.grid.2x2",
                searchAliases: [
                    "favorite apps",
                    "favorites",
                    "open favorites",
                    "app links",
                    "launcher",
                    "apps"
                ]
            )
        ]
    }()

    public static func plan(for phrase: String) -> RemoteCommandPlan? {
        let normalized = RemoteCommandPhraseNormalizer.normalize(phrase)
        guard !normalized.isEmpty else {
            return nil
        }
        return catalog.first { $0.normalizedSearchAliases.contains(normalized) }
    }

    public static func suggestions(matching phrase: String, limit: Int = Int.max) -> [RemoteCommandPlan] {
        let limit = Swift.max(0, limit)
        guard limit > 0 else {
            return []
        }

        let normalized = RemoteCommandPhraseNormalizer.normalize(phrase)
        guard !normalized.isEmpty else {
            return Array(catalog.prefix(limit))
        }

        let queryTokens = Set(normalized.split(separator: " ").map(String.init))
        let scored = catalog.enumerated().compactMap { index, plan -> (score: Int, index: Int, plan: RemoteCommandPlan)? in
            let aliases = plan.normalizedSearchAliases
            if aliases.contains(normalized) {
                return (0, index, plan)
            }
            if aliases.contains(where: { $0.hasPrefix(normalized) }) {
                return (1, index, plan)
            }
            if aliases.contains(where: { $0.contains(normalized) }) {
                return (2, index, plan)
            }
            if aliases.contains(where: { alias in
                let aliasTokens = Set(alias.split(separator: " ").map(String.init))
                return queryTokens.isSubset(of: aliasTokens) || aliasTokens.isSubset(of: queryTokens)
            }) {
                return (3, index, plan)
            }
            return nil
        }

        return scored
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score
            }
            .prefix(limit)
            .map(\.plan)
    }

    private init(key: RemoteKey) {
        self.init(
            action: .key(key),
            title: key.displayTitle,
            systemImage: key.systemImage,
            searchAliases: [key.rawValue, key.accessibilityLabel] + key.searchAliases
        )
    }

    private var normalizedSearchAliases: [String] {
        ([id, title] + searchAliases)
            .map(RemoteCommandPhraseNormalizer.normalize)
            .filter { !$0.isEmpty }
    }
}

private enum RemoteCommandPhraseNormalizer {
    private static let ignoredTokens: Set<String> = [
        "a",
        "an",
        "button",
        "command",
        "for",
        "go",
        "key",
        "open",
        "or",
        "please",
        "press",
        "remote",
        "send",
        "show",
        "tap",
        "the",
        "to",
        "tv"
    ]

    static func normalize(_ phrase: String) -> String {
        let folded = phrase.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !ignoredTokens.contains($0) }
            .joined(separator: " ")
    }
}

/// Raw values match the `remote.RemoteDirection` enum from
/// Docs/Protocol/remotemessage.proto.
public enum KeyAction: UInt8, Sendable, Equatable {
    case press = 1
    case release = 2
    case tap = 3
}
