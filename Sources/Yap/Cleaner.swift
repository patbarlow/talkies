import AppKit
import Foundation

enum CleanerError: Error {
    case missingCredentials
    case badResponse(Int, String)
}

/// Two modes:
///   1. Signed-in — POSTs the transcript to our Worker, which proxies to Claude Haiku.
///   2. BYOK — if the user has set an Anthropic API key directly, goes straight to Anthropic.
final class Cleaner {
    static let shared = Cleaner()

    private let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-haiku-4-5"

    func clean(_ raw: String) async throws -> String {
        let frontApp = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        let appName = frontApp?.localizedName
        let appBundleID = frontApp?.bundleIdentifier

        if let session = await Settings.shared.sessionToken, !session.isEmpty {
            return try await APIClient.shared.cleanup(
                text: raw,
                appName: appName,
                appBundleID: appBundleID,
                session: session
            )
        }

        // BYOK fallback.
        guard let key = await Settings.shared.anthropicKey, !key.isEmpty else {
            throw CleanerError.missingCredentials
        }

        let system = """
        You clean up voice dictation before it is inserted into \(appName ?? "an app").

        Rules:
        - Remove filler words (um, uh, like, you know, sort of).
        - Fix obvious speech-to-text mistakes when context makes the right word clear; otherwise leave the words alone.
        - Preserve the speaker's meaning and voice. Do not add new content.
        - Apply reasonable punctuation and casing.
        - Honor explicit dictation commands: "new line" → \\n, "new paragraph" → \\n\\n.
        - Match the register of \(appName ?? "the app") (casual for Slack/Messages, neutral for Mail, precise for code editors).
        - Return ONLY the cleaned text. No preamble, no quotes, no commentary.
        """

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [["role": "user", "content": raw]],
        ]

        var request = URLRequest(url: anthropicEndpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CleanerError.badResponse(status, String(data: data, encoding: .utf8) ?? "")
        }

        struct Reply: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        return reply.content
            .compactMap { $0.text }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
