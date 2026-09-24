import SwiftUI

struct AnimeView: View {
    let anime: Anime
    @EnvironmentObject var api: API
    @EnvironmentObject var downloads: DownloadStore
    @State private var undoToken: String?
    @State private var undoDeadline = Date.distantPast
    @State private var suggestions: [Anime] = []
    @State private var watched: [Int: EpisodeStatus] = [:]
    @State private var statusAvailable = false
    @State private var confirmAll = false
    @State private var allWatched = true
    @State private var editingEpisode: Int?
    @State private var editing = false
    @State private var minutes = "0"
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
    @State private var downloadCandidate: Playback?
    @State private var showBatchDownloads = false
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
                NavigationLink { GuideView(animeID: anime.id) } label: { Label("Watch order", systemImage: "list.number") }.buttonStyle(.bordered)
                if let token = undoToken {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if context.date < undoDeadline {
                            HStack {
                                Text("Saved change").font(.subheadline)
                                Spacer()
                                Button("Undo") { Task { await undo(token) } }.disabled(busy || favoriteBusy)
                            }.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                if !seasons.isEmpty {
                    Picker("Season / Part", selection: $selected) { ForEach(seasons) { season in Text(season.label).tag(season.id) } }.pickerStyle(.menu)
                }
                Button("Download season / anime", systemImage: "arrow.down.to.line") { showBatchDownloads = true }.buttonStyle(.bordered)
                HStack { Text("Episodes").font(.title2.bold()); Spacer(); if busy { ProgressView() } }
                Menu("Watch status") {
                    Button("Mark selected season as watched") { allWatched = true; confirmAll = true }
                    Button("Reset selected season", role: .destructive) { allWatched = false; confirmAll = true }
                }.buttonStyle(.bordered).disabled(busy || !statusAvailable || unknown)
                if unknown { Text("Episode information is temporarily unavailable.").foregroundStyle(.secondary) }
                ForEach(episodes) { episode in
                    HStack {
                    Button { Task { await play(episode.id) } } label: {
                        HStack { Text(String(format: "%02d", episode.id)).font(.title3.monospacedDigit()).foregroundStyle(.secondary); Text(episode.title).font(.headline); if watched[episode.id]?.watched == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }; Spacer(); Image(systemName: "play.circle.fill").font(.title2) }.padding().background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).disabled(busy)
                    Button { Task { await download(episode.id) } } label: {
                        Image(systemName: "arrow.down.circle").font(.title2).frame(width: 44, height: 44)
                    }.accessibilityLabel("Download episode \(episode.id)").disabled(busy)
                    Menu {
                        Button(watched[episode.id]?.watched == true ? "Mark as unwatched" : "Mark as watched") {
                            Task { await changeStatus(episode: episode.id, complete: !(watched[episode.id]?.watched ?? false)) }
                        }
                        Button("Correct progress") {
                            editingEpisode = episode.id
                            minutes = String(format: "%.1f", (watched[episode.id]?.position ?? 0) / 60)
                            editing = true
                        }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 36, height: 44) }
                    .disabled(busy || !statusAvailable)
                    }
                }
                if let message = downloads.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    if page > 1 { Button("Previous 50") { page -= 1; Task { await loadEpisodes() } } }
                    Spacer()
                    if hasNext { Button("Next 50") { page += 1; Task { await loadEpisodes() } } }
                }
                if !suggestions.isEmpty {
                    Text("Picked for you").font(.title2.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(suggestions) { item in
                                NavigationLink { AnimeView(anime: item) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Artwork(url: item.cover).frame(width: 130, height: 180).clipShape(RoundedRectangle(cornerRadius: 14))
                                        Text(item.title).font(.subheadline.bold()).lineLimit(2).frame(width: 130, alignment: .leading)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
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
            if let home: HomeData = try? await api.request("/home") {
                suggestions = await Recommendations.shared.forYou(api: api, catalogue: home, excluding: anime.id)
            }
        }
        .task(id: selected) { if selected > 0 { page = 1; await loadEpisodes() } }
        .confirmationDialog(allWatched ? "Mark every known episode of the selected season as watched?" : "Reset all saved progress for the selected season?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button(allWatched ? "Mark as watched" : "Reset progress", role: allWatched ? nil : .destructive) { Task { await changeStatus(episode: nil, complete: allWatched) } }
        }
        .alert("Correct progress", isPresented: $editing) {
            TextField("Minutes", text: $minutes).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let episode = editingEpisode, let value = Double(minutes.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0, value <= 1440 {
                    Task { await changeStatus(episode: episode, complete: false, position: value * 60) }
                } else { error = "Enter a valid time in minutes." }
            }
        } message: { Text("Set the resume time in minutes. Use 0 to reset this episode.") }
        .sheet(isPresented: $showBatchDownloads) { BatchDownloadView(animeID: anime.id, initialPartID: selected == 0 ? anime.id : selected) }
        .sheet(item: $downloadCandidate) { DownloadOptionsView(playback: $0) }
        .fullScreenCover(item: $playback, onDismiss: { Task { await loadStatus() } }) { PlayerView(initial: $0) }
    }
    func loadEpisodes() async {
        do {
            let result: EpisodesResponse = try await api.request("/anime/\(selected)/episodes?page=\(page)")
            episodes = result.items; hasNext = result.has_next; unknown = result.unknown; error = nil
            await loadStatus()
        } catch { self.error = error.localizedDescription }
    }
    func loadStatus() async {
        let selectedID = selected
        let selectedPage = page
        do {
            let result: CollectionResponse<EpisodeStatus> = try await api.request("/anime/\(selectedID)/watched?page=\(selectedPage)")
            guard selected == selectedID && page == selectedPage else { return }
            watched = Dictionary(uniqueKeysWithValues: result.items.map { ($0.id, $0) }); statusAvailable = true
        } catch { watched = [:]; statusAvailable = false }
    }
    func changeStatus(episode: Int?, complete: Bool, position: Double = 0) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        var body: [String: Any] = ["watched": complete, "position": position]
        if let episode { body["episode"] = episode }
        if position > 0, let episode, let duration = watched[episode]?.duration { body["duration"] = duration }
        do {
            let result: UndoResponse = try await api.request("/anime/\(selected)/watched", method: "PUT", body: body)
            undoToken = result.undo_token; undoDeadline = Date().addingTimeInterval(120)
            await loadStatus(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    func play(_ episode: Int) async {
        busy = true; error = nil; defer { busy = false }
        do { playback = try await api.request("/play", method: "POST", body: ["anime_id": selected == 0 ? anime.id : selected, "episode": episode, "language": language]) }
        catch { self.error = error.localizedDescription }
    }
    func download(_ episode: Int) async {
        busy = true; defer { busy = false }
        do {
            let source: Playback = try await api.request("/play", method: "POST", body: ["anime_id": selected == 0 ? anime.id : selected, "episode": episode, "language": language])
            downloadCandidate = source
        } catch { self.error = error.localizedDescription }
    }
    func undo(_ token: String) async {
        guard !busy, !favoriteBusy else { return }
        busy = true; defer { busy = false }
        do {
            let _: OK = try await api.request("/undo", method: "POST", body: ["token": token])
            undoToken = nil
            await loadStatus()
            let result: CollectionResponse<Anime> = try await api.request("/library/favorites")
            favorite = result.items.contains { $0.id == anime.id }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func toggleFavorite() async {
        favoriteBusy = true; defer { favoriteBusy = false }
        do {
            if favorite {
                let result: UndoResponse = try await api.request("/favorites/\(anime.id)/remove", method: "POST")
                undoToken = result.undo_token; undoDeadline = Date().addingTimeInterval(120)
            } else {
                let _: OK = try await api.request("/favorites/\(anime.id)", method: "PUT")
                undoToken = nil
            }
            favorite.toggle()
        }
        catch { self.error = error.localizedDescription }
    }
}
