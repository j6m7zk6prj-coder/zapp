import SwiftUI
import UIKit

/// En-tête de fiche plein écran : grande image, logo-titre, infos, actions.
struct DetailHero<Actions: View>: View {
    let item: MediaItem
    let info: TmdbInfo?
    let subtitle: String
    let actions: Actions

    init(item: MediaItem, info: TmdbInfo?, subtitle: String, @ViewBuilder actions: () -> Actions) {
        self.item = item
        self.info = info
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        let isLive = item.kind == .live
        let height = min(UIScreen.main.bounds.height * 0.62, 560)
        ZStack(alignment: .bottom) {
            Group {
                if isLive {
                    ZStack {
                        AmbientBackground()
                        LogoArtwork(url: item.logoURL, name: item.name, logoPadding: 20, initialsSize: 40)
                            .frame(width: 240, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                            .padding(.bottom, 120)
                    }
                } else {
                    RemoteImage(url: info?.poster ?? item.logoURL ?? info?.backdrop) {
                        Theme.gradient(for: item.name)
                    }
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                stops: [.init(color: .clear, location: 0.3), .init(color: Theme.background.opacity(0.8), location: 0.72), .init(color: Theme.background, location: 1)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 12) {
                if let logo = info?.logo {
                    RemoteImage(url: logo, contentMode: .fit) { titleText }
                        .frame(maxWidth: 270, maxHeight: 100)
                } else {
                    titleText
                }
                if let tagline = info?.tagline {
                    Text(tagline)
                        .accentSerif(size: 17)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                actions
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
        .frame(height: height)
    }

    private var titleText: some View {
        Text(info?.title ?? item.displayName)
            .font(.system(size: 32, weight: .bold))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.4), radius: 10)
    }
}

/// Distribution (photos rondes).
struct CastRow: View {
    let cast: [TmdbCast]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Distribution")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(cast) { person in
                        VStack(spacing: 6) {
                            RemoteImage(url: person.photo) {
                                ZStack {
                                    Theme.gradient(for: person.name)
                                    Text(person.name.initials).font(.headline.weight(.heavy))
                                }
                            }
                            .frame(width: 76, height: 76)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                            Text(person.name)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            if let character = person.character, !character.isEmpty {
                                Text(character)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 88)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

/// Résumé dépliable.
struct OverviewText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.82))
            .lineSpacing(3)
            .lineLimit(expanded ? nil : 4)
            .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
            .padding(.horizontal, 20)
    }
}

/// Fiche d'un film, d'une chaîne ou d'un lien perso.
struct ItemDetailView: View {
    let item: MediaItem
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @Environment(ProfileStore.self) private var profiles
    @Environment(MetadataStore.self) private var metadata
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    var body: some View {
        let current = library.item(item.id) ?? item
        let info = metadata.info(for: current)
        let resume = profiles.history(for: current.id).flatMap { $0.canResume ? $0 : nil }

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                DetailHero(item: current, info: info, subtitle: subtitle(current, info)) {
                    VStack(spacing: 12) {
                        Button {
                            router.play(current, context: [current])
                        } label: {
                            Label(resume != nil ? "Reprendre" : current.kind == .live ? "Regarder" : "Lire", systemImage: "play.fill")
                        }
                        .buttonStyle(WhiteCapsuleStyle(fullWidth: true))
                        .disabled(current.streamURL == nil)

                        if let resume {
                            HStack(spacing: 10) {
                                ProgressLine(value: resume.progress)
                                Text("Encore \(resume.remainingText)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        HStack(spacing: 12) {
                            if let trailer = info?.trailerURL {
                                Button {
                                    openURL(trailer)
                                } label: {
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

                if let overview = info?.overview {
                    OverviewText(text: overview)
                }

                if let cast = info?.cast, !cast.isEmpty {
                    CastRow(cast: cast)
                }

                InfoCard(rows: infoRows(current, info))
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tabBarSpacing()
        .task { await metadata.load(current) }
    }

    private func subtitle(_ item: MediaItem, _ info: TmdbInfo?) -> String {
        var parts: [String] = []
        if let year = info?.year { parts.append(String(year)) }
        if let runtime = info?.runtime, !runtime.isEmpty { parts.append(runtime) }
        if let genres = info?.genres, !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ")) }
        if parts.isEmpty { parts = [item.kind == .movie ? "Film" : item.kind == .live ? "En direct" : item.kind.title, item.group] }
        if let rating = info?.rating ?? item.rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        return parts.joined(separator: " · ")
    }

    private func infoRows(_ item: MediaItem, _ info: TmdbInfo?) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let director = info?.director { rows.append((info?.kind == .tv ? "Création" : "Réalisation", director)) }
        if let original = info?.originalTitle { rows.append(("Titre original", original)) }
        rows.append(("Catégorie", item.group))
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
        .glassCard(radius: 20)
    }
}
