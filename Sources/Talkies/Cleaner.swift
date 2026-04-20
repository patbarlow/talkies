import AppKit
import Foundation

enum CleanerError: Error {
    case missingKey
    case badResponse(Int, String)
}

/// Post-transcription polish: strip fillers, fix obvious mis-hearings, apply light formatting.
/// Per-app tone is achieved by passing the frontmost app name into the system prompt.
final class Cleaner {
    static let shared = Cleaner()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-haiku-4-5"

    func clean(_ raw: String) async throws -> String {
        guard let key = await Settings.shared.anthropicKey, !key.isEmpty else {
            throw CleanerError.missingKey
        }

        let frontApp = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.localizedName ?? "an app"
        }

        let system = """
        You clean up voice dictation before it is inserted into \(frontApp).

        Rules:
        - Remove filler words (um, uh, like, you know, sort of).
        - Fix obvious speech-to-text mistakes when context makes the right word clear; otherwise leave the words alone.
        - Preserve the speaker's meaning and voice. Do not add new content.
        - Apply reasonable punctuation and casing.
        - Honor explicit dictation commands: "new line" → \\n, "new paragraph" → \\n\\n.
        - Match the register of \(frontApp) (casual for Slack/Messages, neutral for Mail, precise for code editors).
        - Return ONLY the cleaned text. No preamble, no quotes, no commentary.
        """

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [["role": "user", "content": raw]],
        ]

        var request = URLRequest(url: endpoint)
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
