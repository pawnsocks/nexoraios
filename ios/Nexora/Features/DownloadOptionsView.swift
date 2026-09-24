import SwiftUI

struct DownloadOptionsView: View {
    let playback: Playback
    @EnvironmentObject var downloads: DownloadStore
    @EnvironmentObject var api: API
    @Environment(\.dismiss) private var dismiss
    @State private var confirmMobile = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(playback.anime_title).font(.headline)
                Text("Episode \(playback.episode_number)").foregroundStyle(.secondary)
                Button { start(cellular: false) } label: {
                    Label("Wi-Fi only", systemImage: "wifi").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button { confirmMobile = true } label: {
                    Label("Allow mobile data", systemImage: "antenna.radiowaves.left.and.right").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Text("Wi-Fi downloads wait for a suitable connection. Allowing mobile data also permits the download to continue if Wi-Fi disconnects.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
            .navigationTitle("Download using")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Download using mobile data?", isPresented: $confirmMobile) {
                Button("Cancel", role: .cancel) {}
                Button("Yes, download") { start(cellular: true) }
            } message: {
                Text("This episode may use a large amount of mobile data and count toward your data allowance. Its exact size is not always known. Are you sure?")
            }
        }.presentationDetents([.medium, .large])
    }
    private func start(cellular: Bool) {
        downloads.add(playback, owner: api.offlineOwner, allowCellular: cellular)
        dismiss()
    }
}
