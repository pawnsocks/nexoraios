import Combine
import Foundation

enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
@MainActor final class API: ObservableObject {
    static let base = URL(string: "https://nexoradc.duckdns.org")!
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
                    updateNotice = UpdateNotice(title: "Update available", message: "Build \(latest.run_number) is ready. Open the download page? Install the new IPA with Xenora on your computer; keep the existing app installed.", url: URL(string: latest.html_url))
                }
            } else if manual {
                updateNotice = UpdateNotice(title: "Already up to date", message: "You have the latest successful build (\(current)).", url: nil)
            }
        } catch {
            if manual { updateNotice = UpdateNotice(title: "Update check failed", message: error.localizedDescription, url: nil) }
        }
    }
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 65
        config.timeoutIntervalForResource = 90
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true) async throws -> T {
        guard let url = URL(string: "/api/mobile" + path, relativeTo: Self.base)?.absoluteURL else { throw APIError.message("Invalid request.") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token else { throw APIError.message("Please log in.") }
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.message("Server unavailable.") }
        if http.statusCode == 401 && authenticated { token = nil; account = nil; Keychain.clear() }
        guard (200..<300).contains(http.statusCode) else {
            let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (value?["error"] as? String) ?? (value?["detail"] as? String)
            throw APIError.message(message ?? "Request failed (\(http.statusCode)). Please try again.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func login(username: String, password: String, register: Bool) async throws {
        let result: LoginResponse = try await request(register ? "/auth/register" : "/auth/login", method: "POST", body: ["username": username, "password": password], authenticated: false)
        try Keychain.store(result.token)
        token = result.token; account = result.account
    }
    func restore() async {
        release = try? await request("/version", authenticated: false)
        if token != nil { account = try? await request("/me") }
    }
    func logout() async throws {
        let _: OK = try await request("/logout", method: "POST")
        token = nil; account = nil; Keychain.clear()
    }
    func deleteAccount() async throws {
        let _: OK = try await request("/account", method: "DELETE")
        token = nil; account = nil; Keychain.clear()
    }
}
