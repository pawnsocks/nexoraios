import SwiftUI

struct MainLanguageView: View {
    @EnvironmentObject var api: API
    @State private var language = "English"
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("MAKE IT YOURS").font(.caption).tracking(3).foregroundStyle(.pink)
            Text("What is your\nmain language?").font(.largeTitle.bold())
            Text("We try your preferred audio first, then subtitles in that language. If neither works, we try another language and show you which one is playing.").foregroundStyle(.secondary)
            Picker("Main language", selection: $language) { Text("English").tag("English"); Text("Deutsch").tag("Deutsch") }.pickerStyle(.segmented)
            if let error { Text(error).foregroundStyle(.red) }
            Button(busy ? "Saving…" : "Save and continue") {
                busy = true
                Task { defer { busy = false }; do { try await api.savePreference(language) } catch { self.error = error.localizedDescription } }
            }.buttonStyle(.borderedProminent).disabled(busy)
            Text("Saved to your account. You can change this in Settings.").font(.caption).foregroundStyle(.secondary)
            Button("Log out") { api.clearSession() }.disabled(busy)
        }.padding(28)
    }
}
