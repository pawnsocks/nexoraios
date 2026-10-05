import SwiftUI

private struct DirectoryRow: Decodable, Identifiable {
    let title: String
    let query: String?
    let id: Int?
}
private struct DirectoryResponse: Decodable {
    let items: [DirectoryRow]; let has_next: Bool; let coverage: String
}
struct AlphabetView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var search: SearchState
    @Environment(\.dismiss) private var dismiss
    @State private var letter = "ALL"
    @State private var page = 1
    @State private var data: DirectoryResponse?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Picker("Letter", selection: $letter) {
                    ForEach(["ALL", "#"] + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), id: \.self) { Text($0).tag($0) }
                }
                if let data { Text(data.coverage).font(.caption).foregroundStyle(.secondary) }
            }
            if let data {
                ForEach(Array(data.items.enumerated()), id: \.offset) { _, item in
                    if let id = item.id {
                        NavigationLink(item.title) { AnimeView(anime: Anime(id: id, title: item.title)) }
                    } else {
                        Button(item.title) { search.query = item.query ?? item.title; dismiss() }
                    }
                }
                HStack {
                    Button("Previous") { page -= 1 }.disabled(page == 1)
                    Spacer(); Text("Page \(page)").font(.caption); Spacer()
                    Button("Next") { page += 1 }.disabled(!data.has_next)
                }
            } else if error == nil { ProgressView() }
            if let error { Text(error).foregroundStyle(.secondary); Button("Retry") { Task { await load() } } }
        }.navigationTitle("Anime A–Z")
        .onChange(of: letter) { _, _ in page = 1 }
        .task(id: letter + String(page)) { await load() }
    }
    private func load() async {
        error = nil
        let requestedLetter = letter, requestedPage = page
        do {
            let result: DirectoryResponse = try await api.request("/alphabet?letter=\(letter == "#" ? "%23" : letter)&page=\(page)", web: true)
            try Task.checkCancellation()
            if letter == requestedLetter && page == requestedPage { data = result }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
