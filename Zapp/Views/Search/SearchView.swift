import SwiftUI

struct SearchView: View {
    @Environment(Library.self) private var library
    @State private var query = ""
    @State private var results: [MediaKind: [MediaItem]] = [:]

    private let maxPerSection = 60

    var body: some View {
        NavigationStack {
            List {
                ForEach(MediaKind.allCases) { kind in
                    let found = results[kind] ?? []
                    if !found.isEmpty {
                        let shown = Array(found.prefix(maxPerSection))
                        Section {
                            ForEach(shown) { item in
                                MediaButton(item: item, context: shown) {
                                    ChannelRow(item: item)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(.white.opacity(0.08))
                            }
                        } header: {
                            Text("\(kind.title) · \(found.count.formatted())")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle("Recherche")
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Chaînes, films, séries, catégories"
            )
            .autocorrectionDisabled()
            .task(id: query) {
                // Petit délai pour ne pas relancer la recherche à chaque lettre.
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let found = await library.search(query)
                guard !Task.isCancelled else { return }
                results = found
            }
            .overlay { emptyState }
            .mediaDestinations()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 2 {
            ContentUnavailableView(
                "Rechercher",
                systemImage: "magnifyingglass",
                description: Text("Tape au moins 2 lettres : nom de chaîne, film, série ou catégorie.")
            )
        } else if results.values.allSatisfy(\.isEmpty) {
            ContentUnavailableView.search(text: trimmed)
        }
    }
}
