import SwiftUI

struct SeriesDetailView: View {
    let series: MediaItem
    @Environment(PlaylistStore.self) private var playlists
    @Environment(PlayerPresenter.self) private var presenter
    @Environment(FavoritesStore.self) private var favorites
    @State private var detail: SeriesDetail?
    @State private var loadError: String?
    @State private var season = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let detail {
                    content(detail)
                } else if let loadError {
                    ContentUnavailableView(
                        "Épisodes indisponibles",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(series.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterArt(item: series)
                .frame(width: 120)
            VStack(alignment: .leading, spacing: 8) {
                Text(series.name)
                    .font(.title3.weight(.bold))
                Text(detail?.genre ?? series.group)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if let rating = series.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
                let isFavorite = favorites.contains(series)
                Button {
                    favorites.toggle(series)
                } label: {
                    Label(isFavorite ? "Dans ma liste" : "Ma liste",
                          systemImage: isFavorite ? "checkmark" : "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func content(_ detail: SeriesDetail) -> some View {
        if let plot = detail.plot, !plot.isEmpty {
            Text(plot)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }

        if detail.seasons.count > 1 {
            Picker("Saison", selection: $season) {
                ForEach(detail.seasons, id: \.self) { number in
                    Text("Saison \(number)").tag(number)
                }
            }
            .pickerStyle(.menu)
        }

        let episodes = detail.episodes.filter { $0.season == season }
        if episodes.isEmpty {
            Text("Aucun épisode.")
                .foregroundStyle(Theme.textSecondary)
        }
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
            Button {
                presenter.play(
                    queue: episodes.map { $0.playable(seriesName: series.name) },
                    index: index
                )
            } label: {
                EpisodeRow(episode: episode, seriesName: series.name)
            }
            .buttonStyle(.plain)
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

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 128, height: 72)
                .overlay {
                    AsyncImage(url: episode.imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            ZStack {
                                Theme.gradient(for: seriesName + "\(episode.season)")
                                Text("E\(episode.number)")
                                    .font(.headline.weight(.heavy))
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(episode.number). \(episode.title)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let duration = episode.duration {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
        }
        .contentShape(Rectangle())
    }
}
