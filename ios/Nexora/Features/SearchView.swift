import SwiftUI

struct SearchView: View {
    @EnvironmentObject var api: API
    @State private var query = ""
    @State private var results: [Anime] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.secondary) }
            ForEach(results) { anime in
                NavigationLink { AnimeView(anime: anime) } label: { AnimeRow(anime: anime) }
            }
            if query.count >= 2 && results.isEmpty && !loading && error == nil { Text("No matching anime.").foregroundStyle(.secondary) }
        }.navigationTitle("Search").searchable(text: $query, prompt: "Titles in any language")
        .task(id: query) {
            guard query.count >= 2 else { results = []; loading = false; return }
            loading = true; error = nil
            do {
                try await Task.sleep(for: .milliseconds(400))
                var parts = URLComponents(); parts.queryItems = [URLQueryItem(name: "q", value: query)]
                let response: CollectionResponse<Anime> = try await api.request("/search?" + (parts.percentEncodedQuery ?? ""))
                try Task.checkCancellation(); results = response.items; loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}
struct AnimeRow: View {
    let anime: Anime
    var body: some View {
        HStack(spacing: 14) {
            Artwork(url: anime.cover).frame(width: 58, height: 80).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(anime.title).font(.headline)
                Text([anime.year.map(String.init), anime.format].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if let episode = anime.episode { Text("Episode \(episode)").font(.caption).foregroundStyle(.pink) }
            }
        }.padding(.vertical, 4)
    }
}
