import Foundation
import SwiftUI
import PultCore

struct FavoriteAppLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RemoteControlModel

    @State private var favorites: [FavoriteAppLink] = []
    @State private var title = ""
    @State private var appLink = ""
    @State private var favoriteSearchText = ""
    @State private var statusMessage: String?
    @State private var launchingID: UUID?

    private let store = FavoriteAppLinkStore()

    private var canLaunch: Bool {
        model.selectedDevice?.isPaired == true
    }

    private var normalizedNewURL: URL? {
        FavoriteAppLink.normalizedURL(from: appLink)
    }

    private var canAddFavorite: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && normalizedNewURL != nil
    }

    private var isFilteringFavorites: Bool {
        !favoriteSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleFavorites: [FavoriteAppLink] {
        let query = favoriteSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return favorites }
        return favorites.filter { favorite in
            favorite.title.localizedStandardContains(query)
                || favorite.urlString.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    launcherStatusRow
                }

                Section {
                    if visibleFavorites.isEmpty {
                        ContentUnavailableView(
                            isFilteringFavorites ? "No Matches" : "No Favorites",
                            systemImage: isFilteringFavorites ? "magnifyingglass" : "square.grid.2x2",
                            description: Text(
                                isFilteringFavorites
                                    ? "Try another app name or link."
                                    : "Add an app link or restore the starter set."
                            )
                        )
                    } else if isFilteringFavorites {
                        ForEach(visibleFavorites) { favorite in
                            favoriteButton(for: favorite)
                        }
                    } else {
                        ForEach(favorites) { favorite in
                            favoriteButton(for: favorite)
                        }
                        .onMove(perform: moveFavorites)
                        .onDelete(perform: deleteFavorites)
                    }

                    Button("Restore Starter Set", systemImage: "arrow.counterclockwise") {
                        favorites = FavoriteAppLink.defaultFavorites
                        favoriteSearchText = ""
                        saveFavorites()
                    }
                } header: {
                    Text("Favorites")
                } footer: {
                    Text(favoritesFooterText)
                }

                Section {
                    TextField("App name", text: $title)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                    TextField("https://example.com", text: $appLink)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .textContentType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    Button("Add Favorite", systemImage: "plus", action: addFavorite)
                        .disabled(!canAddFavorite)
                } header: {
                    Text("Custom Link")
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Favorite Apps")
            .scrollContentBackground(.hidden)
            .background { RemoteBackground() }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $favoriteSearchText, placement: .toolbar, prompt: "Search apps")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                #endif
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard favorites.isEmpty else { return }
            favorites = store.load()
        }
    }

    private var favoritesFooterText: String {
        if isFilteringFavorites {
            return "Clear search to reorder favorites. App links are sent over the Android TV Remote Service app-link command."
        }
        return "App links are sent over the Android TV Remote Service app-link command. TVs decide whether a link opens an installed app or a browser."
    }

    private var launcherStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: canLaunch ? "link.circle.fill" : "link.badge.plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(canLaunch ? Color.green : PultDesign.warning)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedDevice?.name ?? "No TV Selected")
                    .font(.headline)
                Text(launcherStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var launcherStatusText: String {
        guard let device = model.selectedDevice else {
            return "Add or select a TV before launching apps."
        }
        guard device.isPaired else {
            return "Pair \(device.name) before sending app links."
        }
        switch model.session.connectionState {
        case .connected:
            return "Ready to send app links."
        case .connecting:
            return "Connecting."
        case .disconnected:
            return "The launcher will connect before sending."
        case let .failed(message):
            return message
        }
    }

    private func favoriteButton(for favorite: FavoriteAppLink) -> some View {
        Button {
            launch(favorite)
        } label: {
            FavoriteAppLinkRow(
                favorite: favorite,
                isLaunching: launchingID == favorite.id
            )
        }
        .disabled(!canLaunch || launchingID != nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                delete(favorite)
            }
        }
    }

    private func launch(_ favorite: FavoriteAppLink) {
        guard let url = favorite.url else {
            statusMessage = "Check the app link for \(favorite.title)."
            return
        }
        guard model.selectedDevice?.isPaired == true else {
            statusMessage = "Pair a TV before launching apps."
            return
        }

        launchingID = favorite.id
        statusMessage = "Sending \(favorite.title)..."
        Task {
            let outcome = await model.openAppLink(url)
            if outcome == .sent {
                statusMessage = "Sent \(favorite.title) to \(model.selectedDevice?.name ?? "TV")."
            } else {
                statusMessage = model.session.lastError ?? "The TV did not accept the app link."
            }
            launchingID = nil
        }
    }

    private func addFavorite() {
        guard let url = normalizedNewURL else { return }
        let favorite = FavoriteAppLink(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            urlString: url.absoluteString,
            systemImage: "link"
        )
        favorites.append(favorite)
        saveFavorites()
        title = ""
        appLink = ""
        favoriteSearchText = ""
        statusMessage = "Added \(favorite.title)."
    }

    private func delete(_ favorite: FavoriteAppLink) {
        favorites.removeAll { $0.id == favorite.id }
        saveFavorites()
    }

    private func deleteFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        saveFavorites()
    }

    private func moveFavorites(fromOffsets source: IndexSet, toOffset destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }

    private func saveFavorites() {
        store.save(favorites)
    }
}

private struct FavoriteAppLinkRow: View {
    let favorite: FavoriteAppLink
    let isLaunching: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: favorite.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(favorite.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(favorite.urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isLaunching {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Launch \(favorite.title)")
    }
}

struct FavoriteAppLink: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var urlString: String
    var systemImage: String

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        systemImage: String
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.systemImage = systemImage
    }

    var url: URL? {
        Self.normalizedURL(from: urlString)
    }

    static let defaultFavorites: [FavoriteAppLink] = [
        FavoriteAppLink(title: "YouTube", urlString: "https://www.youtube.com/tv", systemImage: "play.rectangle.fill"),
        FavoriteAppLink(title: "Netflix", urlString: "https://www.netflix.com", systemImage: "n.square.fill"),
        FavoriteAppLink(title: "Prime Video", urlString: "https://app.primevideo.com", systemImage: "play.tv.fill"),
        FavoriteAppLink(title: "Disney+", urlString: "https://www.disneyplus.com", systemImage: "sparkles.tv.fill"),
        FavoriteAppLink(title: "Hulu", urlString: "https://www.hulu.com", systemImage: "h.square.fill"),
        FavoriteAppLink(title: "Max", urlString: "https://play.max.com", systemImage: "m.square.fill"),
        FavoriteAppLink(title: "Spotify", urlString: "https://open.spotify.com", systemImage: "music.note.tv.fill"),
        FavoriteAppLink(title: "Google TV", urlString: "https://tv.google", systemImage: "tv.fill")
    ]

    static func normalizedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: candidate)
    }
}

struct FavoriteAppLinkStore {
    private let key = "pult.favoriteAppLinks"
    private let defaults = PultAppGroup.sharedDefaults()

    func load() -> [FavoriteAppLink] {
        guard let data = defaults.data(forKey: key) else {
            return FavoriteAppLink.defaultFavorites
        }
        return (try? JSONDecoder().decode([FavoriteAppLink].self, from: data))
            ?? FavoriteAppLink.defaultFavorites
    }

    func save(_ favorites: [FavoriteAppLink]) {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        defaults.set(data, forKey: key)
    }
}
