import Foundation
import Combine

// Observable settings store backed by App Group UserDefaults + shared keychain.
// Used by both the main app and the keyboard extension.
@MainActor
final class SharedSettings: ObservableObject {
    static let shared = SharedSettings()

    @Published private(set) var sessionToken: String?

    @Published var cleanupLevel: CleanupLevel {
        didSet { SharedDefaults.set(cleanupLevel.rawValue, for: .cleanupLevel) }
    }

    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet { SharedDefaults.set(transcriptionLanguage.displayName, for: .transcriptionLang) }
    }

    @Published var customVocabulary: String? {
        didSet { SharedDefaults.set(customVocabulary, for: .customVocabulary) }
    }

    private init() {
        self.sessionToken = SharedKeychain.read("session").flatMap { $0.isEmpty ? nil : $0 }

        if let raw = SharedDefaults.string(for: .cleanupLevel),
           let level = CleanupLevel(rawValue: raw) {
            self.cleanupLevel = level
        } else {
            self.cleanupLevel = .clean
        }

        if let name = SharedDefaults.string(for: .transcriptionLang),
           let lang = TranscriptionLanguage.all.first(where: { $0.displayName == name }) {
            self.transcriptionLanguage = lang
        } else {
            self.transcriptionLanguage = .default
        }

        self.customVocabulary = SharedDefaults.string(for: .customVocabulary)
    }

    func setSessionToken(_ value: String?) {
        sessionToken = value
        SharedKeychain.write("session", value ?? "")
    }
}
