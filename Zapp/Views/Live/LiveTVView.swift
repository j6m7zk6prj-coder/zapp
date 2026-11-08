import SwiftUI

struct LiveTVView: View {
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AppSettings.self) private var settings
    @State private var filter: CategoryFilter = .all

    var body: some View {
        let channels = filter.apply(to: library.all(.live), favoriteIDs: favorites.ids)

        NavigationStack {
            VStack(spacing: 0) {
                CategoryChips(groups: library.groups(of: .live), selection: $filter)
                Group {
                    if settings.liveLayout == .grid {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                                ForEach(channels) { channel in
                                    MediaButton(item: channel, context: channels) {
                                        MediaTile(item: channel, style: .landscape)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 28)
                        }
                    } else {
                        List(channels) { channel in
                            MediaButton(item: channel, context: channels) {
                                ChannelRow(item: channel)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.08))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .overlay {
                    if channels.isEmpty && !library.isLoading {
                        ContentUnavailableView(
                            filter == .favorites ? "Aucun favori" : "Aucune chaîne",
                            systemImage: filter == .favorites ? "heart" : "tv",
                            description: Text(filter == .favorites
                                ? "Appui long sur une chaîne pour l'ajouter."
                                : "Ajoute un lien ou une playlist avec des chaînes en direct.")
                        )
                    }
                }
            }
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle("En direct")
            .toolbar {
                Button {
                    withAnimation {
                        settings.setLiveLayout(settings.liveLayout == .grid ? .list : .grid)
                    }
                } label: {
                    Image(systemName: settings.liveLayout == .grid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(settings.liveLayout == .grid ? "Afficher en liste" : "Afficher en mosaïque")
            }
            .mediaDestinations()
        }
    }
}
