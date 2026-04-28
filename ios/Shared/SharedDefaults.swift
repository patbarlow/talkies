import Foundation

// App Group UserDefaults — readable by both the main app and the keyboard extension.
enum SharedDefaults {
    static let suiteName = "group.app.yap"

    private static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Keys

    enum Key: String {
        case cleanupLevel       = "cleanupLevel"
        case transcriptionLang  = "transcriptionLanguage"
        case customVocabulary   = "customVocabulary"
        // Stats
        case totalWords         = "stats.totalWords"
        case totalSeconds       = "stats.totalSeconds"
        case sessionCount       = "stats.sessionCount"
        case weekWords          = "stats.weekWords"
        case weekSeconds        = "stats.weekSeconds"
        case weekStart          = "stats.weekStart"
        case typingWPM          = "stats.typingWPM"
        // Keyboard activation workaround
        case appBecameActiveAt  = "app.becameActiveAt"
    }

    static func string(for key: Key) -> String? {
        store.string(forKey: key.rawValue)
    }

    static func set(_ value: String?, for key: Key) {
        store.set(value, forKey: key.rawValue)
    }

    static func integer(for key: Key) -> Int {
        store.integer(forKey: key.rawValue)
    }

    static func set(_ value: Int, for key: Key) {
        store.set(value, forKey: key.rawValue)
    }

    static func double(for key: Key) -> Double {
        store.double(forKey: key.rawValue)
    }

    static func set(_ value: Double, for key: Key) {
        store.set(value, forKey: key.rawValue)
    }

    static func date(for key: Key) -> Date? {
        store.object(forKey: key.rawValue) as? Date
    }

    static func set(_ value: Date, for key: Key) {
        store.set(value, forKey: key.rawValue)
    }
}
