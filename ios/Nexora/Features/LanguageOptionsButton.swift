import SwiftUI
import AVFoundation

private struct AvailableSource: Decodable { let languages: [String] }
struct LanguageOptionsButton: View {
    @ObservedObject var model: PlayerModel
    @EnvironmentObject var api: API
    @State private var open = false
    @State private var languages: [String] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        Button { open = true } label: { Label("Audio & subtitles", systemImage: "waveform") }
        .sheet(isPresented: $open) {
            NavigationStack {
                List {
                    Section {
                        Text("Source: Automatic").foregroundStyle(.secondary)
                        Text("Only tracks confirmed for this episode are shown. Switching keeps your playback position.").font(.caption)
                    }
                    if loading { ProgressView("Checking tracks…") }
                    ForEach(languages, id: \.self) { value in
                        Button {
                            Task { await change(value) }
                        } label: {
                            HStack {
                                Text(label(value)); Spacer()
                                if model.playback.source.language == value { Image(systemName: "checkmark") }
                            }
                        }.disabled(loading || model.busy)
                    }
                    if let error { Text(error).foregroundStyle(.secondary) }
                    if !loading && languages.isEmpty { Text("No additional tracks confirmed.") }
                    Button("Refresh availability") { Task { await load() } }.disabled(loading)
                }.navigationTitle("Language")
                .toolbar { Button("Done") { open = false } }
                .task { await load() }
            }.presentationDetents([.medium, .large])
        }
    }
    private func label(_ value: String) -> String {
        ["English":"English audio", "Deutsch":"German audio", "Eng-Sub":"English subtitles", "Ger-Sub":"German subtitles", "Original":"Original audio"][value] ?? value
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let data: CollectionResponse<AvailableSource> = try await api.request("/episode-options/\(model.playback.anime_id)/\(model.playback.episode_number)", web: true)
            languages = Array(Set(data.items.flatMap(\.languages))).sorted()
        } catch { self.error = error.localizedDescription }
    }
    private func change(_ language: String) async {
        loading = true; error = nil; defer { loading = false }
        let original = model.playback
        do {
            let next: Playback = try await api.request("/play", method: "POST", body: ["anime_id": original.anime_id, "episode": original.episode_number, "language": language, "provider": "auto", "quick": true])
            guard next.anime_id == original.anime_id, next.episode_number == original.episode_number, next.source.language == language else { throw APIError.message("The replacement did not match the selected track.") }
            guard model.playback.session_id == original.session_id else { return }
            let position = model.player.currentTime().seconds
            model.load(next, resumeAt: position.isFinite ? max(0, position) : original.resume_seconds)
            open = false
        } catch { self.error = error.localizedDescription }
    }
}
