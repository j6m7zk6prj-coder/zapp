import Foundation
import Observation

/// Contenu de la playlist active, indexé pour l'affichage et la recherche.
@MainActor
@Observable
final class Library {
    private(set) var items: [MediaItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadedPlaylistID: UUID?

    private var byKind: [MediaKind: [MediaItem]] = [:]
    private var groupsByKind: [MediaKind: [String]] = [:]
    private var index: [String: MediaItem] = [:]

    func all(_ kind: MediaKind) -> [MediaItem] { byKind[kind] ?? [] }
    func count(_ kind: MediaKind) -> Int { byKind[kind]?.count ?? 0 }
    func groups(of kind: MediaKind) -> [String] { groupsByKind[kind] ?? [] }

    func lookup(_ ids: Set<String>) -> [MediaItem] {
        ids.compactMap { index[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func recentlyAdded(_ kind: MediaKind, limit: Int = 20) -> [MediaItem] {
        let list = all(kind)
        if list.contains(where: { $0.addedAt != nil }) {
            return Array(list.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }.prefix(limit))
        }
        return Array(list.suffix(limit).reversed())
    }

    func load(_ playlist: Playlist, force: Bool = false) async {
        if !force, loadedPlaylistID == playlist.id, !items.isEmpty { return }
        errorMessage = nil

        if !force, let cached = await LibraryCache.load(playlist.id), !cached.isEmpty {
            apply(cached, playlistID: playlist.id)
            guard LibraryCache.isStale(playlist.id) else { return }
        } else if loadedPlaylistID != playlist.id {
            apply([], playlistID: nil)
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await PlaylistLoader.fetch(playlist)
            guard !Task.isCancelled else { return }
            apply(fetched, playlistID: playlist.id)
            LibraryCache.save(fetched, for: playlist.id)
            if fetched.isEmpty { errorMessage = "La playlist est vide ou illisible." }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        apply([], playlistID: nil)
        errorMessage = nil
    }

    /// Recherche insensible à la casse et aux accents, calculée hors du thread principal.
    func search(_ query: String) async -> [MediaKind: [MediaItem]] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return [:] }
        let snapshot = items
        return await Task.detached(priority: .userInitiated) { () -> [MediaKind: [MediaItem]] in
            var results: [MediaKind: [MediaItem]] = [:]
            for item in snapshot
            where item.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                results[item.kind, default: []].append(item)
            }
            return results
        }.value
    }

    private func apply(_ newItems: [MediaItem], playlistID: UUID?) {
        var seen = Set<String>()
        var unique: [MediaItem] = []
        unique.reserveCapacity(newItems.count)
        var kinds: [MediaKind: [MediaItem]] = [:]
        var groupOrder: [MediaKind: [String]] = [:]
        var groupSeen: [MediaKind: Set<String>] = [:]
        var newIndex: [String: MediaItem] = [:]

        for item in newItems where seen.insert(item.id).inserted {
            unique.append(item)
            kinds[item.kind, default: []].append(item)
            newIndex[item.id] = item
            if groupSeen[item.kind, default: []].insert(item.group).inserted {
                groupOrder[item.kind, default: []].append(item.group)
            }
        }

        items = unique
        byKind = kinds
        groupsByKind = groupOrder
        index = newIndex
        loadedPlaylistID = playlistID
    }
}
