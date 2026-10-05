import Combine
import Foundation

enum APIError: LocalizedError {
    case message(String)
    case http(Int, String)
    var errorDescription: String? { switch self { case .message(let text): return text; case .http(_, let text): return text } }
}
@MainActor final class API: ObservableObject {
    static let base = URL(string: "https://nexoraanime.duckdns.org")!
    static let supportURL = URL(string: "https://discord.com/invite/w6w4AxfUCT")!
    @Published var needsLanguageChoice = false
    @Published var account: Account? {
        didSet {
            if let account, let data = try? JSONEncoder().encode(account) { UserDefaults.standard.set(data, forKey: "offline-account") }
        }
    }
    var offlineOwner: String? {
        guard token != nil else { return nil }
        if let account { return account.id }
        guard let data = UserDefaults.standard.data(forKey: "offline-account") else { return nil }
        return (try? JSONDecoder().decode(Account.self, from: data))?.id
    }
    @Published var token: String? = Keychain.read()
    @Published var release: ReleaseInfo?
    @Published var checkingUpdate = false
    @Published var updateNotice: UpdateNotice?
    private var announcedBuild: Int?
    struct UpdateNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let url: URL?
    }
    private struct Runs: Decodable { let workflow_runs: [Run] }
    private struct Run: Decodable {
        let run_number: Int; let conclusion: String?; let path: String
        let html_url: String; let head_branch: String?
    }
    func checkForUpdates(manual: Bool = false) async {
        guard !checkingUpdate else { return }
        checkingUpdate = true; defer { checkingUpdate = false }
        do {
            // The public build feed reflects published builds even when server version settings lag behind.
            let url = URL(string: "https://api.github.com/repos/pawnsocks/nexoraios/actions/workflows/ios.yml/runs?branch=main&status=success&per_page=5")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Nexora-iOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.message("The update service could not be reached. Try again later.") }
            let runs = try JSONDecoder().decode(Runs.self, from: data)
            guard let latest = runs.workflow_runs.filter({ $0.head_branch == "main" && $0.conclusion == "success" && $0.path == ".github/workflows/ios.yml" }).max(by: { $0.run_number < $1.run_number }) else {
                throw APIError.message("No published build could be verified.")
            }
            let current = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
            if latest.run_number > current {
                if manual || announcedBuild != latest.run_number {
                    announcedBuild = latest.run_number
                    updateNotice = UpdateNotice(title: "Update available", message: "Build \(latest.run_number) is ready. Open the download page? Install the new IPA using your signing tool; keep the existing app installed.", url: URL(string: latest.html_url))
                }
            } else if manual {
                updateNotice = UpdateNotice(title: "Already up to date", message: "You have the latest successful build (\(current)).", url: nil)
            }
        } catch {
            if manual { updateNotice = UpdateNotice(title: "Update check failed", message: error.localizedDescription, url: nil) }
        }
    }
    private struct MediaAccess: Decodable { let url: String }
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 65
        config.timeoutIntervalForResource = 90
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true, web: Bool = false) async throws -> T {
        guard let url = URL(string: (web ? "/api/web" : "/api/mobile") + path, relativeTo: Self.base)?.absoluteURL else { throw APIError.message("Invalid request.") }
        var req = URLRequest(url: url)
        req.timeoutInterval = ["/me", "/version"].contains(path) ? 8 : 65
        req.httpMethod = method
        req.setValue(Self.base.absoluteString, forHTTPHeaderField: "Origin")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token else { throw APIError.message("Please log in.") }
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.message("Server unavailable.") }
        if http.statusCode == 401 && authenticated { clearSession() }
        guard (200..<300).contains(http.statusCode) else {
            let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = value?["detail"] as? [String: Any]
            if detail?["code"] as? String == "password_change_required" { account?.must_change_password = true }
            let message = (value?["error"] as? String) ?? (value?["detail"] as? String) ?? (detail?["message"] as? String)
            let reference = http.value(forHTTPHeaderField: "X-Nexora-Error-ID").map { " · Error ID: " + $0 } ?? ""
            throw APIError.http(http.statusCode, (message ?? "Request failed (\(http.statusCode)). Please try again.") + reference)
        }
        let decoded = try JSONDecoder().decode(T.self, from: data)
        if var playback = decoded as? Playback {
            let grant: MediaAccess
            do { grant = try await request("/media-access/" + playback.session_id, method: "POST", web: true) }
            catch APIError.http(404, _) { throw APIError.message("Install the Nexora server media/download update before using this app version.") }
            guard let url = URL(string: grant.url, relativeTo: Self.base)?.absoluteURL,
                  url.scheme == "https", url.host == Self.base.host,
                  url.path.hasPrefix("/api/playback/media/") else { throw APIError.message("The server returned an invalid media access link.") }
            playback.source.url = url.absoluteString
            return playback as! T
        }
        return decoded
    }
    func login(username: String, password: String) async throws {
        let result: LoginResponse = try await request("/auth/login", method: "POST", body: ["username": username, "password": password], authenticated: false)
        try Keychain.store(result.token)
        token = result.token; account = result.account
        await loadPreferences()
    }
    private struct Preferences: Decodable { let main_language: String? }
    func loadPreferences() async {
        guard token != nil, account?.must_change_password != true else { return }
        if let result: Preferences = try? await request("/preferences", web: true) {
            needsLanguageChoice = result.main_language == nil
            if let value = result.main_language { UserDefaults.standard.set(value, forKey: "preferredLanguage") }
        }
    }
    func savePreference(_ value: String) async throws {
        let result: Preferences = try await request("/preferences", method: "PUT", body: ["language": value], web: true)
        UserDefaults.standard.set(result.main_language ?? value, forKey: "preferredLanguage")
        needsLanguageChoice = false
    }
    func resolvePlayback(animeID: Int, episode: Int, preferred: String, excluding: Set<String> = []) async throws -> Playback {
        var last: Error = APIError.message("No remaining language could be played.")
        let owner = token
        for language in PlaybackLanguages.order(preferred).filter({ !excluding.contains($0) }) {
            try Task.checkCancellation()
            guard token == owner else { throw APIError.message("Your login changed. Try again.") }
            do {
                let result: Playback = try await request("/play", method: "POST", body: ["anime_id": animeID, "episode": episode, "language": language, "provider": "auto", "quick": true, "subtitle_fallback": false])
                guard result.anime_id == animeID, result.episode_number == episode, result.source.language == language else { throw APIError.message("The source did not match the requested episode and language.") }
                return result
            } catch APIError.http(let status, let message) {
                guard PlaybackLanguages.canRetry(status) else { throw APIError.http(status, message) }
                last = APIError.http(status, message)
            }
        }
        throw last
    }
    func clearSession() {
        needsLanguageChoice = false
        token = nil; account = nil; Keychain.clear()
        UserDefaults.standard.removeObject(forKey: "offline-account")
    }
    func changePassword(current: String, new: String) async throws {
        let _: OK = try await request("/security/password", method: "POST", body: ["current_password": current, "new_password": new], web: true)
        clearSession()
    }
    func logoutAll() async throws {
        let _: OK = try await request("/security/logout-all", method: "POST", web: true)
        clearSession()
    }
    func restore() async {
        async let info: ReleaseInfo? = try? request("/version", authenticated: false)
        if token != nil { account = try? await request("/me") }
        release = await info
        await loadPreferences()
    }
    func logout() async throws {
        let _: OK = try await request("/logout", method: "POST")
        clearSession()
    }
    func deleteAccount() async throws {
        let _: OK = try await request("/account", method: "DELETE")
        clearSession()
    }
}
