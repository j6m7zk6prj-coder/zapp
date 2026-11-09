import Foundation
import Observation

struct Profile: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var colorHex: UInt32
    /// Symbole SF affiché dans l'avatar (nil = initiale).
    var symbol: String?

    var initial: String {
        let trimmed = name.trimmed
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }

    static let colors: [UInt32] = [0x8B7CFF, 0xFF6B6B, 0x34C759, 0xFF9F0A, 0xBF5AF2, 0x64D2FF, 0xFF375F, 0xFFD60A]
    static let symbols = ["person.fill", "star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill", "moon.fill", "gamecontroller.fill", "soccerball", "film.fill"]
}

struct FollowedTeam: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var logo: URL?
    var league: String

    var team: TeamRef { TeamRef(id: id, name: name, shortName: name, abbreviation: "", logo: logo, color: nil) }
}

struct HistoryEntry: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var subtitle: String?
    var url: URL
    var artwork: URL?
    var isLive: Bool
    var positionMs: Int = 0
    var durationMs: Int = 0
    var updatedAt = Date()

    var progress: Double { durationMs > 0 ? min(max(Double(positionMs) / Double(durationMs), 0), 1) : 0 }
    /// Film ou épisode commencé (plus de 30 s) et pas terminé.
    var canResume: Bool { !isLive && durationMs > 0 && positionMs > 30_000 && progress < 0.95 }

    var remainingText: String {
        let minutes = max(1, (durationMs - positionMs) / 60_000)
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }

    var playable: Playable {
        Playable(id: id, title: title, subtitle: subtitle, url: url, artworkURL: artwork, isLive: isLive)
    }
}

struct ProfileData: Codable {
    var favorites: Set<String> = []
    var leagues: [String] = LeagueCatalog.defaultFollowed
    var teams: [FollowedTeam] = []
    /// Chaînes épinglées par compétition (slug → identifiants).
    var channelPins: [String: [String]] = [:]
    var history: [HistoryEntry] = []
}

/// Profils : chacun a ses favoris, son historique, ses ligues et ses équipes.
@MainActor
@Observable
final class ProfileStore {
    private(set) var profiles: [Profile] = []
    private(set) var activeID: UUID
    private(set) var current = ProfileData()

    private static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var listURL: URL { folder.appendingPathComponent("profiles.json") }
    private static func dataURL(_ id: UUID) -> URL { folder.appendingPathComponent("profile-\(id.uuidString).json") }

    private struct ListFile: Codable {
        var profiles: [Profile]
        var activeID: UUID?
    }

    init() {
        if let data = try? Data(contentsOf: Self.listURL),
           let file = try? JSONDecoder().decode(ListFile.self, from: data),
           !file.profiles.isEmpty {
            profiles = file.profiles
            activeID = file.activeID.flatMap { id in file.profiles.contains { $0.id == id } ? id : nil } ?? file.profiles[0].id
            current = Self.load(activeID)
        } else {
            let first = Profile(name: "Moi", colorHex: Profile.colors[0], symbol: nil)
            profiles = [first]
            activeID = first.id
            var data = ProfileData()
            // Reprise des favoris de la version précédente.
            data.favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites.v1") ?? [])
            current = data
            saveList()
            saveData()
        }
    }

    var active: Profile { profiles.first { $0.id == activeID } ?? profiles[0] }

    // MARK: Profils

    @discardableResult
    func add(name: String, colorHex: UInt32? = nil, symbol: String? = nil) -> Profile {
        let profile = Profile(
            name: name.trimmed.isEmpty ? "Profil \(profiles.count + 1)" : name.trimmed,
            colorHex: colorHex ?? Profile.colors[profiles.count % Profile.colors.count],
            symbol: symbol
        )
        profiles.append(profile)
        if let data = try? JSONEncoder().encode(ProfileData()) { try? data.write(to: Self.dataURL(profile.id), options: .atomic) }
        saveList()
        return profile
    }

    func update(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        saveList()
    }

    func delete(_ profile: Profile) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        try? FileManager.default.removeItem(at: Self.dataURL(profile.id))
        if activeID == profile.id { switchTo(profiles[0].id) } else { saveList() }
    }

    func switchTo(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }), id != activeID else { return }
        saveData()
        activeID = id
        current = Self.load(id)
        saveList()
    }

    // MARK: Favoris

    func toggleFavorite(_ id: String) {
        if current.favorites.contains(id) { current.favorites.remove(id) } else { current.favorites.insert(id) }
        saveData()
    }

    // MARK: Foot

    func follows(league slug: String) -> Bool { current.leagues.contains(slug) }
    func follows(team id: String) -> Bool { current.teams.contains { $0.id == id } }

    func setLeague(_ slug: String, followed: Bool) {
        current.leagues.removeAll { $0 == slug }
        if followed { current.leagues.append(slug) }
        saveData()
    }

    func setTeam(_ team: FollowedTeam, followed: Bool) {
        current.teams.removeAll { $0.id == team.id }
        if followed { current.teams.append(team) }
        saveData()
    }

    /// Compétitions à charger : suivies + celles des équipes suivies.
    var footSlugs: [String] {
        var result = current.leagues
        for team in current.teams where !team.league.isEmpty && !result.contains(team.league) { result.append(team.league) }
        return result
    }

    func pinnedChannels(_ slug: String) -> [String] { current.channelPins[slug] ?? [] }

    func togglePin(_ slug: String, channelID: String) {
        var list = current.channelPins[slug] ?? []
        if let index = list.firstIndex(of: channelID) { list.remove(at: index) } else { list.insert(channelID, at: 0) }
        current.channelPins[slug] = list.isEmpty ? nil : list
        saveData()
    }

    // MARK: Historique

    /// Enregistre la position de lecture. Écrit sur disque au plus toutes les quelques secondes.
    func record(_ playable: Playable, positionMs: Int?, durationMs: Int?) {
        var entry = current.history.first { $0.id == playable.id }
            ?? HistoryEntry(id: playable.id, title: playable.title, url: playable.url, isLive: playable.isLive)
        entry.title = playable.title
        entry.subtitle = playable.subtitle
        entry.url = playable.url
        entry.artwork = playable.artworkURL
        entry.isLive = playable.isLive
        if let positionMs, positionMs >= 0 { entry.positionMs = positionMs }
        if let durationMs, durationMs > 0 { entry.durationMs = durationMs }
        entry.updatedAt = Date()
        current.history.removeAll { $0.id == playable.id }
        current.history.insert(entry, at: 0)
        if current.history.count > 200 { current.history.removeLast(current.history.count - 200) }
        saveData()
    }

    func history(for id: String) -> HistoryEntry? { current.history.first { $0.id == id } }

    var continueWatching: [HistoryEntry] { Array(current.history.filter(\.canResume).prefix(20)) }
    var recentChannelIDs: [String] { current.history.filter(\.isLive).prefix(20).map(\.id) }

    func removeHistory(_ id: String) {
        current.history.removeAll { $0.id == id }
        saveData()
    }

    func clearHistory() {
        current.history.removeAll()
        saveData()
    }

    // MARK: Fichiers

    private static func load(_ id: UUID) -> ProfileData {
        guard let data = try? Data(contentsOf: dataURL(id)),
              let decoded = try? JSONDecoder().decode(ProfileData.self, from: data) else { return ProfileData() }
        return decoded
    }

    private func saveData() {
        if let data = try? JSONEncoder().encode(current) { try? data.write(to: Self.dataURL(activeID), options: .atomic) }
    }

    private func saveList() {
        if let data = try? JSONEncoder().encode(ListFile(profiles: profiles, activeID: activeID)) {
            try? data.write(to: Self.listURL, options: .atomic)
        }
    }
}
