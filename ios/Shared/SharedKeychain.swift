import Foundation
import Security

// Both the main app (app.yap.YapIOS) and the keyboard extension
// (app.yap.YapIOS.Keyboard) share this keychain access group.
// Both targets list "$(AppIdentifierPrefix)app.yap.YapIOS" in their
// keychain-access-groups entitlement, which resolves to
// "T544U3WVL6.app.yap.YapIOS" at signing time.
enum SharedKeychain {
    private static let service = "app.yap.YapIOS"
    private static let accessGroup = "T544U3WVL6.app.yap.YapIOS"

    static func read(_ account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: accessGroup,
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
            kSecAttrAccessGroup: accessGroup,
        ]
        SecItemDelete(base as CFDictionary)
        if value.isEmpty { return }
        var add = base
        add[kSecValueData] = value.data(using: .utf8)!
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
