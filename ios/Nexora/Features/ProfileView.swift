import SwiftUI

struct ProfileStats: Decodable {
    let username: String
    let episodes: Int
    let anime_started: Int
    let anime_completed: Int
    let favorites: Int
}
struct ProfileView: View {
    @EnvironmentObject var api: API
    @State private var stats: ProfileStats?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(String((api.account?.username ?? "N").prefix(2)).uppercased())
                    .font(.system(size: 42, weight: .bold)).frame(width: 100, height: 100)
                    .background(.pink.gradient, in: Circle())
                Text(api.account?.username ?? "Profile").font(.largeTitle.bold())
                if let stats {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        metric("Episodes watched", stats.episodes)
                        metric("Anime started", stats.anime_started)
                        metric("Anime completed", stats.anime_completed)
                        metric("Favorites", stats.favorites)
                    }
                    Text("Each episode counts once, including episodes marked as watched. Seasons and movies count as separate catalogue entries. Previously deleted history cannot be recovered.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let error { ErrorCard(message: error) { Task { await load() } } }
                else { ProgressView() }
                NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }.padding(24)
        }.navigationTitle("Profile").task { await load() }.refreshable { await load() }
    }
    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 8) { Text(value.formatted()).font(.largeTitle.bold()); Text(label).font(.caption) }
            .frame(maxWidth: .infinity).padding(.vertical, 24).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
    private func load() async {
        do { stats = try await api.request("/profile"); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct GuideResponse: Decodable {
    let items: [GuideEntry]; let partial: Bool; let note: String
}
struct GuideEntry: Decodable, Identifiable {
    let id: Int; let title: String; let cover: String?; let format: String?; let relation: String
    let date: [String: Int?]
}
struct GuideView: View {
    let animeID: Int
    @EnvironmentObject var api: API
    @State private var guide: GuideResponse?
    @State private var error: String?
    var body: some View {
        List {
            if let guide {
                Section { Text(guide.note).font(.caption); if guide.partial { Text("Some related entries could not be loaded.").foregroundStyle(.secondary) } }
                ForEach(guide.items) { entry in
                    NavigationLink { AnimeView(anime: Anime(id: entry.id, title: entry.title, cover: entry.cover)) } label: {
                        HStack {
                            Artwork(url: entry.cover).frame(width: 48, height: 68).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.title).font(.headline)
                                Text([entry.format ?? "Anime", entry.relation.replacingOccurrences(of: "_", with: " ").capitalized].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if let error { ErrorCard(message: error) { Task { await load() } } }
            else { ProgressView("Loading watch guide…") }
        }.navigationTitle("Watch order").task { await load() }
    }
    private func load() async {
        do { guide = try await api.request("/anime/\(animeID)/guide"); error = nil } catch { self.error = error.localizedDescription }
    }
}
