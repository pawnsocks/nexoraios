import SwiftUI

struct DownloadRequest {
    let animeID: Int
    let title: String
    let episode: Int
    let language: String
}
struct DownloadPart: Identifiable {
    let id: Int
    let title: String
    let count: Int?
}
struct BatchDownloadView: View {
    let animeID: Int
    let initialPartID: Int
    @EnvironmentObject var api: API
    @EnvironmentObject var downloads: DownloadStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferredLanguage") private var language = "Deutsch"
    @State private var parts: [DownloadPart] = []
    @State private var selection = Set<Int>()
    @State private var loading = true
    @State private var error: String?
    @State private var confirmMobile = false
    private var count: Int { parts.filter { selection.contains($0.id) }.reduce(0) { $0 + ($1.count ?? 0) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose complete seasons or all listed parts. Only confirmed released episodes are added; future releases are not downloaded automatically.").font(.caption)
                    Picker("Language", selection: $language) {
                        Text("Deutsch").tag("Deutsch")
                        Text("English audio").tag("English")
                        Text("German subtitles").tag("Ger-Sub")
                        Text("English subtitles").tag("Eng-Sub")
                        Text("Original audio").tag("Original")
                    }
                    Text("Language availability is checked for each episode when its download starts.").font(.caption).foregroundStyle(.secondary)
                }
                if loading { ProgressView("Loading seasons…") }
                if let error { ErrorCard(message: error) { Task { await load() } } }
                if !parts.isEmpty {
                    Section("Seasons and parts") {
                        Button("Select all parts") { selection = Set(parts.filter { ($0.count ?? 0) > 0 }.map(\.id)) }
                        Button("Clear selection") { selection.removeAll() }
                        ForEach(parts) { part in
                            Toggle(isOn: Binding(get: { selection.contains(part.id) }, set: { value in
                                if value { selection.insert(part.id) } else { selection.remove(part.id) }
                            })) {
                                VStack(alignment: .leading) {
                                    Text(part.title)
                                    Text(part.count.map { "\($0) released episodes" } ?? "Released episode count unavailable")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.disabled((part.count ?? 0) == 0)
                        }
                    }
                    Section("Add \(count) episodes to queue") {
                        Button("Queue using Wi-Fi only") { enqueue(cellular: false) }.disabled(count == 0 || loading)
                        Button("Queue with mobile data allowed") { confirmMobile = true }.disabled(count == 0 || loading)
                        Text("Downloads run one at a time. Reorder waiting episodes in Downloads. Already queued or downloaded episodes are skipped.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("Download anime").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Allow mobile data for \(count) episodes?", isPresented: $confirmMobile) {
                Button("Cancel", role: .cancel) {}
                Button("Yes, queue downloads") { enqueue(cellular: true) }
            } message: { Text("A whole anime can use many gigabytes. This permission applies to every selected episode, including downloads that continue after Wi-Fi disconnects. Are you sure?") }
            .task { await load() }
        }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let response: CollectionResponse<Season> = try await api.request("/anime/\(animeID)/seasons")
            var entries = response.items
            if !entries.contains(where: { $0.id == animeID }) { entries.insert(Season(id: animeID, title: "Selected anime", label: "Selected anime"), at: 0) }
            var loaded: [DownloadPart] = []
            var seen = Set<Int>()
            for entry in entries where seen.insert(entry.id).inserted {
                try Task.checkCancellation()
                let detail: Anime = try await api.request("/anime/\(entry.id)")
                let count = DownloadQueuePolicy.releasedCount(status: detail.status, total: detail.episodes, aired: detail.aired_episodes)
                loaded.append(DownloadPart(id: detail.id, title: detail.title, count: count))
            }
            parts = loaded
            selection = Set(loaded.filter { $0.id == initialPartID && ($0.count ?? 0) > 0 }.map(\.id))
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func enqueue(cellular: Bool) {
        guard count <= 20_000 else { error = "Select fewer than 20,001 episodes per queue."; return }
        let requests = parts.filter { selection.contains($0.id) }.flatMap { part -> [DownloadRequest] in
            guard let count = part.count, count > 0 else { return [] }
            return (1...count).map { DownloadRequest(animeID: part.id, title: part.title, episode: $0, language: language) }
        }
        if downloads.enqueue(requests, owner: api.offlineOwner, allowCellular: cellular) { dismiss() }
        else { error = downloads.message }
    }
}
