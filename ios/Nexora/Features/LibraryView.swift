import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var api: API
    @State private var kind = "favorites"
    @State private var items: [Anime] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            Picker("Collection", selection: $kind) { Text("Favorites").tag("favorites"); Text("Continue").tag("continue"); Text("History").tag("history") }.pickerStyle(.segmented)
            if loading { ProgressView() }
            if let error { ErrorCard(message: error) { Task { await load() } } }
            ForEach(items) { anime in NavigationLink { AnimeView(anime: anime) } label: { AnimeRow(anime: anime) } }
            if items.isEmpty && !loading && error == nil { Text(kind == "favorites" ? "Save an anime to watch it later." : "Start watching to see your anime here.").foregroundStyle(.secondary) }
        }.navigationTitle("My List").task(id: kind) { await load() }.refreshable { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { let response: CollectionResponse<Anime> = try await api.request("/library/\(kind)"); items = response.items }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
