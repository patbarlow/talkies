import Foundation

struct PublicUser: Codable, Equatable {
    let id: String
    let email: String?
    let name: String?
    let plan: String
    let weekWords: Int
    let totalWords: Int
    let weekStart: String
    let weekLimit: Int?
}

enum APIError: Error, LocalizedError {
    case notSignedIn
    case invalidSession
    case weeklyLimitReached(limit: Int, used: Int)
    case upstream(String)
    case transport(Error)
    case http(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Not signed in to Talkies."
        case .invalidSession: "Your session has expired. Please sign in again."
        case .weeklyLimitReached(let limit, let used):
            "Weekly limit reached (\(used)/\(limit) words). Upgrade to Pro for unlimited."
        case .upstream(let detail): "Upstream error: \(detail)"
        case .transport(let err): "Network error: \(err.localizedDescription)"
        case .http(let code, let detail): "HTTP \(code): \(detail)"
        case .decoding: "Couldn't read response from server."
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    /// Production Worker URL. Override at runtime for dev by setting a custom
    /// `APIBaseURLOverride` in UserDefaults.
    static let defaultBaseURL = URL(string: "https://talkies-api.pat-barlow.workers.dev")!

    private var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "APIBaseURLOverride"),
           let url = URL(string: override) {
            return url
        }
        return Self.defaultBaseURL
    }

    private init() {}

    // MARK: - Auth

    struct AuthResponse: Decodable {
        let session: String
        let user: PublicUser
    }

    func authenticateWithApple(
        identityToken: String,
        email: String?,
        fullName: String?
    ) async throws -> AuthResponse {
        var payload: [String: String] = ["identityToken": identityToken]
        if let email { payload["email"] = email }
        if let fullName { payload["fullName"] = fullName }

        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, status) = try await post(path: "/auth/apple", body: body, session: nil)
        guard status == 200 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: - Me

    func me(session: String) async throws -> PublicUser {
        let (data, status) = try await get(path: "/v1/me", session: session)
        if status == 401 { throw APIError.invalidSession }
        guard status == 200 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(PublicUser.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: - Transcribe

    struct TranscribeResponse: Decodable {
        let text: String
        let wordCount: Int
    }

    func transcribe(
        audio: URL,
        prompt: String?,
        session: String
    ) async throws -> TranscribeResponse {
        let boundary = "Talkies-\(UUID().uuidString)"
        var body = Data()
        let audioData = try Data(contentsOf: audio)
        body.appendFile(boundary: boundary, name: "audio", filename: "audio.wav", contentType: "audio/wav", data: audioData)
        if let prompt, !prompt.isEmpty {
            body.appendField(boundary: boundary, name: "prompt", value: prompt)
        }
        body.appendString("--\(boundary)--\r\n")

        let url = baseURL.appendingPathComponent("/v1/transcribe")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: body)
        } catch {
            throw APIError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        if status == 401 { throw APIError.invalidSession }
        if status == 402 {
            struct LimitError: Decodable { let limit: Int?; let used: Int? }
            if let err = try? JSONDecoder().decode(LimitError.self, from: data) {
                throw APIError.weeklyLimitReached(limit: err.limit ?? 0, used: err.used ?? 0)
            }
            throw APIError.weeklyLimitReached(limit: 0, used: 0)
        }
        guard status == 200 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(TranscribeResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: - Cleanup

    struct CleanupResponse: Decodable { let text: String }

    func cleanup(
        text: String,
        appName: String?,
        appBundleID: String?,
        session: String
    ) async throws -> String {
        var payload: [String: String] = ["text": text]
        if let appName { payload["appName"] = appName }
        if let appBundleID { payload["appBundleID"] = appBundleID }
        let body = try JSONSerialization.data(withJSONObject: payload)

        let (data, status) = try await post(path: "/v1/cleanup", body: body, session: session)
        if status == 401 { throw APIError.invalidSession }
        guard status == 200 else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(CleanupResponse.self, from: data).text
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: - Low-level

    private func get(path: String, session: String?) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        if let session { request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? -1)
        } catch {
            throw APIError.transport(error)
        }
    }

    private func post(path: String, body: Data, session: String?) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let session { request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? -1)
        } catch {
            throw APIError.transport(error)
        }
    }
}

private extension Data {
    mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
    mutating func appendField(boundary: String, name: String, value: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }
    mutating func appendFile(boundary: String, name: String, filename: String, contentType: String, data: Data) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}
