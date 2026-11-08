import SwiftUI

/// En-tête de fiche façon Apple TV : fond flouté, affiche, titre, actions.
struct DetailHeader<Actions: View>: View {
    let item: MediaItem
    let subtitle: String
    let actions: Actions

    init(item: MediaItem, subtitle: String, @ViewBuilder actions: () -> Actions) {
        self.item = item
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(height: 470)
                .overlay {
                    AsyncImage(url: item.logoURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .blur(radius: 40)
                                .opacity(0.6)
                        } else {
                            Theme.gradient(for: item.name).opacity(0.55)
                        }
                    }
                }
                .clipped()

            LinearGradient(colors: [.clear, Theme.background.opacity(0.7), Theme.background],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 14) {
                Group {
                    if item.kind == .live {
                        LandscapeArt(item: item).frame(width: 250)
                    } else {
                        PosterArt(item: item).frame(width: 150)
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 22, y: 10)

                Text(item.name)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                actions
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

/// Fiche d'un film, d'une vidéo ou d'un lien perso.
struct ItemDetailView: View {
    let item: MediaItem
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let current = library.item(item.id) ?? item

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DetailHeader(item: current, subtitle: subtitle(current)) {
                    HStack(spacing: 12) {
                        Button {
                            router.play(current, context: [current])
                        } label: {
                            Label("Lire", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryActionStyle())
                        .disabled(current.streamURL == nil)

                        Button {
                            favorites.toggle(current)
                        } label: {
                            Image(systemName: favorites.contains(current) ? "checkmark" : "plus")
                        }
                        .buttonStyle(CircleActionStyle())
                        .accessibilityLabel("Favori")

                        Button {
                            router.edit(current)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(CircleActionStyle())
                        .accessibilityLabel("Modifier")
                    }
                }

                InfoCard(rows: infoRows(current))
                    .padding(.horizontal)
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func subtitle(_ item: MediaItem) -> String {
        var parts = [item.kind == .movie ? "Film" : item.kind.title, item.group]
        if let rating = item.rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        return parts.joined(separator: " · ")
    }

    private func infoRows(_ item: MediaItem) -> [(String, String)] {
        var rows: [(String, String)] = [("Catégorie", item.group)]
        if let url = item.streamURL {
            rows.append(("Format", LinkInspector.format(of: url).rawValue))
            rows.append(("Lecteur", PlaybackSupport.engineLabel(for: url, preference: settings.engine)))
        }
        rows.append(("Source", item.isCustomLink ? "Lien ajouté à la main" : "Playlist"))
        return rows
    }
}

struct InfoCard: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                HStack {
                    Text(row.0)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(row.1)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
                .font(.subheadline)
                .padding(.vertical, 12)
                if offset < rows.count - 1 {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
