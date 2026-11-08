import Foundation
import Observation

/// Contenu affiché : liens perso + playlist active, avec les modifications de l'utilisateur appliquées.
@MainActor
@Observable
final class Library {
    private(set) var items: [MediaItem] = []
    private(set) var hiddenItems: [MediaItem] = []
    private(set) var customLinkItems: [MediaItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadedPlaylistID: UUID?

    private var playlistItems: [MediaItem] = []
    private var customItems: [MediaItem] = []
    private var overrides: [String: ItemOverride] = [:]

    private var byKind: [MediaKind: [MediaItem]] = [:]
    private var groupsByKind: [MediaKind: [String]] = [:]
    private var index: [String: MediaItem] = [:]
    private var baseIndex: [String: MediaItem] = [:]

    // MARK: Lecture

    func all(_ kind: MediaKind) -> [MediaItem] { byKind[kind] ?? [] }
    func count(_ kind: MediaKind) -> Int { byKind[kind]?.count ?? 0 }
    func groups(of kind: MediaKind) -> [String] { groupsByKind[kind] ?? [] }

    /// Version à jour (modifications comprises) d'un élément.
    func item(_ id: String) -> MediaItem? { index[id] }

    /// Version d'origine, avant modifications.
    func baseItem(_ id: String) -> MediaItem? { baseIndex[id] }

    func lookup(_ ids: Set<String>) -> [MediaItem] {
        ids.compactMap { index[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func recentlyAdded(_ kind: MediaKind, limit: Int = 20) -> [MediaItem] {
        let list = all(kind).filter { !$0.isCustomLink }
        if list.contains(where: { $0.addedAt != nil }) {
            return Array(list.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }.prefix(limit))
        }
        return Array(list.suffix(limit).reversed())
    }

    // MARK: Chargement

    func setCustomization(links: [MediaItem], overrides: [String: ItemOverride]) {
        customItems = links
        self.overrides = overrides
        rebuild()
    }

    func load(_ playlist: Playlist, force: Bool = false) async {
        if !force, loadedPlaylistID == playlist.id, !playlistItems.isEmpty { return }
        errorMessage = nil

        if !force, let cached = await LibraryCache.load(playlist.id), !cached.isEmpty {
            setPlaylistItems(cached, playlistID: playlist.id)
            guard LibraryCache.isStale(playlist.id) else { return }
        } else if loadedPlaylistID != playlist.id {
            setPlaylistItems([], playlistID: nil)
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await PlaylistLoader.fetch(playlist)
            guard !Task.isCancelled else { return }
            setPlaylistItems(fetched, playlistID: playlist.id)
            LibraryCache.save(fetched, for: playlist.id)
            if fetched.isEmpty { errorMessage = "La playlist est vide ou illisible." }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    func resetPlaylist() {
        errorMessage = nil
        setPlaylistItems([], playlistID: nil)
    }

    /// Recherche insensible à la casse et aux accents, calculée hors du thread principal.
    func search(_ query: String) async -> [MediaKind: [MediaItem]] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return [:] }
        let snapshot = items
        return await Task.detached(priority: .userInitiated) { () -> [MediaKind: [MediaItem]] in
            var results: [MediaKind: [MediaItem]] = [:]
            for item in snapshot
            where item.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || item.group.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                results[item.kind, default: []].append(item)
            }
            return results
        }.value
    }

    // MARK: Privé

    private func setPlaylistItems(_ newItems: [MediaItem], playlistID: UUID?) {
        playlistItems = newItems
        loadedPlaylistID = playlistID
        rebuild()
    }

    private func rebuild() {
        var seen = Set<String>()
        var visible: [MediaItem] = []
        var hidden: [MediaItem] = []
        var custom: [MediaItem] = []
        var kinds: [MediaKind: [MediaItem]] = [:]
        var groupOrder: [MediaKind: [String]] = [:]
        var groupSeen: [MediaKind: Set<String>] = [:]
        var newIndex: [String: MediaItem] = [:]
        var newBase: [String: MediaItem] = [:]
        visible.reserveCapacity(customItems.count + playlistItems.count)

        for original in customItems + playlistItems where seen.insert(original.id).inserted {
            newBase[original.id] = original
            var item = original
            if let change = overrides[original.id] {
                item = change.applied(to: original)
                if change.hidden == true {
                    hidden.append(item)
                    continue
                }
            }
            visible.append(item)
            if item.isCustomLink { custom.append(item) }
            kinds[item.kind, default: []].append(item)
            newIndex[item.id] = item
            if groupSeen[item.kind, default: []].insert(item.group).inserted {
                groupOrder[item.kind, default: []].append(item.group)
            }
        }

        items = visible
        hiddenItems = hidden
        customLinkItems = custom
        byKind = kinds
        groupsByKind = groupOrder
        index = newIndex
        baseIndex = newBase
    }
}
