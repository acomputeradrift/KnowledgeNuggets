import Foundation

final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "http://localhost:4000")!
    private var token: String? = nil

    func setToken(_ token: String) {
        self.token = token.isEmpty ? nil : token
    }

    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            urlRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode < 300 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func requestEmpty(_ path: String, method: String = "POST", body: Data? = nil) async throws {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            urlRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode < 300 else {
            throw URLError(.badServerResponse)
        }
    }

    struct LoginResponse: Decodable { let token: String }
    struct RegisterResponse: Decodable { let id: String; let email: String }
    struct LoginRequest: Encodable { let email: String; let password: String }
    struct RegisterRequest: Encodable { let email: String; let password: String }
    struct NuggetRequest: Encodable {
        let text: String
        let author_name: String?
        let book_title: String?
        let category: String?
        let active: Bool
    }
    struct NuggetUpdateRequest: Encodable {
        let text: String?
        let author_name: String?
        let book_title: String?
        let category: String?
        let active: Bool?
    }
    struct SettingsRequest: Encodable {
        let send_time_local: String
        let timezone: String
        let marketplace: String
        let send_push: Bool
        let send_email: Bool
    }
    struct DeviceRequest: Encodable { let device_token: String }

    func login(email: String, password: String) async throws -> String {
        let payload = try JSONEncoder().encode(LoginRequest(email: email, password: password))
        let result: LoginResponse = try await request("auth/login", method: "POST", body: payload)
        return result.token
    }

    func register(email: String, password: String) async throws {
        let payload = try JSONEncoder().encode(RegisterRequest(email: email, password: password))
        let _: RegisterResponse = try await request("auth/register", method: "POST", body: payload)
    }

    func fetchNuggets() async throws -> [Nugget] {
        return try await request("nuggets")
    }

    func createNugget(_ nugget: Nugget) async throws -> Nugget {
        let payload = try JSONEncoder().encode(NuggetRequest(
            text: nugget.text,
            author_name: nugget.authorName,
            book_title: nugget.bookTitle,
            category: nugget.category,
            active: nugget.active
        ))
        return try await request("nuggets", method: "POST", body: payload)
    }

    func updateNugget(_ nugget: Nugget, original: Nugget) async throws -> Nugget {
        let payload = try JSONEncoder().encode(NuggetUpdateRequest(
            text: nugget.text,
            author_name: nugget.authorName ?? (original.authorName == nil ? nil : ""),
            book_title: nugget.bookTitle ?? (original.bookTitle == nil ? nil : ""),
            category: nugget.category ?? (original.category == nil ? nil : ""),
            active: nugget.active
        ))
        return try await request("nuggets/\(nugget.id)", method: "PUT", body: payload)
    }

    func fetchSettings() async throws -> UserSettings {
        return try await request("settings")
    }

    func updateSettings(_ settings: UserSettings) async throws -> UserSettings {
        let payload = try JSONEncoder().encode(SettingsRequest(
            send_time_local: settings.sendTimeLocal,
            timezone: settings.timezone,
            marketplace: settings.marketplace,
            send_push: settings.sendPush,
            send_email: settings.sendEmail
        ))
        return try await request("settings", method: "PUT", body: payload)
    }

    func registerDevice(token: String) async throws {
        let payload = try JSONEncoder().encode(DeviceRequest(device_token: token))
        try await requestEmpty("devices/register", method: "POST", body: payload)
    }
}
