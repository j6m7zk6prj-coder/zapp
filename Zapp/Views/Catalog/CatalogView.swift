import SwiftUI

/// Grille de films ou de séries, filtrable par catégorie.
struct CatalogView: View {
    let kind: MediaKind
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @State private var filter: CategoryFilter = .all

    var body: some View {
        let items = filter.apply(to: library.all(kind), favoriteIDs: favorites.ids)

        NavigationStack {
            VStack(spacing: 0) {
                CategoryChips(groups: library.groups(of: kind), selection: $filter)
                ScrollView {
                    MediaGrid(items: items)
                        .padding(.top, 4)
                }
                .overlay {
                    if items.isEmpty && !library.isLoading {
                        ContentUnavailableView(
                            filter == .favorites ? "Aucun favori" : "Rien ici",
                            systemImage: kind.systemImage,
                            description: Text(filter == .favorites
                                ? "Appui long sur une affiche pour l'ajouter."
                                : "Aucun contenu de type « \(kind.title) » pour l'instant.")
                        )
                    }
                }
            }
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle(kind.title)
            .mediaDestinations()
        }
    }
}
