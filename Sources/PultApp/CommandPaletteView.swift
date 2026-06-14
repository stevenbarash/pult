import Foundation
import SwiftUI
import PultCore

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss

    let device: DeviceRecord?
    let connectionState: ConnectionState
    let onCommand: (RemoteQuickCommand) -> Void

    @State private var query = ""
    @State private var scope: RemoteCommandScope = .all

    private var commands: [RemoteQuickCommand] {
        RemoteQuickCommand.commands(device: device, connectionState: connectionState)
    }

    private var visibleCommands: [RemoteQuickCommand] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return commands.filter { command in
            (scope == .all || command.scope == scope)
                && (trimmedQuery.isEmpty || command.matches(trimmedQuery))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Command Type", selection: $scope) {
                        ForEach(RemoteCommandScope.allCases) { scope in
                            Label(scope.title, systemImage: scope.systemImage)
                                .tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    if visibleCommands.isEmpty {
                        ContentUnavailableView(
                            "No Commands",
                            systemImage: "command",
                            description: Text("Try another command, app, or setup action.")
                        )
                    } else {
                        ForEach(visibleCommands) { command in
                            Button {
                                dismiss()
                                onCommand(command)
                            } label: {
                                CommandPaletteRow(command: command)
                            }
                            .buttonStyle(.plain)
                            .disabled(!command.isEnabled)
                        }
                    }
                } header: {
                    Text(sectionTitle)
                }
            }
            .navigationTitle("Command")
            .scrollContentBackground(.hidden)
            .background { RemoteBackground() }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, placement: .toolbar, prompt: "Search commands")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sectionTitle: String {
        scope == .all ? "Actions" : scope.title
    }
}

private struct CommandPaletteRow: View {
    let command: RemoteQuickCommand

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.systemImage)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(command.isEnabled ? command.tint : Color.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(command.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(command.isEnabled ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(command.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)

            Image(systemName: command.trailingSystemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(command.title). \(command.subtitle)")
    }
}

enum RemoteCommandScope: String, CaseIterable, Identifiable {
    case all
    case remote
    case apps
    case setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .remote: "Remote"
        case .apps: "Apps"
        case .setup: "Setup"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "command"
        case .remote: "button.programmable"
        case .apps: "square.grid.2x2"
        case .setup: "wrench.and.screwdriver"
        }
    }
}

enum RemoteQuickCommandAction {
    case key(RemoteKey)
    case connect
    case addDevice
    case textEntry
    case pairing
    case manageDevices
    case favoriteApps
    case diagnostics
}

struct RemoteQuickCommand: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var trailingSystemImage: String = "return"
    var tint: Color
    var scope: RemoteCommandScope
    var aliases: [String]
    var isEnabled: Bool
    var action: RemoteQuickCommandAction

    func matches(_ query: String) -> Bool {
        let normalized = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return searchTokens.contains { token in
            token.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .localizedStandardContains(normalized)
        }
    }

    private var searchTokens: [String] {
        [title, subtitle, scope.title] + aliases
    }

    static func commands(device: DeviceRecord?, connectionState: ConnectionState) -> [RemoteQuickCommand] {
        let hasDevice = device != nil
        let isPaired = device?.isPaired == true
        let isConnected = connectionState == .connected
        let deviceName = device?.name ?? "TV"

        var commands: [RemoteQuickCommand] = [
            RemoteQuickCommand(
                id: "add-tv",
                title: "Add TV",
                subtitle: "Scan nearby or enter an IP address.",
                systemImage: "plus",
                tint: .pultAccent,
                scope: .setup,
                aliases: ["scan", "manual ip", "new tv", "network"],
                isEnabled: true,
                action: .addDevice
            )
        ]

        if hasDevice {
            commands.append(
                RemoteQuickCommand(
                    id: "connect",
                    title: isConnected ? "Reconnect" : "Connect",
                    subtitle: isPaired ? "\(deviceName) is ready for a fresh session." : "Pair \(deviceName) before connecting.",
                    systemImage: "arrow.clockwise",
                    tint: PultDesign.connected,
                    scope: .setup,
                    aliases: ["retry", "redial", "wake", "session"],
                    isEnabled: isPaired,
                    action: .connect
                )
            )
            commands.append(
                RemoteQuickCommand(
                    id: "pair",
                    title: "Pair Again",
                    subtitle: "Start a new pairing handshake with \(deviceName).",
                    systemImage: "link",
                    tint: PultDesign.warning,
                    scope: .setup,
                    aliases: ["code", "setup", "tls", "handshake"],
                    isEnabled: true,
                    action: .pairing
                )
            )
            commands.append(
                RemoteQuickCommand(
                    id: "diagnostics",
                    title: "Diagnostics",
                    subtitle: "Review reachability, session state, and validation.",
                    systemImage: "stethoscope",
                    tint: PultDesign.utility,
                    scope: .setup,
                    aliases: ["validation", "status", "debug", "reachability"],
                    isEnabled: true,
                    action: .diagnostics
                )
            )
            commands.append(
                RemoteQuickCommand(
                    id: "manage-tvs",
                    title: "Manage TVs",
                    subtitle: "Select, reorder, or remove saved TVs.",
                    systemImage: "list.bullet",
                    tint: .pultAccent,
                    scope: .setup,
                    aliases: ["devices", "saved", "delete", "reorder"],
                    isEnabled: true,
                    action: .manageDevices
                )
            )
        }

        commands.append(
            RemoteQuickCommand(
                id: "keyboard",
                title: "TV Keyboard",
                subtitle: keyboardSubtitle(hasDevice: hasDevice, isPaired: isPaired),
                systemImage: "keyboard",
                tint: .pultAccent,
                scope: .apps,
                aliases: ["text", "search", "type", "input", "ime"],
                isEnabled: hasDevice && isPaired,
                action: .textEntry
            )
        )
        commands.append(
            RemoteQuickCommand(
                id: "favorite-apps",
                title: "Favorite Apps",
                subtitle: appSubtitle(hasDevice: hasDevice, isPaired: isPaired),
                systemImage: "square.grid.2x2",
                tint: .pultAccent,
                scope: .apps,
                aliases: ["launcher", "youtube", "netflix", "hulu", "spotify"],
                isEnabled: hasDevice && isPaired,
                action: .favoriteApps
            )
        )

        commands.append(contentsOf: remoteKeyCommands(isEnabled: isPaired && isConnected))
        return commands
    }

    private static func keyboardSubtitle(hasDevice: Bool, isPaired: Bool) -> String {
        if !hasDevice {
            return "Add a TV before typing."
        }
        if !isPaired {
            return "Pair the selected TV before typing."
        }
        return "Type into the focused TV text field."
    }

    private static func appSubtitle(hasDevice: Bool, isPaired: Bool) -> String {
        if !hasDevice {
            return "Add a TV before launching apps."
        }
        if !isPaired {
            return "Pair the selected TV before launching apps."
        }
        return "Open saved app links on the selected TV."
    }

    private static func remoteKeyCommands(isEnabled: Bool) -> [RemoteQuickCommand] {
        let keys: [RemoteKey] = [
            .up, .down, .left, .right, .select,
            .back, .home, .voiceSearch, .search, .playPause, .rewind, .fastForward,
            .volumeUp, .volumeDown, .mute, .power
        ]

        return keys.map { key in
            RemoteQuickCommand(
                id: "key-\(key.rawValue)",
                title: key.displayTitle,
                subtitle: isEnabled ? "Send to the selected TV." : "Connect a paired TV first.",
                systemImage: key.systemImage,
                tint: tint(for: key),
                scope: .remote,
                aliases: [key.rawValue, key.accessibilityLabel] + key.searchAliases,
                isEnabled: isEnabled,
                action: .key(key)
            )
        }
    }

    private static func tint(for key: RemoteKey) -> Color {
        switch key {
        case .power:
            PultDesign.danger
        case .volumeUp, .volumeDown, .mute:
            PultDesign.utility
        case .search, .voiceSearch, .playPause, .rewind, .fastForward:
            PultDesign.accent
        default:
            .primary
        }
    }
}
