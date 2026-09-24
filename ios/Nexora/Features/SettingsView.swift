import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var network: Connectivity
    @EnvironmentObject var downloads: DownloadStore
    @AppStorage("downloadLimitGB") private var limit = 5
    @AppStorage("downloadAutoDelete") private var autoDelete = true
    @AppStorage("preferredLanguage") private var language = "Deutsch"
    @AppStorage("autoNext") private var autoNext = true
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var working = false
    @State private var cleared = false
    var body: some View {
        Form {
            Section("Account") { Text(api.account?.username ?? "Nexora account") }
            Section("Playback") {
                Picker("Preferred language", selection: $language) {
                    Text("Deutsch").tag("Deutsch")
                    Text("English audio").tag("English")
                    Text("German subtitles").tag("Ger-Sub")
                    Text("English subtitles").tag("Eng-Sub")
                    Text("Original audio").tag("Original")
                }
                Toggle("Autoplay next episode", isOn: $autoNext)
                Text("A preference does not guarantee availability for every episode.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Downloads") {
                Text("Choose a network for each download. Mobile data always requires confirmation.").font(.caption).foregroundStyle(.secondary)
                Picker("Storage limit", selection: $limit) {
                    ForEach([1, 2, 5, 10, 20, 50], id: \.self) { Text("\($0) GB").tag($0) }
                }.onChange(of: limit) { _, _ in downloads.applyPolicy() }
                Toggle("Delete after watching", isOn: $autoDelete)
                Text("Used: \(ByteCountFormatter.string(fromByteCount: downloads.usedBytes, countStyle: .file))").font(.caption)
                Text("Applies to downloads on this iPhone. Finished episodes are deleted after playback closes or advances. iOS temporary downloads may briefly exceed the limit.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Storage") {
                Button(cleared ? "Image cache cleared" : "Clear image cache") { Task { await ArtworkCache.shared.clear(); cleared = true } }
            }
            Section("Nexora") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                LabeledContent("Network", value: network.online ? "Online" : "Offline")
                UpdateBanner()
                Link(destination: URL(string: "https://discord.gg/BU5xTMu9QE")!) {
                    Label("Support Discord", systemImage: "bubble.left.and.bubble.right")
                }
                Button(api.checkingUpdate ? "Checking…" : "Check for updates") { Task { await api.checkForUpdates(manual: true) } }.disabled(api.checkingUpdate)
            }
            Section {
                Button("Log out") { perform { try await api.logout() } }.disabled(working)
                Button("Delete account", role: .destructive) { confirmDelete = true }.disabled(working)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Settings").onAppear { downloads.refreshUsage() }
        .confirmationDialog("Delete your account and saved progress? This cannot be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { perform { try await api.deleteAccount() } }
        }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        working = true
        Task { defer { working = false }; do { try await action() } catch { self.error = error.localizedDescription } }
    }
}
