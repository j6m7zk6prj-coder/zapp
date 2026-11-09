import SwiftUI

struct LiveTVView: View {
    enum Mode: String, CaseIterable {
        case discover = "Découvrir"
        case favorites = "Favoris"
        case all = "Toutes"
    }

    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @Environment(ProfileStore.self) private var profiles
    @Environment(AppSettings.self) private var settings
    @State private var mode: Mode = .discover
    @State private var filter: CategoryFilter = .all
    @State private var tonight: [Match] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    switch mode {
                    case .discover: discover
                    case .favorites: grid(library.all(.live).filter { favorites.ids.contains($0.id) }, empty: "Appui long sur une chaîne pour l'ajouter à tes favoris.")
                    case .all:
                        CategoryChips(groups: library.groups(of: .live), selection: $filter)
                        grid(filter.apply(to: library.all(.live), favoriteIDs: favorites.ids), empty: "Ajoute un lien ou une playlist avec des chaînes en direct.")
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(AmbientBackground(tint: Color(hex: 0x0A84FF)))
            .toolbar(.hidden, for: .navigationBar)
            .tabBarSpacing()
            .mediaDestinations()
            .task(id: profiles.footSlugs.joined(separator: ",")) {
                let today = await EspnClient.shared.day(profiles.footSlugs, Date())
                tonight = today.filter { $0.state == .live || $0.state == .scheduled }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                (Text("La télé, ") + Text("en direct.").accentSerif(size: 34))
                    .font(.system(size: 34, weight: .bold))
                Spacer()
                Button {
                    withAnimation { settings.setLiveLayout(settings.liveLayout == .grid ? .list : .grid) }
                } label: {
                    Image(systemName: settings.liveLayout == .grid ? "list.bullet" : "square.grid.2x2")
                }
                .buttonStyle(GlassCircleStyle(size: 40))
                .accessibilityLabel(settings.liveLayout == .grid ? "Afficher en liste" : "Afficher en mosaïque")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Mode.allCases, id: \.self) { item in
                        Pill(title: item.rawValue,
                             icon: item == .favorites ? "heart.fill" : nil,
                             count: item == .all ? library.count(.live) : nil,
                             selected: mode == item) {
                            withAnimation(.snappy) { mode = item }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private var discover: some View {
        if !tonight.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Pour toi", subtitle: "Matchs du jour sur tes chaînes")
                MatchShelf(matches: tonight)
            }
        }

        let recent = profiles.recentChannelIDs.compactMap { library.item($0) }
        if !recent.isEmpty {
            Shelf(title: "Regardées récemment", items: recent, style: .landscape)
        }

        let favoriteChannels = library.all(.live).filter { favorites.ids.contains($0.id) }
        if !favoriteChannels.isEmpty {
            Shelf(title: "Tes chaînes favorites", items: favoriteChannels, style: .landscape)
        }

        let groups = library.groups(of: .live)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Catégories")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(groups.prefix(40), id: \.self) { group in
                        NavigationLink(value: BrowseRoute.group(.live, group)) {
                            HStack {
                                Text(group)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 64)
                            .glassCard(radius: 18, tint: Theme.gradientColor(for: group))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }

        if library.all(.live).isEmpty && !library.isLoading {
            ContentUnavailableView("Aucune chaîne", systemImage: "tv", description: Text("Ajoute un lien ou une playlist avec des chaînes en direct."))
                .padding(.top, 40)
        }
    }

    @ViewBuilder
    private func grid(_ channels: [MediaItem], empty: String) -> some View {
        if channels.isEmpty && !library.isLoading {
            ContentUnavailableView("Rien ici", systemImage: "tv", description: Text(empty))
                .padding(.top, 30)
        } else if settings.liveLayout == .grid {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                ForEach(channels) { channel in
                    MediaButton(item: channel, context: channels) {
                        MediaTile(item: channel, style: .landscape)
                    }
                }
            }
            .padding(.horizontal)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(channels) { channel in
                    MediaButton(item: channel, context: channels) {
                        ChannelRow(item: channel)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                    }
                    Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 90)
                }
            }
        }
    }
}
