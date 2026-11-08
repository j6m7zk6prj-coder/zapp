import SwiftUI

struct LiveTVView: View {
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @State private var filter: CategoryFilter = .all

    var body: some View {
        let channels = filter.apply(to: library.all(.live), favoriteIDs: favorites.ids)

        NavigationStack {
            VStack(spacing: 0) {
                CategoryChips(groups: library.groups(of: .live), selection: $filter)
                List(channels) { channel in
                    MediaButton(item: channel, context: channels) {
                        ChannelRow(item: channel)
                    }
                    .listRowBackground(Theme.background)
                    .listRowSeparatorTint(Theme.surfaceHigh)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if channels.isEmpty && !library.isLoading {
                        ContentUnavailableView(
                            filter == .favorites ? "Aucun favori" : "Aucune chaîne",
                            systemImage: filter == .favorites ? "heart" : "tv",
                            description: Text(filter == .favorites
                                ? "Appui long sur une chaîne pour l'ajouter."
                                : "Ajoute une playlist contenant des chaînes en direct.")
                        )
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Live TV")
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }
}
