import Foundation
import Observation
import SwiftUI // MutableCollection.move(fromOffsets:toOffset:)

/// Liens ajoutés à la main + modifications (nom, logo, catégorie, masquage) des éléments de playlist.
@MainActor
@Observable
final class CustomizationStore {
    private(set) var links: [CustomLink] = []
    private(set) var overrides: [String: ItemOverride] = [:]
    /// Incrémenté à chaque modification, pour reconstruire la bibliothèque.
    private(set) var revision = 0

    private struct Snapshot: Codable {
        var links: [CustomLink]
        var overrides: [String: ItemOverride]
    }

    private static var fileURL: URL {
        AppPaths.documents.appendingPathComponent("customization.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            links = snapshot.links
            overrides = snapshot.overrides
        }
    }

    var linkItems: [MediaItem] { links.map(\.mediaItem) }

    func link(forItemID id: String) -> CustomLink? {
        links.first { $0.itemID == id }
    }

    // MARK: Liens

    func save(_ link: CustomLink) {
        if let index = links.firstIndex(where: { $0.id == link.id }) {
            if links[index].logoFile != link.logoFile { LogoStorage.delete(links[index].logoFile) }
            links[index] = link
        } else {
            links.append(link)
        }
        persist()
    }

    func delete(_ link: CustomLink) {
        LogoStorage.delete(link.logoFile)
        links.removeAll { $0.id == link.id }
        if let removed = overrides.removeValue(forKey: link.itemID) {
            LogoStorage.delete(removed.logoFile)
        }
        persist()
    }

    func moveLinks(from source: IndexSet, to destination: Int) {
        links.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: Modifications

    func itemOverride(for id: String) -> ItemOverride {
        overrides[id] ?? ItemOverride()
    }

    func setOverride(_ value: ItemOverride, for id: String) {
        let previous = overrides[id]
        if previous?.logoFile != value.logoFile { LogoStorage.delete(previous?.logoFile) }
        overrides[id] = value.isEmpty ? nil : value
        persist()
    }

    func resetOverride(for id: String) {
        setOverride(ItemOverride(), for: id)
    }

    func setHidden(_ hidden: Bool, id: String) {
        var value = itemOverride(for: id)
        value.hidden = hidden ? true : nil
        setOverride(value, for: id)
    }

    private func persist() {
        revision += 1
        let snapshot = Snapshot(links: links, overrides: overrides)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
