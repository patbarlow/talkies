import Foundation

enum TranscriberError: Error {
    case notSignedIn
}

/// Transcription always goes through the Yap Worker. It proxies to Groq
/// Whisper and enforces the weekly word limit for free users server-side.
final class Transcriber {
    static let shared = Transcriber()

    func transcribe(wavURL: URL) async throws -> String {
        guard let session = await Settings.shared.sessionToken, !session.isEmpty else {
            throw TranscriberError.notSignedIn
        }
        let vocab = await Settings.shared.customVocabulary
        let language = await Settings.shared.transcriptionLanguage.whisperCode
        let result = try await APIClient.shared.transcribe(
            audio: wavURL,
            prompt: vocab,
            language: language,
            session: session
        )
        Task { await AuthStore.shared.refresh() }
        return result.text
    }
}
