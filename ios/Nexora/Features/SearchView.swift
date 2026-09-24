import SwiftUI
import Combine

@MainActor final class SearchState: ObservableObject {
    @Published var query = ""
    @Published var results: [Anime] = []
    var loadedQuery = ""
}


struct SearchView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var search: SearchState
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.secondary) }
            ForEach(search.results) { anime in
                NavigationLink { AnimeView(anime: anime) } label: { AnimeRow(anime: anime) }
            }
            if search.query.count >= 2 && search.results.isEmpty && !loading && error == nil { Text("No matching anime.").foregroundStyle(.secondary) }
        }.navigationTitle("Search").searchable(text: $search.query, prompt: "Titles in any language")
        .task(id: search.query) {
            guard search.query.count >= 2 else { search.results = []; loading = false; return }
            guard search.loadedQuery != search.query || search.results.isEmpty else { return }
            loading = true; error = nil
            do {
                try await Task.sleep(for: .milliseconds(400))
                var parts = URLComponents(); parts.queryItems = [URLQueryItem(name: "q", value: search.query)]
                let response: CollectionResponse<Anime> = try await api.request("/search?" + (parts.percentEncodedQuery ?? ""))
                try Task.checkCancellation(); search.results = response.items; search.loadedQuery = search.query; loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}
struct AnimeRow: View {
    let anime: Anime
    @EnvironmentObject var api: API
    @State private var fetchedCover: String?
    var body: some View {
        HStack(spacing: 14) {
            Artwork(url: anime.cover ?? fetchedCover).frame(width: 58, height: 80).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(anime.title).font(.headline)
                Text([anime.year.map(String.init), anime.format].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if let episode = anime.episode { Text("Episode \(episode)").font(.caption).foregroundStyle(.pink) }
            }
        }.padding(.vertical, 4)
        .task(id: anime.id) {
            guard anime.cover == nil else { return }
            let detail: Anime? = try? await api.request("/anime/\(anime.id)")
            if !Task.isCancelled { fetchedCover = detail?.cover }
        }
    }
}
