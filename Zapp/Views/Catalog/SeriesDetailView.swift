import SwiftUI

struct SeriesDetailView: View {
    let series: MediaItem
    @Environment(PlaylistStore.self) private var playlists
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(FavoritesStore.self) private var favorites
    @Environment(ProfileStore.self) private var profiles
    @Environment(MetadataStore.self) private var metadata
    @Environment(\.openURL) private var openURL
    @State private var detail: SeriesDetail?
    @State private var loadError: String?
    @State private var season = 1

    var body: some View {
        let current = library.item(series.id) ?? series
        let info = metadata.info(for: current)
        let resume = resumeIndex(current)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DetailHero(item: current, info: info, subtitle: subtitle(current, info)) {
                    VStack(spacing: 12) {
                        Button {
                            play(current, from: resume?.index)
                        } label: {
                            Label(resume.map { "Reprendre S\($0.episode.season) E\($0.episode.number)" } ?? "Lire", systemImage: "play.fill")
                        }
                        .buttonStyle(WhiteCapsuleStyle(fullWidth: true))
                        .disabled(detail?.episodes.isEmpty ?? true)

                        HStack(spacing: 12) {
                            if let trailer = info?.trailerURL {
                                Button { openURL(trailer) } label: {
                                    Label("Bande-annonce", systemImage: "play.rectangle")
                                }
                                .buttonStyle(GlassCapsuleStyle(fullWidth: true))
                            }
                            Button {
                                favorites.toggle(current)
                            } label: {
                                Image(systemName: favorites.contains(current) ? "checkmark" : "plus")
                            }
                            .buttonStyle(GlassCircleStyle())
                            .accessibilityLabel("Ma liste")

                            Button {
                                router.edit(current)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(GlassCircleStyle())
                            .accessibilityLabel("Modifier")
                        }
                    }
                }

                if let overview = detail?.plot.flatMap({ $0.isEmpty ? nil : $0 }) ?? info?.overview {
                    OverviewText(text: overview)
                }

                Group {
                    if let detail {
                        episodes(detail, seriesName: current.name)
                    } else if let loadError {
                        ContentUnavailableView("Épisodes indisponibles", systemImage: "exclamationmark.triangle", description: Text(loadError))
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                    }
                }

                if let cast = info?.cast, !cast.isEmpty {
                    CastRow(cast: cast)
                }
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tabBarSpacing()
        .task { await load() }
        .task { await metadata.load(current) }
    }

    private func subtitle(_ item: MediaItem, _ info: TmdbInfo?) -> String {
        var parts = ["Série"]
        if let year = info?.year { parts.append(String(year)) }
        if let genre = info?.genres.first ?? detail?.genre { parts.append(genre) }
        if let count = detail?.seasons.count ?? info?.seasons, count > 0 { parts.append(count == 1 ? "1 saison" : "\(count) saisons") }
        if let rating = info?.rating ?? item.rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        return parts.joined(separator: " · ")
    }

    /// Tous les épisodes dans l'ordre : l'épisode suivant enchaîne même d'une saison à l'autre.
    private var allEpisodes: [Episode] {
        (detail?.episodes ?? []).sorted { ($0.season, $0.number) < ($1.season, $1.number) }
    }

    private func resumeIndex(_ current: MediaItem) -> (index: Int, episode: Episode)? {
        let all = allEpisodes
        let latest = all.enumerated()
            .compactMap { pair -> (Int, Episode, Date)? in
                guard let entry = profiles.history(for: pair.element.playable(seriesName: current.name).id), entry.canResume else { return nil }
                return (pair.offset, pair.element, entry.updatedAt)
            }
            .max { $0.2 < $1.2 }
        return latest.map { (index: $0.0, episode: $0.1) }
    }

    private func play(_ current: MediaItem, from index: Int?) {
        let all = allEpisodes
        guard !all.isEmpty else { return }
        let start = index ?? all.firstIndex { $0.season == season } ?? 0
        router.play(queue: all.map { $0.playable(seriesName: current.name) }, index: start)
    }

    @ViewBuilder
    private func episodes(_ detail: SeriesDetail, seriesName: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Épisodes")
            if detail.seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(detail.seasons, id: \.self) { number in
                            Pill(title: "Saison \(number)", selected: number == season) { season = number }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            let all = allEpisodes
            let queue = all.map { $0.playable(seriesName: seriesName) }
            let list = all.enumerated().filter { $0.element.season == season }
            if list.isEmpty {
                Text("Aucun épisode.").foregroundStyle(Theme.textSecondary).padding(.horizontal, 20)
            }
            LazyVStack(spacing: 10) {
                ForEach(list, id: \.element.id) { index, episode in
                    Button {
                        router.play(queue: queue, index: index)
                    } label: {
                        EpisodeRow(episode: episode, seriesName: seriesName, entry: profiles.history(for: queue[index].id))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func load() async {
        guard detail == nil else { return }
        guard let seriesID = series.seriesID,
              let credentials = playlists.active?.xtreamCredentials else {
            loadError = "Cette playlist ne fournit pas la liste des épisodes."
            return
        }
        do {
            let result = try await XtreamClient(credentials: credentials).seriesDetail(id: seriesID)
            season = result.seasons.first ?? 1
            detail = result
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let seriesName: String
    let entry: HistoryEntry?

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 136, height: 77)
                .overlay {
                    RemoteImage(url: episode.imageURL) {
                        ZStack {
                            Theme.gradient(for: seriesName + "\(episode.season)")
                            Text("E\(episode.number)").font(.system(.headline, design: .rounded).weight(.heavy))
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if let entry, entry.durationMs > 0 {
                        ProgressLine(value: entry.progress, height: 3).padding(6)
                    }
                }
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.9), in: Circle())
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("ÉPISODE \(episode.number)")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Theme.textSecondary)
                Text(episode.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let duration = episode.duration {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .glassCard(radius: 18)
        .contentShape(Rectangle())
    }
}
