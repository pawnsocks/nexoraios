import SwiftUI

struct HomeView: View {
    @EnvironmentObject var api: API
    @State private var home: HomeData?
    @State private var continuing: [Anime] = []
    @State private var error: String?
    @State private var day = Date()
    private var days: [Date] { (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                UpdateBanner()
                if let home {
                    if let featured = home.airing.first ?? home.popular.first {
                        NavigationLink { AnimeView(anime: featured) } label: {
                            ZStack(alignment: .bottomLeading) {
                                Artwork(url: featured.banner ?? featured.cover).frame(height: 390)
                                LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("IN THE SPOTLIGHT").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.pink)
                                    Text(featured.title).font(.largeTitle.bold()).multilineTextAlignment(.leading)
                                    Text((featured.genres ?? []).prefix(3).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                                    Label("Explore episodes", systemImage: "play.fill").font(.headline).padding(12).background(.white, in: Capsule()).foregroundStyle(.black)
                                }.padding(24)
                            }.clipShape(RoundedRectangle(cornerRadius: 26))
                        }.buttonStyle(.plain)
                    }
                    if !continuing.isEmpty { AnimeShelf(title: "Continue watching", items: continuing) }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("This week").font(.title2.bold()); Spacer(); Text("Release calendar").font(.caption).foregroundStyle(.secondary) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(days, id: \.self) { date in
                                    Button { day = date } label: {
                                        VStack(spacing: 8) { Text(date.formatted(.dateTime.weekday(.abbreviated))); Text(date.formatted(.dateTime.day())).font(.title3.bold()) }
                                            .frame(width: 54).padding(.vertical, 12)
                                            .background(Calendar.current.isDate(date, inSameDayAs: day) ? Color.pink.opacity(0.65) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        let entries = home.calendar.filter { Calendar.current.isDate(Date(timeIntervalSince1970: Double($0.airing_at)), inSameDayAs: day) }
                        if entries.isEmpty { Text("No scheduled releases for this day.").foregroundStyle(.secondary).padding(.vertical) }
                        ForEach(entries) { entry in
                            NavigationLink { AnimeView(anime: entry.anime) } label: {
                                HStack(spacing: 14) {
                                    Artwork(url: entry.anime.cover).frame(width: 55, height: 76).clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.anime.title).font(.headline).lineLimit(2)
                                        Text("Episode \(entry.episode)").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: Double(entry.airing_at)), style: .time).font(.subheadline.monospacedDigit()).foregroundStyle(.pink)
                                }.padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                        Text(home.calendar_note).font(.caption).foregroundStyle(.secondary)
                    }
                    AnimeShelf(title: "Coming soon", items: home.upcoming)
                    AnimeShelf(title: "Currently airing", items: home.airing)
                    AnimeShelf(title: "Popular", items: home.popular)
                } else if error == nil { ProgressView().frame(maxWidth: .infinity).padding(80) }
                if let error { ErrorCard(message: error) { Task { await load() } } }
            }.padding(.horizontal, 18).padding(.bottom, 30)
        }.background(Color(red: 0.035, green: 0.045, blue: 0.06))
        .navigationTitle("Nexora").toolbar { NavigationLink { SettingsView() } label: { Image(systemName: "person.crop.circle") } }
        .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        error = nil
        do { home = try await api.request("/home") } catch { self.error = error.localizedDescription }
        let list: CollectionResponse<Anime>? = try? await api.request("/library/continue")
        continuing = list?.items ?? []
    }
}
struct AnimeShelf: View {
    let title: String
    let items: [Anime]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { anime in
                        NavigationLink { AnimeView(anime: anime) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Artwork(url: anime.cover).frame(width: 128, height: 182).clipShape(RoundedRectangle(cornerRadius: 16))
                                Text(anime.title).font(.subheadline.weight(.medium)).lineLimit(2).frame(width: 128, alignment: .leading)
                                if let episode = anime.episode { Text("Episode \(episode)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
struct ErrorCard: View {
    let message: String
    let retry: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: 12) { Text(message).foregroundStyle(.secondary); Button("Try again", action: retry) }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16)) }
}
struct UpdateBanner: View {
    @EnvironmentObject var api: API
    private let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    var body: some View {
        if let release = api.release, release.latest.compare(current, options: .numeric) == .orderedDescending {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nexora \(release.latest) is available").font(.headline)
                if !release.notes.isEmpty { Text(release.notes).font(.caption).foregroundStyle(.secondary) }
                if let value = release.url, let url = URL(string: value), url.scheme == "https" { Link("Get update", destination: url) }
                else { Text("Install the latest signed release to update.").font(.caption) }
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
