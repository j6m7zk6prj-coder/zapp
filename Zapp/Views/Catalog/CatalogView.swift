import SwiftUI

/// Films ou séries : tendances, catégories en pastilles, grille d'affiches.
struct CatalogView: View {
    let kind: MediaKind
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @Environment(MetadataStore.self) private var metadata
    @State private var filter: CategoryFilter = .all

    var body: some View {
        let items = filter.apply(to: library.all(kind), favoriteIDs: favorites.ids)
        let trending = metadata.trending.filter { $0.item.kind == kind }.map { $0.item }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    (Text(kind == .movie ? "Le cinéma, " : "Les séries, ") + Text(kind == .movie ? "chez toi." : "sans fin.").accentSerif(size: 34))
                        .font(.system(size: 34, weight: .bold))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if filter == .all && !trending.isEmpty {
                        Shelf(title: "Tendances cette semaine", items: Array(trending.prefix(20)), style: .poster)
                    }

                    CategoryChips(groups: library.groups(of: kind), selection: $filter)

                    if items.isEmpty && !library.isLoading {
                        ContentUnavailableView(
                            filter == .favorites ? "Aucun favori" : "Rien ici",
                            systemImage: kind.systemImage,
                            description: Text(filter == .favorites
                                ? "Appui long sur une affiche pour l'ajouter."
                                : "Aucun contenu de type « \(kind.title) » pour l'instant.")
                        )
                        .padding(.top, 30)
                    } else {
                        MediaGrid(items: items)
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(AmbientBackground(tint: kind == .movie ? Color(hex: 0xBF5AF2) : Color(hex: 0xFF375F)))
            .toolbar(.hidden, for: .navigationBar)
            .tabBarSpacing()
            .mediaDestinations()
        }
    }
}
