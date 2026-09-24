import SwiftUI
import AVKit

@MainActor final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var playback: Playback
    @Published var error: String?
    @Published var busy = false
    private var observer: NSKeyValueObservation?
    private var periodic: Any?
    private var ended: NSObjectProtocol?
    private var playState: NSKeyValueObservation?
    private var saving = false
    private var loaded = false
    private var api: API?
    var autoNext = true
    var preferredLanguage = "Deutsch"
    init(_ initial: Playback) { playback = initial }
    func start(_ api: API) {
        guard !loaded else { return }; loaded = true; self.api = api
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        load(playback)
        periodic = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 20, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.save() }
        }
        playState = player.observe(\.timeControlStatus) { [weak self] player, _ in
            if player.timeControlStatus == .paused { Task { @MainActor in await self?.save() } }
        }
    }
    func load(_ value: Playback) {
        error = nil
        guard let url = URL(string: value.source.url, relativeTo: API.base)?.absoluteURL, url.scheme == "https" else { error = "Invalid video URL."; return }
        observer?.invalidate()
        if let ended { NotificationCenter.default.removeObserver(ended) }
        playback = value
        let item = AVPlayerItem(url: url)
        observer = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed { self.error = "Video could not be loaded. Try refreshing its source." }
                if item.status == .readyToPlay {
                    if let resume = value.resume_seconds, resume > 0 { self.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) }
                    self.player.play()
                }
            }
        }
        ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.save(completed: true)
                if self.autoNext && self.playback.has_next { await self.step(1) }
            }
        }
        player.replaceCurrentItem(with: item)
    }
    func seek(_ delta: Double) {
        let now = player.currentTime().seconds
        guard now.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, now + delta), preferredTimescale: 600))
    }
    func save(completed: Bool = false) async {
        guard let api, !saving else { return }
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        guard position.isFinite, duration.isFinite, duration > 0, position >= 5 else { return }
        saving = true; defer { saving = false }
        do {
            let _: OK = try await api.request("/play/\(playback.session_id)/progress", method: "POST", body: ["position": min(position, duration), "duration": duration, "ended": completed])
        } catch { self.error = "Your progress could not be saved. Check your connection." }
    }
    func step(_ delta: Int) async {
        guard let api, !busy else { return }; busy = true; defer { busy = false }
        await save(); player.pause()
        do {
            let result: Playback = try await api.request("/play", method: "POST", body: ["anime_id": playback.anime_id, "episode": playback.episode_number + delta, "language": playback.source.language ?? preferredLanguage])
            load(result)
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard let api, !busy else { return }; busy = true; defer { busy = false }
        await save(); player.pause()
        do { let result: Playback = try await api.request("/play/\(playback.session_id)/refresh", method: "POST"); load(result) }
        catch { self.error = error.localizedDescription }
    }
    func stop() async {
        await save(); player.pause(); observer?.invalidate(); playState?.invalidate()
        if let periodic { player.removeTimeObserver(periodic); self.periodic = nil }
        if let ended { NotificationCenter.default.removeObserver(ended); self.ended = nil }
    }
}
struct PlayerView: View {
    @EnvironmentObject var api: API
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var phase
    @AppStorage("autoNext") private var autoNext = true
    @AppStorage("preferredLanguage") private var language = "Deutsch"
    @StateObject private var model: PlayerModel
    init(initial: Playback) { _model = StateObject(wrappedValue: PlayerModel(initial)) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoPlayer(player: model.player).frame(maxHeight: .infinity)
                Text("Episode \(model.playback.episode_number)").font(.headline)
                HStack(spacing: 24) {
                    Button { Task { await model.step(-1) } } label: { Image(systemName: "backward.end.fill") }.disabled(!model.playback.has_prev || model.busy)
                    Button { model.seek(-10) } label: { Image(systemName: "gobackward.10") }
                    Button { model.seek(10) } label: { Image(systemName: "goforward.10") }
                    Button { Task { await model.step(1) } } label: { Image(systemName: "forward.end.fill") }.disabled(!model.playback.has_next || model.busy)
                }.font(.title2).padding()
                if model.busy { ProgressView("Loading episode…") }
                if let error = model.error { Text(error).font(.callout).foregroundStyle(.secondary).padding(.horizontal) }
                Button("Reload source") { Task { await model.refresh() } }.disabled(model.busy).padding(.bottom)
            }.navigationTitle(model.playback.anime_title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { Task { await model.stop(); dismiss() } } } }
        }.task { model.autoNext = autoNext; model.preferredLanguage = language; model.start(api) }
        .onChange(of: phase) { _, value in if value != .active { model.player.pause(); Task { await model.save() } } }
        .onDisappear { Task { await model.stop() } }
    }
}
