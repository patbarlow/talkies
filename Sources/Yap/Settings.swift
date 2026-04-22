import Foundation
import Security
import SwiftUI

extension Notification.Name {
    static let yapHotkeyChanged = Notification.Name("YapHotkeyChanged")
    static let yapAuthStateChanged = Notification.Name("YapAuthStateChanged")
    static let yapAccessibilityChanged = Notification.Name("YapAccessibilityChanged")
}


enum CleanupLevel: String, CaseIterable, Codable {
    case off, clean, polish

    var label: String {
        switch self {
        case .off:    "Off"
        case .clean:  "Clean"
        case .polish: "Polish"
        }
    }

    var description: String {
        switch self {
        case .off:    "Paste exactly what you said, including mistakes."
        case .clean:  "Remove filler words and fix obvious mis-hearings."
        case .polish: "Rewrite for clarity and brevity while keeping your meaning."
        }
    }
}

struct TranscriptionLanguage: Identifiable, Hashable {
    let displayName: String
    let whisperCode: String
    let spellingVariant: String?

    var id: String { displayName }

    static let all: [TranscriptionLanguage] = [
        .init(displayName: "🇺🇸 English (US)",          whisperCode: "en", spellingVariant: "American"),
        .init(displayName: "🇬🇧 English (British)",     whisperCode: "en", spellingVariant: "British"),
        .init(displayName: "🇦🇺 English (Australian)",  whisperCode: "en", spellingVariant: "Australian"),
        .init(displayName: "🇿🇦 Afrikaans",    whisperCode: "af", spellingVariant: nil),
        .init(displayName: "🇸🇦 Arabic",       whisperCode: "ar", spellingVariant: nil),
        .init(displayName: "🇦🇲 Armenian",     whisperCode: "hy", spellingVariant: nil),
        .init(displayName: "🇦🇿 Azerbaijani",  whisperCode: "az", spellingVariant: nil),
        .init(displayName: "🇧🇾 Belarusian",   whisperCode: "be", spellingVariant: nil),
        .init(displayName: "🇧🇦 Bosnian",      whisperCode: "bs", spellingVariant: nil),
        .init(displayName: "🇧🇬 Bulgarian",    whisperCode: "bg", spellingVariant: nil),
        .init(displayName: "🏴󠁥󠁳󠁣󠁴󠁿 Catalan",      whisperCode: "ca", spellingVariant: nil),
        .init(displayName: "🇨🇳 Chinese",      whisperCode: "zh", spellingVariant: nil),
        .init(displayName: "🇭🇷 Croatian",     whisperCode: "hr", spellingVariant: nil),
        .init(displayName: "🇨🇿 Czech",        whisperCode: "cs", spellingVariant: nil),
        .init(displayName: "🇩🇰 Danish",       whisperCode: "da", spellingVariant: nil),
        .init(displayName: "🇳🇱 Dutch",        whisperCode: "nl", spellingVariant: nil),
        .init(displayName: "🇪🇪 Estonian",     whisperCode: "et", spellingVariant: nil),
        .init(displayName: "🇫🇮 Finnish",      whisperCode: "fi", spellingVariant: nil),
        .init(displayName: "🇫🇷 French",       whisperCode: "fr", spellingVariant: nil),
        .init(displayName: "🇪🇸 Galician",     whisperCode: "gl", spellingVariant: nil),
        .init(displayName: "🇩🇪 German",       whisperCode: "de", spellingVariant: nil),
        .init(displayName: "🇬🇷 Greek",        whisperCode: "el", spellingVariant: nil),
        .init(displayName: "🇮🇱 Hebrew",       whisperCode: "he", spellingVariant: nil),
        .init(displayName: "🇮🇳 Hindi",        whisperCode: "hi", spellingVariant: nil),
        .init(displayName: "🇭🇺 Hungarian",    whisperCode: "hu", spellingVariant: nil),
        .init(displayName: "🇮🇸 Icelandic",    whisperCode: "is", spellingVariant: nil),
        .init(displayName: "🇮🇩 Indonesian",   whisperCode: "id", spellingVariant: nil),
        .init(displayName: "🇮🇹 Italian",      whisperCode: "it", spellingVariant: nil),
        .init(displayName: "🇯🇵 Japanese",     whisperCode: "ja", spellingVariant: nil),
        .init(displayName: "🇮🇳 Kannada",      whisperCode: "kn", spellingVariant: nil),
        .init(displayName: "🇰🇿 Kazakh",       whisperCode: "kk", spellingVariant: nil),
        .init(displayName: "🇰🇷 Korean",       whisperCode: "ko", spellingVariant: nil),
        .init(displayName: "🇱🇻 Latvian",      whisperCode: "lv", spellingVariant: nil),
        .init(displayName: "🇱🇹 Lithuanian",   whisperCode: "lt", spellingVariant: nil),
        .init(displayName: "🇲🇰 Macedonian",   whisperCode: "mk", spellingVariant: nil),
        .init(displayName: "🇲🇾 Malay",        whisperCode: "ms", spellingVariant: nil),
        .init(displayName: "🇮🇳 Marathi",      whisperCode: "mr", spellingVariant: nil),
        .init(displayName: "🇳🇿 Māori",        whisperCode: "mi", spellingVariant: nil),
        .init(displayName: "🇳🇵 Nepali",       whisperCode: "ne", spellingVariant: nil),
        .init(displayName: "🇳🇴 Norwegian",    whisperCode: "no", spellingVariant: nil),
        .init(displayName: "🇮🇷 Persian",      whisperCode: "fa", spellingVariant: nil),
        .init(displayName: "🇵🇱 Polish",       whisperCode: "pl", spellingVariant: nil),
        .init(displayName: "🇵🇹 Portuguese",   whisperCode: "pt", spellingVariant: nil),
        .init(displayName: "🇷🇴 Romanian",     whisperCode: "ro", spellingVariant: nil),
        .init(displayName: "🇷🇺 Russian",      whisperCode: "ru", spellingVariant: nil),
        .init(displayName: "🇷🇸 Serbian",      whisperCode: "sr", spellingVariant: nil),
        .init(displayName: "🇸🇰 Slovak",       whisperCode: "sk", spellingVariant: nil),
        .init(displayName: "🇸🇮 Slovenian",    whisperCode: "sl", spellingVariant: nil),
        .init(displayName: "🇪🇸 Spanish",      whisperCode: "es", spellingVariant: nil),
        .init(displayName: "🇰🇪 Swahili",      whisperCode: "sw", spellingVariant: nil),
        .init(displayName: "🇸🇪 Swedish",      whisperCode: "sv", spellingVariant: nil),
        .init(displayName: "🇵🇭 Tagalog",      whisperCode: "tl", spellingVariant: nil),
        .init(displayName: "🇱🇰 Tamil",        whisperCode: "ta", spellingVariant: nil),
        .init(displayName: "🇹🇭 Thai",         whisperCode: "th", spellingVariant: nil),
        .init(displayName: "🇹🇷 Turkish",      whisperCode: "tr", spellingVariant: nil),
        .init(displayName: "🇺🇦 Ukrainian",    whisperCode: "uk", spellingVariant: nil),
        .init(displayName: "🇵🇰 Urdu",         whisperCode: "ur", spellingVariant: nil),
        .init(displayName: "🇻🇳 Vietnamese",   whisperCode: "vi", spellingVariant: nil),
        .init(displayName: "🏴󠁧󠁢󠁷󠁬󠁳󠁿 Welsh",        whisperCode: "cy", spellingVariant: nil),
    ]

    static let `default` = all[0]
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published private(set) var sessionToken: String?

    @Published var cleanupLevel: CleanupLevel {
        didSet { UserDefaults.standard.set(cleanupLevel.rawValue, forKey: "cleanupLevel") }
    }
    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet { UserDefaults.standard.set(transcriptionLanguage.displayName, forKey: "transcriptionLanguage") }
    }
    @Published var customVocabulary: String? {
        didSet { UserDefaults.standard.set(customVocabulary, forKey: "customVocabulary") }
    }
    @Published var hotkey: HotkeySpec {
        didSet {
            if let data = try? JSONEncoder().encode(hotkey) {
                UserDefaults.standard.set(data, forKey: "hotkey")
            }
            NotificationCenter.default.post(name: .yapHotkeyChanged, object: hotkey)
        }
    }

    private init() {
        self.sessionToken = Keychain.read("session").flatMap { $0.isEmpty ? nil : $0 }
        if let raw = UserDefaults.standard.string(forKey: "cleanupLevel") {
            if let level = CleanupLevel(rawValue: raw) {
                self.cleanupLevel = level
            } else {
                // Migrate from old light/medium/heavy scale
                self.cleanupLevel = raw == "heavy" ? .polish : .clean
            }
        } else {
            let wasEnabled = UserDefaults.standard.object(forKey: "cleanupEnabled") as? Bool ?? true
            self.cleanupLevel = wasEnabled ? .clean : .off
        }
        if let name = UserDefaults.standard.string(forKey: "transcriptionLanguage"),
           let lang = TranscriptionLanguage.all.first(where: { $0.displayName == name }) {
            self.transcriptionLanguage = lang
        } else {
            self.transcriptionLanguage = .default
        }
        self.customVocabulary = UserDefaults.standard.string(forKey: "customVocabulary")

        if let data = UserDefaults.standard.data(forKey: "hotkey"),
           let spec = try? JSONDecoder().decode(HotkeySpec.self, from: data) {
            self.hotkey = spec
        } else {
            self.hotkey = .defaultSpec
        }
    }

    func setSessionToken(_ value: String?) {
        sessionToken = value
        Keychain.write("session", value ?? "")
    }
}

enum Keychain {
    private static let service = "app.yap.Yap"

    static func read(_ account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String) {
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(base as CFDictionary)
        if value.isEmpty { return }
        var add = base
        add[kSecValueData] = value.data(using: .utf8)!
        SecItemAdd(add as CFDictionary, nil)
    }
}
