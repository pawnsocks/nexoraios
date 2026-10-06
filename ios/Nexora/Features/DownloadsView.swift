import SwiftUI
import AVKit

private struct DownloadGroup: Identifiable {
    let id: String
    let title: String
    let episodes: [OfflineEpisode]
}

struct DownloadsView: View {
    @EnvironmentObject var downloads: DownloadStore
    @EnvironmentObject var api: API
    @State private var selected: OfflineEpisode?
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var pendingDeletion = Set<String>()
    private var owned: [OfflineEpisode] { downloads.items.filter { $0.owner == api.offlineOwner } }
    private var groups: [DownloadGroup] {
        Dictionary(grouping: owned) { item in
            item.animeID.map { "anime:\($0)" } ?? "title:\(item.title)"
        }.map { key, rows in
            DownloadGroup(id: key, title: rows.first?.title ?? "Anime", episodes: rows.sorted {
                if $0.episode != $1.episode { return $0.episode < $1.episode }
                if $0.language != $1.language { return $0.language < $1.language }
                return $0.id < $1.id
            })
        }.sorted { a, b in
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }
    var body: some View {
        List(selection: $selection) {
            if owned.isEmpty {
                ContentUnavailableView("Your offline episodes", systemImage: "arrow.down.circle", description: Text("Download episodes to keep them together here, sorted by anime and episode."))
            }
            Section("Queue") {
                Button(downloads.queuePaused ? "Resume queue" : "Pause queue") { downloads.setQueuePaused(!downloads.queuePaused) }
                NavigationLink("Manage download order") { DownloadQueueView() }
                if let message = downloads.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }.disabled(editMode.isEditing)
            ForEach(groups) { group in
                Section {
                    ForEach(group.episodes) { item in
                        episodeRow(item).tag(item.id)
                            .swipeActions {
                                Button("Delete", role: .destructive) { pendingDeletion = [item.id] }
                            }
                    }
                } header: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(group.title)
                            Text("\(group.episodes.count) episodes").font(.caption)
                        }
                        Spacer()
                        if editMode.isEditing {
                            Button(role: .destructive) { pendingDeletion = Set(group.episodes.map(\.id)) } label: {
                                Image(systemName: "trash")
                            }.accessibilityLabel("Delete all downloads for " + group.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    selection.removeAll()
                }.disabled(owned.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) {
                if editMode.isEditing {
                    Button("Delete selected (\(selection.count))", role: .destructive) { pendingDeletion = selection }
                        .disabled(selection.isEmpty)
                }
            }
        }
        .confirmationDialog("Delete \(pendingDeletion.count) downloaded episodes?", isPresented: Binding(
            get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion.removeAll() } }
        ), titleVisibility: .visible) {
            Button("Delete downloads", role: .destructive) {
                let ids = pendingDeletion
                for item in owned.filter({ ids.contains($0.id) }) { downloads.remove(item) }
                selection.subtract(ids); pendingDeletion.removeAll()
            }
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        } message: {
            Text("Saved videos will be removed from this iPhone. Queued or active downloads will be cancelled. Your online watch progress stays unchanged.")
        }
        .onAppear { downloads.bind(api) }
        .onChange(of: api.offlineOwner) { _, _ in selection.removeAll(); pendingDeletion.removeAll(); editMode = .inactive }
        .fullScreenCover(item: $selected) { item in
            if let location = item.location { OfflinePlayer(url: downloads.localURL(location), identity: item.id) }
        }
    }
    @ViewBuilder private func episodeRow(_ item: OfflineEpisode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Episode \(item.episode)").font(.headline)
            Text(item.language).font(.caption).foregroundStyle(.secondary)
            if item.id == downloads.preparingID { ProgressView("Preparing episode…") }
            else if let error = item.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                if !editMode.isEditing { Button("Retry") { downloads.retry(item) } }
            } else if item.location != nil && item.progress == 1 {
                if !editMode.isEditing {
                    Button("Play offline", systemImage: "play.fill") { selected = item }.buttonStyle(.borderedProminent)
                } else { Label("Downloaded", systemImage: "checkmark.circle").font(.caption) }
            } else if item.queued == true {
                Label("Queued", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(value: item.progress)
                Text("\(Int(item.progress * 100))% downloaded").font(.caption.monospacedDigit())
            }
        }.padding(.vertical, 8)
    }
}

private struct DownloadQueueView: View {
    @EnvironmentObject var downloads: DownloadStore
    @EnvironmentObject var api: API
    private var waiting: [OfflineEpisode] {
        downloads.items.filter { $0.owner == api.offlineOwner && $0.queued == true && $0.id != downloads.preparingID }
    }
    var body: some View {
        List {
            Text("One download at a time. Use Edit to change the download order.").font(.caption).foregroundStyle(.secondary)
            ForEach(waiting) { item in
                VStack(alignment: .leading) {
                    Text(item.title).font(.headline)
                    Text("Episode \(item.episode) · \(item.language)").font(.caption).foregroundStyle(.secondary)
                }
            }.onMove { from, to in downloads.moveQueued(from: from, to: to, owner: api.offlineOwner) }
             .onDelete { offsets in
                 let rows = waiting
                 for index in offsets { downloads.remove(rows[index]) }
             }
        }.navigationTitle("Download order").toolbar { EditButton() }
    }
}
struct OfflinePlayer: View {
    let url: URL
    let identity: String
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @EnvironmentObject var downloads: DownloadStore
    @State private var finished = false
    @State private var ended: NSObjectProtocol?
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player).ignoresSafeArea()
            Button { dismiss() } label: { Image(systemName: "xmark").padding(14).background(.ultraThinMaterial, in: Circle()) }.padding(20)
        }.onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                Task { @MainActor in finished = true }
            }
            player.seek(to: CMTime(seconds: UserDefaults.standard.double(forKey: "offline-position-" + identity), preferredTimescale: 600))
            player.play()
        }.onDisappear {
            let position = player.currentTime().seconds
            if position.isFinite { UserDefaults.standard.set(position, forKey: "offline-position-" + identity) }
            player.pause(); player.replaceCurrentItem(with: nil)
            if let ended { NotificationCenter.default.removeObserver(ended) }
            if finished { downloads.removeWatched(identity: identity) }
        }
    }
}
