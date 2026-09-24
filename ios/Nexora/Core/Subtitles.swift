import SwiftUI
import AVFoundation

/// Renders only selectable text tracks. Burned-in captions remain part of the video.
@MainActor final class SubtitleRenderer: NSObject, ObservableObject, AVPlayerItemLegibleOutputPushDelegate {
    @Published var text = ""
    @Published var tracks: [AVMediaSelectionOption] = []
    @Published var selected = -1
    private weak var item: AVPlayerItem?
    private weak var player: AVPlayer?
    private var group: AVMediaSelectionGroup?
    private var output: AVPlayerItemLegibleOutput?
    private var clock: Any?
    private var events: [(Double, String)] = []
    func attach(_ item: AVPlayerItem, player: AVPlayer) {
        detach(); self.item = item; self.player = player
        let output = AVPlayerItemLegibleOutput()
        output.suppressesPlayerRendering = false
        output.advanceIntervalForDelegateInvocation = 5
        output.setDelegate(self, queue: .main)
        item.add(output); self.output = output
        clock = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.render(time.seconds) }
        }
        Task {
            do {
                let group = try await item.asset.loadMediaSelectionGroup(for: .legible)
                guard self.item === item else { return }
                self.group = group; self.tracks = group?.options.filter { $0.mediaType == .subtitle || $0.mediaType == .text } ?? []
                output.suppressesPlayerRendering = !self.tracks.isEmpty
                if let group, let active = item.currentMediaSelection.selectedMediaOption(in: group), let index = self.tracks.firstIndex(of: active) { self.selected = index }
            } catch { /* No editable subtitle track. */ }
        }
    }
    func select(_ index: Int) {
        guard let item, let group else { return }
        clear(); selected = index
        item.select(tracks.indices.contains(index) ? tracks[index] : nil, in: group)
    }
    func clear() { events.removeAll(); text = "" }
    func legibleOutput(_ output: AVPlayerItemLegibleOutput, didOutputAttributedStrings strings: [NSAttributedString], nativeSampleBuffers: [Any], forItemTime itemTime: CMTime) {
        guard output === self.output else { return }
        let time = itemTime.seconds
        guard time.isFinite else { return }
        events.append((time, strings.map(\.string).joined(separator: "\n")))
        events.sort { $0.0 < $1.0 }
        if events.count > 300 { events.removeFirst(events.count - 300) }
    }
    func outputSequenceWasFlushed(_ output: AVPlayerItemOutput) { clear() }
    private func render(_ now: Double) {
        guard now.isFinite else { return }
        let offset = min(5, max(-5, UserDefaults.standard.double(forKey: "subtitleOffset")))
        let target = now - offset
        text = events.last(where: { $0.0 <= target })?.1 ?? ""
        // Retain enough past events to change the offset while paused or playing.
        while events.count > 1 && events[1].0 < now - 15 { events.removeFirst() }
    }
    func detach() {
        if let clock, let player { player.removeTimeObserver(clock) }; clock = nil
        if let output, let item { item.remove(output) }; output = nil
        item = nil; player = nil; group = nil; tracks = []; selected = -1; clear()
    }
}
struct SubtitleOverlay: View {
    @ObservedObject var subtitles: SubtitleRenderer
    @AppStorage("subtitleSize") private var size = 22.0
    @AppStorage("subtitleBackground") private var background = 0.65
    var body: some View {
        VStack {
            Spacer()
            if !subtitles.text.isEmpty {
                Text(subtitles.text).font(.system(size: size, weight: .medium))
                    .multilineTextAlignment(.center).foregroundStyle(.white)
                    .padding(8).background(.black.opacity(background), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 24).padding(.bottom, 48)
            }
        }.allowsHitTesting(false)
    }
}
struct SubtitleSettings: View {
    @ObservedObject var subtitles: SubtitleRenderer
    @AppStorage("subtitleSize") private var size = 22.0
    @AppStorage("subtitleBackground") private var background = 0.65
    @AppStorage("subtitleOffset") private var offset = 0.0
    var body: some View {
        Form {
            if subtitles.tracks.isEmpty {
                Text("This stream has no editable text subtitle track. Captions embedded in the picture cannot be changed.")
            } else {
                Picker("Subtitle track", selection: Binding(get: { subtitles.selected }, set: { subtitles.select($0) })) {
                    Text("Off").tag(-1)
                    ForEach(subtitles.tracks.indices, id: \.self) { index in Text(subtitles.tracks[index].displayName).tag(index) }
                }
                Section("Appearance") {
                    LabeledContent("Font size", value: "\(Int(size))")
                    Slider(value: $size, in: 14...40, step: 1)
                    LabeledContent("Background", value: "\(Int(background * 100))%")
                    Slider(value: $background, in: 0...1, step: 0.05)
                    Text("Subtitle preview").font(.system(size: size)).foregroundStyle(.white).padding(8).background(.black.opacity(background))
                }
                Section("Timing") {
                    Text(String(format: "%+.1f seconds", offset))
                    Slider(value: $offset, in: -5...5, step: 0.1)
                    Text("Positive = later, negative = earlier. Earlier display depends on the stream providing captions ahead of playback.").font(.caption)
                    Button("Reset timing") { offset = 0 }
                }
            }
        }.navigationTitle("Subtitles")
    }
}
