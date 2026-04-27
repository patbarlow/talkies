import Foundation

// MARK: - User & Auth

struct PublicUser: Codable, Equatable {
    let id: String
    let email: String
    let name: String?
    let plan: String
    let weekWords: Int
    let totalWords: Int
    let weekStart: String
    let weekLimit: Int?
    let hasAvatar: Bool
}

// MARK: - API Errors

enum APIError: Error, LocalizedError {
    case notSignedIn
    case invalidSession
    case weeklyLimitReached(limit: Int, used: Int)
    case rateLimited(retryAfter: Int)
    case invalidCode
    case codeExpired
    case tooManyAttempts
    case noCode
    case upstream(String)
    case transport(Error)
    case http(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Yap."
        case .invalidSession:
            return "Your session has expired. Please sign in again."
        case .weeklyLimitReached(let limit, let used):
            return "Weekly limit reached (\(used)/\(limit) words). Upgrade to Pro for unlimited."
        case .rateLimited(let retryAfter):
            return "Please wait \(retryAfter) seconds before requesting another code."
        case .invalidCode:
            return "That code isn't right."
        case .codeExpired:
            return "That code has expired. Request a new one."
        case .tooManyAttempts:
            return "Too many attempts. Request a new code."
        case .noCode:
            return "No code was sent to that email recently."
        case .upstream(let detail):
            return "Upstream error: \(detail)"
        case .transport(let err):
            return "Network error: \(err.localizedDescription)"
        case .http(let code, let detail):
            return "HTTP \(code): \(detail)"
        case .decoding:
            return "Couldn't read response from server."
        }
    }
}

// MARK: - Library

struct RecordingEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let rawText: String
    let finalText: String
    let durationSeconds: Double
    let wordCount: Int
    let appName: String?
    let bundleID: String?
    let cleanupLevel: String?
    let language: String?
    var syncedAt: Date?
}

// MARK: - Settings types

enum CleanupLevel: String, CaseIterable, Codable {
    case off, clean, polish

    var label: String {
        switch self {
        case .off:    return "Off"
        case .clean:  return "Clean"
        case .polish: return "Polish"
        }
    }

    var description: String {
        switch self {
        case .off:    return "Paste exactly what you said, including mistakes."
        case .clean:  return "Remove filler words and fix obvious mis-hearings."
        case .polish: return "Rewrite for clarity and brevity while keeping your meaning."
        }
    }
}

struct TranscriptionLanguage: Identifiable, Hashable, Codable {
    let displayName: String
    let whisperCode: String
    let spellingVariant: String?

    var id: String { displayName }

    static let all: [TranscriptionLanguage] = [
        .init(displayName: "🇺🇸 English (US)",         whisperCode: "en", spellingVariant: "American"),
        .init(displayName: "🇬🇧 English (British)",    whisperCode: "en", spellingVariant: "British"),
        .init(displayName: "🇦🇺 English (Australian)", whisperCode: "en", spellingVariant: "Australian"),
        .init(displayName: "🇿🇦 Afrikaans",   whisperCode: "af", spellingVariant: nil),
        .init(displayName: "🇸🇦 Arabic",      whisperCode: "ar", spellingVariant: nil),
        .init(displayName: "🇦🇲 Armenian",    whisperCode: "hy", spellingVariant: nil),
        .init(displayName: "🇦🇿 Azerbaijani", whisperCode: "az", spellingVariant: nil),
        .init(displayName: "🇧🇾 Belarusian",  whisperCode: "be", spellingVariant: nil),
        .init(displayName: "🇧🇦 Bosnian",     whisperCode: "bs", spellingVariant: nil),
        .init(displayName: "🇧🇬 Bulgarian",   whisperCode: "bg", spellingVariant: nil),
        .init(displayName: "🏴󠁥󠁳󠁣󠁴󠁿 Catalan",     whisperCode: "ca", spellingVariant: nil),
        .init(displayName: "🇨🇳 Chinese",     whisperCode: "zh", spellingVariant: nil),
        .init(displayName: "🇭🇷 Croatian",    whisperCode: "hr", spellingVariant: nil),
        .init(displayName: "🇨🇿 Czech",       whisperCode: "cs", spellingVariant: nil),
        .init(displayName: "🇩🇰 Danish",      whisperCode: "da", spellingVariant: nil),
        .init(displayName: "🇳🇱 Dutch",       whisperCode: "nl", spellingVariant: nil),
        .init(displayName: "🇪🇪 Estonian",    whisperCode: "et", spellingVariant: nil),
        .init(displayName: "🇫🇮 Finnish",     whisperCode: "fi", spellingVariant: nil),
        .init(displayName: "🇫🇷 French",      whisperCode: "fr", spellingVariant: nil),
        .init(displayName: "🇪🇸 Galician",    whisperCode: "gl", spellingVariant: nil),
        .init(displayName: "🇩🇪 German",      whisperCode: "de", spellingVariant: nil),
        .init(displayName: "🇬🇷 Greek",       whisperCode: "el", spellingVariant: nil),
        .init(displayName: "🇮🇱 Hebrew",      whisperCode: "he", spellingVariant: nil),
        .init(displayName: "🇮🇳 Hindi",       whisperCode: "hi", spellingVariant: nil),
        .init(displayName: "🇭🇺 Hungarian",   whisperCode: "hu", spellingVariant: nil),
        .init(displayName: "🇮🇸 Icelandic",   whisperCode: "is", spellingVariant: nil),
        .init(displayName: "🇮🇩 Indonesian",  whisperCode: "id", spellingVariant: nil),
        .init(displayName: "🇮🇹 Italian",     whisperCode: "it", spellingVariant: nil),
        .init(displayName: "🇯🇵 Japanese",    whisperCode: "ja", spellingVariant: nil),
        .init(displayName: "🇮🇳 Kannada",     whisperCode: "kn", spellingVariant: nil),
        .init(displayName: "🇰🇿 Kazakh",      whisperCode: "kk", spellingVariant: nil),
        .init(displayName: "🇰🇷 Korean",      whisperCode: "ko", spellingVariant: nil),
        .init(displayName: "🇱🇻 Latvian",     whisperCode: "lv", spellingVariant: nil),
        .init(displayName: "🇱🇹 Lithuanian",  whisperCode: "lt", spellingVariant: nil),
        .init(displayName: "🇲🇰 Macedonian",  whisperCode: "mk", spellingVariant: nil),
        .init(displayName: "🇲🇾 Malay",       whisperCode: "ms", spellingVariant: nil),
        .init(displayName: "🇮🇳 Marathi",     whisperCode: "mr", spellingVariant: nil),
        .init(displayName: "🇳🇿 Māori",       whisperCode: "mi", spellingVariant: nil),
        .init(displayName: "🇳🇵 Nepali",      whisperCode: "ne", spellingVariant: nil),
        .init(displayName: "🇳🇴 Norwegian",   whisperCode: "no", spellingVariant: nil),
        .init(displayName: "🇮🇷 Persian",     whisperCode: "fa", spellingVariant: nil),
        .init(displayName: "🇵🇱 Polish",      whisperCode: "pl", spellingVariant: nil),
        .init(displayName: "🇵🇹 Portuguese",  whisperCode: "pt", spellingVariant: nil),
        .init(displayName: "🇷🇴 Romanian",    whisperCode: "ro", spellingVariant: nil),
        .init(displayName: "🇷🇺 Russian",     whisperCode: "ru", spellingVariant: nil),
        .init(displayName: "🇷🇸 Serbian",     whisperCode: "sr", spellingVariant: nil),
        .init(displayName: "🇸🇰 Slovak",      whisperCode: "sk", spellingVariant: nil),
        .init(displayName: "🇸🇮 Slovenian",   whisperCode: "sl", spellingVariant: nil),
        .init(displayName: "🇪🇸 Spanish",     whisperCode: "es", spellingVariant: nil),
        .init(displayName: "🇰🇪 Swahili",     whisperCode: "sw", spellingVariant: nil),
        .init(displayName: "🇸🇪 Swedish",     whisperCode: "sv", spellingVariant: nil),
        .init(displayName: "🇵🇭 Tagalog",     whisperCode: "tl", spellingVariant: nil),
        .init(displayName: "🇱🇰 Tamil",       whisperCode: "ta", spellingVariant: nil),
        .init(displayName: "🇹🇭 Thai",        whisperCode: "th", spellingVariant: nil),
        .init(displayName: "🇹🇷 Turkish",     whisperCode: "tr", spellingVariant: nil),
        .init(displayName: "🇺🇦 Ukrainian",   whisperCode: "uk", spellingVariant: nil),
        .init(displayName: "🇵🇰 Urdu",        whisperCode: "ur", spellingVariant: nil),
        .init(displayName: "🇻🇳 Vietnamese",  whisperCode: "vi", spellingVariant: nil),
        .init(displayName: "🏴󠁧󠁢󠁷󠁬󠁳󠁿 Welsh",       whisperCode: "cy", spellingVariant: nil),
    ]

    static let `default` = all[0]
}
