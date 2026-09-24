import SwiftUI
import AVKit

struct DownloadsView: View {
    @EnvironmentObject var downloads: DownloadStore
    @EnvironmentObject var api: API
    @State private var selected: OfflineEpisode?
    private var owned: [OfflineEpisode] { downloads.items.filter { $0.owner == api.offlineOwner } }
    private var waiting: [OfflineEpisode] { owned.filter { $0.queued == true && $0.id != downloads.preparingID } }
    private var activeAndSaved: [OfflineEpisode] { owned.filter { $0.queued != true || $0.id == downloads.preparingID } }
    var body: some View {
        List {
            if owned.isEmpty {
                ContentUnavailableView("Your offline episodes", systemImage: "arrow.down.circle", description: Text("Tap Download in the player to save an episode on this iPhone."))
            }
            Section("Queue") {
                Button(downloads.queuePaused ? "Resume queue" : "Pause queue") { downloads.setQueuePaused(!downloads.queuePaused) }
                Text("\(waiting.count) waiting · one download at a time").font(.caption).foregroundStyle(.secondary)
                Text("Pause stops new downloads; the current one continues. Reopen Nexora if the queue waits in the background.").font(.caption).foregroundStyle(.secondary)
                if let message = downloads.message { Text(message).font(.caption) }
                ForEach(waiting) { item in
                    VStack(alignment: .leading) {
                        Text(item.title).font(.headline)
                        Text("Episode \(item.episode) · \(item.language) · \(item.wifiOnly == true ? "Wi-Fi" : "Mobile data allowed")").font(.caption).foregroundStyle(.secondary)
                    }.swipeActions { Button("Remove", role: .destructive) { downloads.remove(item) } }
                }.onMove { from, to in downloads.moveQueued(from: from, to: to, owner: api.offlineOwner) }
            }
            ForEach(activeAndSaved) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title).font(.headline)
                    Text("Episode \(item.episode) · \(item.language)").font(.caption).foregroundStyle(.secondary)
                    if item.id == downloads.preparingID { ProgressView("Preparing episode…") }
                    else if item.location != nil && item.progress == 1 {
                        Button("Play offline", systemImage: "play.fill") { selected = item }.buttonStyle(.borderedProminent)
                    } else if let error = item.error { Text(error).font(.caption).foregroundStyle(.secondary); Button("Retry") { downloads.retry(item); downloads.setQueuePaused(false) } }
                    else { ProgressView(value: item.progress); Text("\(Int(item.progress * 100))% downloaded").font(.caption.monospacedDigit()) }
                }.padding(.vertical, 8)
                .swipeActions { Button("Delete", role: .destructive) { downloads.remove(item) } }
            }
        }.navigationTitle("Downloads")
        .toolbar { EditButton() }
        .onAppear { downloads.bind(api) }
        .fullScreenCover(item: $selected) { item in
            if let location = item.location { OfflinePlayer(url: downloads.localURL(location), identity: item.id) }
        }
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
