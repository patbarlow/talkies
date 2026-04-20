import Foundation
import Security
import SwiftUI

extension Notification.Name {
    static let yapHotkeyChanged = Notification.Name("YapHotkeyChanged")
    static let yapAuthStateChanged = Notification.Name("YapAuthStateChanged")
    static let yapAccessibilityChanged = Notification.Name("YapAccessibilityChanged")
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published private(set) var sessionToken: String?

    @Published var cleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(cleanupEnabled, forKey: "cleanupEnabled") }
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
        self.cleanupEnabled = UserDefaults.standard.object(forKey: "cleanupEnabled") as? Bool ?? true
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
