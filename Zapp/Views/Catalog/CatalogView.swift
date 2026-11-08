import SwiftUI

/// Grille de films ou de séries, filtrable par catégorie.
struct CatalogView: View {
    let kind: MediaKind
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @State private var filter: CategoryFilter = .all

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        let items = filter.apply(to: library.all(kind), favoriteIDs: favorites.ids)

        NavigationStack {
            VStack(spacing: 0) {
                CategoryChips(groups: library.groups(of: kind), selection: $filter)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            MediaButton(item: item, context: items) {
                                PosterCard(item: item)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .overlay {
                    if items.isEmpty && !library.isLoading {
                        ContentUnavailableView(
                            filter == .favorites ? "Aucun favori" : "Rien ici",
                            systemImage: kind.systemImage,
                            description: Text(filter == .favorites
                                ? "Appui long sur une affiche pour l'ajouter."
                                : "Cette playlist ne contient pas de \(kind.unit).")
                        )
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(kind.title)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationDestination(for: MediaItem.self) { SeriesDetailView(series: $0) }
        }
    }
}
