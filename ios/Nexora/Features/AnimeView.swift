import SwiftUI

struct AnimeView: View {
    let anime: Anime
    @EnvironmentObject var api: API
    @AppStorage("preferredLanguage") private var language = "Deutsch"
    @State private var detail: Anime?
    @State private var seasons: [Season] = []
    @State private var selected = 0
    @State private var episodes: [Episode] = []
    @State private var page = 1
    @State private var hasNext = false
    @State private var unknown = false
    @State private var busy = false
    @State private var favorite = false
    @State private var favoriteBusy = false
    @State private var error: String?
    @State private var playback: Playback?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Artwork(url: (detail ?? anime).banner ?? (detail ?? anime).cover).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 22))
                Text((detail ?? anime).title).font(.largeTitle.bold())
                Text((detail?.genres ?? []).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if let description = detail?.description { Text(description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)).font(.subheadline).foregroundStyle(.secondary) }
                HStack {
                    Button(favorite ? "Remove favorite" : "Favorite anime", systemImage: favorite ? "heart.fill" : "heart") { Task { await toggleFavorite() } }.buttonStyle(.bordered).disabled(favoriteBusy)
                    if anime.episode != nil { Button("Continue") { Task { await play(anime.episode ?? 1) } }.buttonStyle(.borderedProminent).disabled(busy) }
                }
                if !seasons.isEmpty {
                    Picker("Season / Part", selection: $selected) { ForEach(seasons) { season in Text(season.label).tag(season.id) } }.pickerStyle(.menu)
                }
                HStack { Text("Episodes").font(.title2.bold()); Spacer(); if busy { ProgressView() } }
                if unknown { Text("Episode information is temporarily unavailable.").foregroundStyle(.secondary) }
                ForEach(episodes) { episode in
                    Button { Task { await play(episode.id) } } label: {
                        HStack { Text(String(format: "%02d", episode.id)).font(.title3.monospacedDigit()).foregroundStyle(.secondary); Text(episode.title).font(.headline); Spacer(); Image(systemName: "play.circle.fill").font(.title2) }.padding().background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).disabled(busy)
                }
                HStack {
                    if page > 1 { Button("Previous 50") { page -= 1; Task { await loadEpisodes() } } }
                    Spacer()
                    if hasNext { Button("Next 50") { page += 1; Task { await loadEpisodes() } } }
                }
                if let error { ErrorCard(message: error) { Task { await loadEpisodes() } } }
            }.padding(20)
        }.navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                detail = try await api.request("/anime/\(anime.id)")
                let result: CollectionResponse<Season> = try await api.request("/anime/\(anime.id)/seasons")
                seasons = result.items; selected = anime.id
                let list: CollectionResponse<Anime> = try await api.request("/library/favorites")
                favorite = list.items.contains { $0.id == anime.id }
            } catch { self.error = error.localizedDescription }
            if selected == 0 { selected = anime.id }
        }
        .task(id: selected) { if selected > 0 { page = 1; await loadEpisodes() } }
        .fullScreenCover(item: $playback) { PlayerView(initial: $0) }
    }
    func loadEpisodes() async {
        do {
            let result: EpisodesResponse = try await api.request("/anime/\(selected)/episodes?page=\(page)")
            episodes = result.items; hasNext = result.has_next; unknown = result.unknown; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func play(_ episode: Int) async {
        busy = true; error = nil; defer { busy = false }
        do { playback = try await api.request("/play", method: "POST", body: ["anime_id": selected == 0 ? anime.id : selected, "episode": episode, "language": language]) }
        catch { self.error = error.localizedDescription }
    }
    func toggleFavorite() async {
        favoriteBusy = true; defer { favoriteBusy = false }
        do { let _: OK = try await api.request("/favorites/\(anime.id)", method: favorite ? "DELETE" : "PUT"); favorite.toggle() }
        catch { self.error = error.localizedDescription }
    }
}
