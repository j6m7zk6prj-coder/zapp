import SwiftUI

struct SeriesDetailView: View {
    let series: MediaItem
    @Environment(PlaylistStore.self) private var playlists
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(FavoritesStore.self) private var favorites
    @State private var detail: SeriesDetail?
    @State private var loadError: String?
    @State private var season = 1

    var body: some View {
        let current = library.item(series.id) ?? series

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DetailHeader(item: current, subtitle: subtitle(current)) {
                    HStack(spacing: 12) {
                        Button {
                            playFirstEpisode(current)
                        } label: {
                            Label("Lire", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryActionStyle())
                        .disabled(detail?.episodes.isEmpty ?? true)

                        Button {
                            favorites.toggle(current)
                        } label: {
                            Image(systemName: favorites.contains(current) ? "checkmark" : "plus")
                        }
                        .buttonStyle(CircleActionStyle())

                        Button {
                            router.edit(current)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(CircleActionStyle())
                    }
                }

                Group {
                    if let detail {
                        content(detail, seriesName: current.name)
                    } else if let loadError {
                        ContentUnavailableView(
                            "Épisodes indisponibles",
                            systemImage: "exclamationmark.triangle",
                            description: Text(loadError)
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func subtitle(_ item: MediaItem) -> String {
        var parts = ["Série", detail?.genre ?? item.group]
        if let rating = item.rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        if let count = detail?.seasons.count, count > 0 { parts.append(count == 1 ? "1 saison" : "\(count) saisons") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func content(_ detail: SeriesDetail, seriesName: String) -> some View {
        if let plot = detail.plot, !plot.isEmpty {
            Text(plot)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }

        if detail.seasons.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(detail.seasons, id: \.self) { number in
                        let selected = number == season
                        Button {
                            withAnimation(.snappy) { season = number }
                        } label: {
                            Text("Saison \(number)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 15)
                                .padding(.vertical, 8)
                                .background {
                                    if selected {
                                        Capsule().fill(Theme.accent)
                                    } else {
                                        Capsule().fill(.ultraThinMaterial)
                                    }
                                }
                                .foregroundStyle(selected ? Theme.onAccent : Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        let episodes = detail.episodes.filter { $0.season == season }
        if episodes.isEmpty {
            Text("Aucun épisode.")
                .foregroundStyle(Theme.textSecondary)
        }
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
            Button {
                router.play(queue: episodes.map { $0.playable(seriesName: seriesName) }, index: index)
            } label: {
                EpisodeRow(episode: episode, seriesName: seriesName)
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    private func playFirstEpisode(_ current: MediaItem) {
        guard let detail else { return }
        let episodes = detail.episodes.filter { $0.season == season }
        guard !episodes.isEmpty else { return }
        router.play(queue: episodes.map { $0.playable(seriesName: current.name) }, index: 0)
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
                .frame(width: 132, height: 74)
                .overlay {
                    AsyncImage(url: episode.imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            ZStack {
                                Theme.gradient(for: seriesName + "\(episode.season)")
                                Text("E\(episode.number)")
                                    .font(.system(.headline, design: .rounded).weight(.heavy))
                            }
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.4))
                        .padding(5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("ÉPISODE \(episode.number)")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Theme.textSecondary)
                Text(episode.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let duration = episode.duration {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}
