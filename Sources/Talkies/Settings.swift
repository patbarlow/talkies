import Foundation
import Security
import SwiftUI

extension Notification.Name {
    static let talkiesHotkeyChanged = Notification.Name("TalkiesHotkeyChanged")
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published private(set) var groqKey: String?
    @Published private(set) var anthropicKey: String?
    @Published private(set) var sessionToken: String?

    @Published var cleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(cleanupEnabled, forKey: "cleanupEnabled") }
    }
    @Published var hasSkippedSignIn: Bool {
        didSet { UserDefaults.standard.set(hasSkippedSignIn, forKey: "hasSkippedSignIn") }
    }
    @Published var customVocabulary: String? {
        didSet { UserDefaults.standard.set(customVocabulary, forKey: "customVocabulary") }
    }
    @Published var hotkey: HotkeySpec {
        didSet {
            if let data = try? JSONEncoder().encode(hotkey) {
                UserDefaults.standard.set(data, forKey: "hotkey")
            }
            NotificationCenter.default.post(name: .talkiesHotkeyChanged, object: hotkey)
        }
    }

    private init() {
        self.groqKey = Keychain.read("groq")
        self.anthropicKey = Keychain.read("anthropic")
        self.sessionToken = Keychain.read("session").flatMap { $0.isEmpty ? nil : $0 }
        self.cleanupEnabled = UserDefaults.standard.object(forKey: "cleanupEnabled") as? Bool ?? true
        self.hasSkippedSignIn = UserDefaults.standard.bool(forKey: "hasSkippedSignIn")
        self.customVocabulary = UserDefaults.standard.string(forKey: "customVocabulary")

        if let data = UserDefaults.standard.data(forKey: "hotkey"),
           let spec = try? JSONDecoder().decode(HotkeySpec.self, from: data) {
            self.hotkey = spec
        } else {
            self.hotkey = .defaultSpec
        }
    }

    func setGroqKey(_ value: String) {
        groqKey = value
        Keychain.write("groq", value)
    }

    func setAnthropicKey(_ value: String) {
        anthropicKey = value
        Keychain.write("anthropic", value)
    }

    func setSessionToken(_ value: String?) {
        sessionToken = value
        Keychain.write("session", value ?? "")
    }
}

enum Keychain {
    private static let service = "app.talkies.Talkies"

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
