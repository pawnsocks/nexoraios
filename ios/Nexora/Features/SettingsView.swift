import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var network: Connectivity
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
                Button("Check for updates") { Task { await api.restore() } }
            }
            Section {
                Button("Log out") { perform { try await api.logout() } }.disabled(working)
                Button("Delete account", role: .destructive) { confirmDelete = true }.disabled(working)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Settings")
        .confirmationDialog("Delete your account and saved progress? This cannot be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { perform { try await api.deleteAccount() } }
        }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        working = true
        Task { defer { working = false }; do { try await action() } catch { self.error = error.localizedDescription } }
    }
}
