import Foundation

enum TranscriberError: Error {
    case missingKey
    case badResponse(Int, String)
}

/// Sends audio to Groq's OpenAI-compatible Whisper endpoint.
/// Swap this implementation to hit Deepgram / OpenAI / Apple SpeechAnalyzer as needed.
final class Transcriber {
    static let shared = Transcriber()

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let model = "whisper-large-v3-turbo"

    func transcribe(wavURL: URL) async throws -> String {
        guard let key = await Settings.shared.groqKey, !key.isEmpty else {
            throw TranscriberError.missingKey
        }

        let boundary = "Talkies-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendField(boundary: boundary, name: "model", value: model)
        body.appendField(boundary: boundary, name: "language", value: "en")
        body.appendField(boundary: boundary, name: "response_format", value: "json")
        body.appendField(boundary: boundary, name: "temperature", value: "0")

        if let vocab = await Settings.shared.customVocabulary, !vocab.isEmpty {
            body.appendField(boundary: boundary, name: "prompt", value: vocab)
        }

        let audio = try Data(contentsOf: wavURL)
        body.appendFile(boundary: boundary, name: "file", filename: "audio.wav", contentType: "audio/wav", data: audio)
        body.appendString("--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranscriberError.badResponse(status, String(data: data, encoding: .utf8) ?? "")
        }
        struct Reply: Decodable { let text: String }
        return try JSONDecoder().decode(Reply.self, from: data)
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
