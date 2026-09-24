import SwiftUI
import AVKit

@MainActor final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    let subtitles = SubtitleRenderer()
    @Published var playback: Playback
    @Published var error: String?
    @Published var busy = false
    private var stallTask: Task<Void, Never>?
    private var recoveryClock: Any?
    private var lastGoodTime: Double = 0
    private var prepareStarted = Date()
    private var failedToEnd: NSObjectProtocol?
    private var waitingSince: Date?
    private var failedProviders = Set<String>()
    private var repairAttempts = 0
    private var closed = false
    private var preparing = false
    @Published var repairing = false
    var didFinish: ((Int, Int) -> Void)?
    private var observer: NSKeyValueObservation?
    private var periodic: Any?
    private var ended: NSObjectProtocol?
    private var playState: NSKeyValueObservation?
    private var saving = false
    private var loaded = false
    private var finished = false
    private var api: API?
    var autoNext = true
    var preferredLanguage = "Deutsch"
    init(_ initial: Playback) { playback = initial }
    func start(_ api: API) {
        guard !loaded else { return }; loaded = true; self.api = api
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        load(playback)
        recoveryClock = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.closed, !self.preparing else { return }
                if self.player.timeControlStatus == .playing, time.seconds.isFinite { self.lastGoodTime = time.seconds }
            }
        }
        periodic = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 20, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.save() }
        }
        stallTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, !self.closed else { return }
                if self.preparing && Date().timeIntervalSince(self.prepareStarted) > 30 && !self.busy {
                    self.preparing = false; await self.repair()
                }
                if self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate && !self.repairing && !self.preparing {
                    if let since = self.waitingSince, Date().timeIntervalSince(since) >= 15 { await self.repair() }
                    else if self.waitingSince == nil { self.waitingSince = Date() }
                } else { self.waitingSince = nil }
            }
        }
        playState = player.observe(\.timeControlStatus) { [weak self] player, _ in
            if player.timeControlStatus == .paused { Task { @MainActor in await self?.save() } }
        }
    }
    func load(_ value: Playback, resumeAt: Double? = nil) {
        error = nil
        guard let url = URL(string: value.source.url, relativeTo: API.base)?.absoluteURL, url.scheme == "https" else { error = "Invalid video URL."; return }
        observer?.invalidate()
        if let ended { NotificationCenter.default.removeObserver(ended) }
        if let failedToEnd { NotificationCenter.default.removeObserver(failedToEnd) }
        if value.anime_id != playback.anime_id || value.episode_number != playback.episode_number {
            failedProviders.removeAll(); repairAttempts = 0
        }
        playback = value; finished = false; preparing = true
        prepareStarted = Date(); lastGoodTime = resumeAt ?? value.resume_seconds ?? 0
        waitingSince = nil
        let item = AVPlayerItem(url: url)
        observer = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, !self.closed, self.player.currentItem === item else { return }
                if item.status == .failed { self.preparing = false; await self.repair() }
                if item.status == .readyToPlay {
                    let resume = resumeAt ?? value.resume_seconds ?? 0
                    let duration = item.duration.seconds
                    if resume > 0, duration.isFinite, resume >= duration {
                        self.preparing = false
                        self.error = "The replacement video is shorter than your saved position. Playback was stopped."
                        return
                    }
                    if resume > 0 {
                        self.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] success in
                            Task { @MainActor in
                                guard let self, !self.closed, self.player.currentItem === item else { return }
                                self.preparing = false
                                if success { self.lastGoodTime = resume; self.player.play() }
                                else { self.error = "Could not restore your playback position. Try another source." }
                            }
                        }
                    } else { self.preparing = false; self.player.play() }
                }
            }
        }
        ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.finished = true
                self.didFinish?(self.playback.anime_id, self.playback.episode_number)
                await self.save(completed: true)
                if self.autoNext && self.playback.has_next { await self.step(1) }
            }
        }
        failedToEnd = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                await self.repair()
            }
        }
        player.replaceCurrentItem(with: item)
        subtitles.attach(item, player: player)
    }
    func repair() async {
        guard let api, !closed, !busy, !repairing, !finished else { return }
        guard repairAttempts < 3, let language = playback.source.language else {
            error = "No replacement source is available. Your position has been kept."; return
        }
        let current = player.currentTime().seconds
        let position = current.isFinite && current > 0 ? current : lastGoodTime
        lastGoodTime = position
        if let id = playback.source.id { failedProviders.insert(id) }
        repairAttempts += 1; repairing = true; busy = true
        error = "Restoring playback at " + String(format: "%d:%02d", Int(position) / 60, Int(position) % 60) + "…"
        player.pause()
        let original = playback
        do {
            let replacement: Playback = try await api.request("/play/\(original.session_id)/repair", method: "POST", body: ["language": language, "excluded": Array(failedProviders)])
            guard !closed else { busy = false; repairing = false; return }
            guard replacement.anime_id == original.anime_id, replacement.episode_number == original.episode_number, replacement.source.language == language else {
                throw NSError(domain: "Nexora", code: 1, userInfo: [NSLocalizedDescriptionKey: "Replacement did not match the episode and language."])
            }
            busy = false; repairing = false
            load(replacement, resumeAt: position)
        } catch {
            busy = false; repairing = false
            if !closed { self.error = "Automatic repair failed. Your position is kept. " + error.localizedDescription }
        }
    }
    func seek(_ delta: Double) {
        let now = player.currentTime().seconds
        guard now.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, now + delta), preferredTimescale: 600))
    }
    func save(completed: Bool = false) async {
        guard let api, !saving, !preparing else { return }
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        guard position.isFinite, duration.isFinite, duration > 0, position >= 5 else { return }
        saving = true; defer { saving = false }
        do {
            let _: OK = try await api.request("/play/\(playback.session_id)/progress", method: "POST", body: ["position": min(position, duration), "duration": duration, "ended": completed || finished])
        } catch { self.error = "Your progress could not be saved. Check your connection." }
    }
    func step(_ delta: Int) async {
        guard delta > 0 ? playback.has_next : playback.has_prev else { return }
        guard let api, !busy else { return }; busy = true; defer { busy = false }
        await save(); player.pause()
        do {
            let result: Playback = try await api.request("/play", method: "POST", body: ["anime_id": playback.anime_id, "episode": playback.episode_number + delta, "language": playback.source.language ?? preferredLanguage])
            if !closed { load(result) }
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard let api, !busy else { return }; busy = true; defer { busy = false }
        await save(); player.pause()
        let current = player.currentTime().seconds
        let position = current.isFinite && current > 0 ? current : lastGoodTime
        do { let result: Playback = try await api.request("/play/\(playback.session_id)/refresh", method: "POST"); if !closed { load(result, resumeAt: position) } }
        catch { self.error = error.localizedDescription }
    }
    func stop() async {
        closed = true; stallTask?.cancel(); stallTask = nil
        if let recoveryClock { player.removeTimeObserver(recoveryClock); self.recoveryClock = nil }
        await save(); player.pause(); subtitles.detach(); observer?.invalidate(); playState?.invalidate()
        if let periodic { player.removeTimeObserver(periodic); self.periodic = nil }
        if let ended { NotificationCenter.default.removeObserver(ended); self.ended = nil }
        if let failedToEnd { NotificationCenter.default.removeObserver(failedToEnd); self.failedToEnd = nil }
    }
}
struct PlayerView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var downloads: DownloadStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var phase
    @AppStorage("autoNext") private var autoNext = true
    @AppStorage("preferredLanguage") private var language = "Deutsch"
    @StateObject private var model: PlayerModel
    @State private var showControls = true
    @State private var showSubtitles = false
    @State private var downloadCandidate: Playback?
    init(initial: Playback) { _model = StateObject(wrappedValue: PlayerModel(initial)) }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if landscape {
                    VideoPlayer(player: model.player).overlay { SubtitleOverlay(subtitles: model.subtitles) }.ignoresSafeArea()
                    VStack {
                        header
                        Spacer()
                        if showControls { controls.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 60) }
                    }.padding(.vertical, 12)
                } else {
                    VStack(spacing: 20) {
                        header
                        VideoPlayer(player: model.player).overlay { SubtitleOverlay(subtitles: model.subtitles) }
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.playback.anime_title).font(.title2.bold())
                            Text("Episode \(model.playback.episode_number)").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                        controls.padding(20).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .task { model.autoNext = autoNext; model.preferredLanguage = language; model.didFinish = { anime, episode in downloads.removeWatched(anime: anime, episode: episode, owner: api.offlineOwner) }; model.start(api) }
        .onChange(of: autoNext) { _, value in model.autoNext = value }
        .onChange(of: phase) { _, value in if value != .active { Task { await model.save() } } }
        .onDisappear { Task { await model.stop() } }
        .sheet(item: $downloadCandidate) { DownloadOptionsView(playback: $0) }
        .sheet(isPresented: $showSubtitles) { NavigationStack { SubtitleSettings(subtitles: model.subtitles).toolbar { Button("Done") { showSubtitles = false } } } }
    }
    private var header: some View {
        HStack {
            Button { Task { await model.stop(); dismiss() } } label: { Image(systemName: "xmark").frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle()) }
            Spacer()
            Button { showControls.toggle() } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle()) }
        }.foregroundStyle(.white).padding(.horizontal, 20)
    }
    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                Button { Task { await model.step(-1) } } label: { Image(systemName: "backward.end.fill") }.disabled(!model.playback.has_prev || model.busy)
                Button { model.seek(-10) } label: { Image(systemName: "gobackward.10") }
                Spacer()
                Button { Task { await model.step(1) } } label: { Label("Next episode", systemImage: "forward.end.fill").font(.subheadline.bold()) }.buttonStyle(.borderedProminent).disabled(!model.playback.has_next || model.busy)
                Spacer()
                Button { model.seek(10) } label: { Image(systemName: "goforward.10") }
            }.font(.title2).frame(minHeight: 44)
            HStack {
                Toggle("Autoplay", isOn: $autoNext).fixedSize().font(.caption)
                Spacer()
                Button { downloadCandidate = model.playback } label: { Label("Download", systemImage: "arrow.down.circle") }.buttonStyle(.bordered)
                Menu {
                    Button("Subtitles") { showSubtitles = true }
                    Button("Try another source") { Task { await model.repair() } }
                    Button("Reload source") { Task { await model.refresh() } }
                } label: { Image(systemName: "ellipsis.circle").font(.title2) }
            }
            if model.busy { ProgressView("Loading episode…") }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if let message = downloads.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
