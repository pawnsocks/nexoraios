import SwiftUI

@main struct NexoraApp: App {
    @UIApplicationDelegateAdaptor(DownloadAppDelegate.self) private var appDelegate
    @StateObject private var api = API()
    @StateObject private var network = Connectivity()
    @StateObject private var search = SearchState()
    @StateObject private var downloads = DownloadStore.shared
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(api).environmentObject(network).environmentObject(search).environmentObject(downloads)
                .task(id: api.token) { downloads.bind(api) }
                .preferredColorScheme(.dark).tint(Color(red: 0.97, green: 0.34, blue: 0.48))
        }
    }
}
struct RootView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var api: API
    @EnvironmentObject var network: Connectivity
    @State private var launching = true
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.06).ignoresSafeArea()
            if launching {
                VStack(spacing: 18) {
                    Image("Brand").resizable().scaledToFit().frame(width: 130, height: 130).clipShape(RoundedRectangle(cornerRadius: 28))
                    Text("NEXORA").font(.headline).tracking(7)
                }.transition(.opacity)
            } else if api.token == nil { AuthView() }
            else { MainView() }
        }
        .task {
            async let restore: Void = api.restore()
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { launching = false }
            await restore
            await api.checkForUpdates()
        }
        .alert(item: $api.updateNotice) { notice in
            if let url = notice.url {
                return Alert(title: Text(notice.title), message: Text(notice.message), primaryButton: .default(Text("Open update")) { openURL(url) }, secondaryButton: .cancel(Text("Later")))
            }
            return Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .onChange(of: network.online) { _, online in if online { Task { await api.restore() } } }
    }
}
struct MainView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "house") }
            NavigationStack { SearchView() }.tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { LibraryView() }.tabItem { Label("My List", systemImage: "bookmark") }
            NavigationStack { ProfileView() }.tabItem { Label("Profile", systemImage: "person.crop.circle") }
            NavigationStack { DownloadsView() }.tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
        }
    }
}
