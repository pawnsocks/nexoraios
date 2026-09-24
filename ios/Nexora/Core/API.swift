import Combine
import Foundation

enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
@MainActor final class API: ObservableObject {
    static let base = URL(string: "https://nexoradc.duckdns.org")!
    @Published var account: Account?
    @Published var token: String? = Keychain.read()
    @Published var release: ReleaseInfo?
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
