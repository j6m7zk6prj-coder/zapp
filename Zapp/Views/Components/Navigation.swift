import SwiftUI

/// Une chaîne se lance directement (avec zapping), le reste ouvre sa fiche.
struct MediaButton<Content: View>: View {
    let item: MediaItem
    let context: [MediaItem]
    let content: Content
    @Environment(Router.self) private var router

    init(item: MediaItem, context: [MediaItem], @ViewBuilder content: () -> Content) {
        self.item = item
        self.context = context
        self.content = content()
    }

    var body: some View {
        if item.kind == .live {
            Button {
                router.play(item, context: context)
            } label: {
                content
            }
            .buttonStyle(CardButtonStyle())
        } else {
            NavigationLink(value: item) { content }
                .buttonStyle(CardButtonStyle())
        }
    }
}

/// Filtre des catégories (puces horizontales).
enum CategoryFilter: Hashable {
    case all
    case favorites
    case group(String)

    func apply(to items: [MediaItem], favoriteIDs: Set<String>) -> [MediaItem] {
        switch self {
        case .all: return items
        case .favorites: return items.filter { favoriteIDs.contains($0.id) }
        case .group(let name): return items.filter { $0.group == name }
        }
    }
}

struct CategoryChips: View {
    let groups: [String]
    @Binding var selection: CategoryFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                chip("Tout", value: .all)
                chip("Favoris", value: .favorites, icon: "heart.fill")
                ForEach(groups, id: \.self) { group in
                    chip(group, value: .group(group))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(height: 58)
    }

    private func chip(_ title: String, value: CategoryFilter, icon: String? = nil) -> some View {
        let isSelected = selection == value
        return Button {
            withAnimation(.snappy) { selection = value }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.caption2)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(.white)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                }
            }
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}

/// Rangée horizontale façon Apple TV, avec lien « Tout voir ».
struct Shelf: View {
    let title: String
    let items: [MediaItem]
    var style: TileStyle = .auto
    var route: BrowseRoute?
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        MediaButton(item: item, context: items) {
                            MediaTile(item: item, style: style, width: tileWidth(for: item))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    @ViewBuilder
    private var header: some View {
        if let route {
            NavigationLink(value: route) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        } else {
            Text(title)
                .font(.title3.weight(.bold))
        }
    }

    private func tileWidth(for item: MediaItem) -> CGFloat {
        let landscape: Bool
        switch style {
        case .landscape: landscape = true
        case .poster: landscape = false
        case .auto: landscape = item.kind == .live
        }
        return landscape ? settings.posterSize.width * 1.6 : settings.posterSize.width
    }
}

/// Grille réutilisable (onglets Films/Séries, « Tout voir »).
struct MediaGrid: View {
    let items: [MediaItem]
    @Environment(AppSettings.self) private var settings

    private var allLive: Bool { !items.isEmpty && items.allSatisfy { $0.kind == .live } }

    var body: some View {
        let minimum = allLive ? settings.posterSize.width * 1.35 : settings.posterSize.width - 6
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 14)], spacing: 20) {
            ForEach(items) { item in
                MediaButton(item: item, context: items) {
                    MediaTile(item: item)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 28)
    }
}

/// Écran « Tout voir ».
struct BrowseGridView: View {
    let route: BrowseRoute
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites

    private var items: [MediaItem] {
        switch route {
        case .kind(let kind): return library.all(kind)
        case .favorites: return library.lookup(favorites.ids)
        case .customLinks: return library.customLinkItems
        case .group(let kind, let name): return library.all(kind).filter { $0.group == name }
        }
    }

    var body: some View {
        let list = items
        ScrollView {
            MediaGrid(items: list)
                .padding(.top, 8)
        }
        .overlay {
            if list.isEmpty {
                ContentUnavailableView("Rien ici", systemImage: "square.grid.2x2")
            }
        }
        .background(Theme.backdrop.ignoresSafeArea())
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.large)
        .tabBarSpacing()
    }
}
