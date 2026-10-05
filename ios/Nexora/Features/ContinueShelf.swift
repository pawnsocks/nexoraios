import SwiftUI

struct ContinueShelf: View {
    let items: [Anime]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Continue today").font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in ContinueCard(anime: item) }
                }
            }
        }
    }
}
private struct ContinueCard: View {
    let anime: Anime
    @EnvironmentObject var api: API
    @AppStorage("preferredLanguage") private var language = "Deutsch"
    @State private var playback: Playback?
    @State private var busy = false
    @State private var error: String?
    private var progress: Double { guard let d = anime.duration, d > 0 else { return 0 }; return min(1, max(0, (anime.position ?? 0) / d)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AnimeArtwork(anime: anime).frame(width: 234, height: 150).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                Button { resume() } label: {
                    Group { if busy { ProgressView() } else { Image(systemName: "play.fill") } }
                        .frame(width: 46, height: 46).background(.pink, in: Circle()).padding(12)
                }.buttonStyle(.plain).disabled(busy).accessibilityLabel("Resume " + anime.title)
            }.clipShape(RoundedRectangle(cornerRadius: 18))
            NavigationLink { AnimeView(anime: anime) } label: { Text(anime.title).font(.headline).lineLimit(1) }.buttonStyle(.plain)
            Text("Episode \(anime.episode ?? 1) · \(Int((anime.position ?? 0) / 60)) min").font(.caption).foregroundStyle(.secondary)
            ProgressView(value: progress).tint(.pink)
        }.frame(width: 234)
        .fullScreenCover(item: $playback) { PlayerView(initial: $0) }
        .alert("Could not resume", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func resume() {
        busy = true
        Task {
            defer { busy = false }
            do { playback = try await api.resolvePlayback(animeID: anime.id, episode: anime.episode ?? 1, preferred: language) }
            catch { self.error = error.localizedDescription }
        }
    }
}
