import Foundation

/// Modifications faites par l'utilisateur sur une chaîne / un film d'une playlist.
struct ItemOverride: Codable, Hashable, Sendable {
    var name: String?
    var group: String?
    var logoURL: URL?
    /// Image importée depuis Photos, rangée dans Documents/Logos.
    var logoFile: String?
    var removeLogo: Bool?
    var hidden: Bool?

    var isEmpty: Bool {
        (name ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            && (group ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            && logoURL == nil
            && logoFile == nil
            && removeLogo != true
            && hidden != true
    }

    func applied(to item: MediaItem) -> MediaItem {
        var copy = item
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { copy.name = name }
        if let group, !group.trimmingCharacters(in: .whitespaces).isEmpty { copy.group = group }
        if removeLogo == true {
            copy.logoURL = nil
        } else if let logoFile {
            copy.logoURL = AppPaths.logoFile(logoFile)
        } else if let logoURL {
            copy.logoURL = logoURL
        }
        return copy
    }
}

/// Un flux ajouté à la main par l'utilisateur (n'importe quel format).
struct CustomLink: Identifiable, Codable, Hashable, Sendable {
    static let defaultGroup = "Mes liens"
    static let idPrefix = "custom-"

    var id: UUID
    var name: String
    var url: URL
    var group: String
    var kind: MediaKind
    var logoURL: URL?
    var logoFile: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        group: String = CustomLink.defaultGroup,
        kind: MediaKind = .live,
        logoURL: URL? = nil,
        logoFile: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.group = group
        self.kind = kind
        self.logoURL = logoURL
        self.logoFile = logoFile
        self.createdAt = createdAt
    }

    var itemID: String { Self.idPrefix + id.uuidString }

    var resolvedLogoURL: URL? {
        if let logoFile { return AppPaths.logoFile(logoFile) }
        return logoURL
    }

    var mediaItem: MediaItem {
        MediaItem(
            id: itemID,
            name: name,
            group: group.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultGroup : group,
            kind: kind,
            streamURL: url,
            logoURL: resolvedLogoURL,
            addedAt: createdAt
        )
    }
}

extension MediaItem {
    var isCustomLink: Bool { id.hasPrefix(CustomLink.idPrefix) }
}
