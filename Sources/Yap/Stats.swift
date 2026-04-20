import Foundation
import SwiftUI

@MainActor
final class Stats: ObservableObject {
    static let shared = Stats()

    @Published private(set) var totalWords: Int
    @Published private(set) var totalSeconds: Double
    @Published private(set) var sessionCount: Int
    @Published private(set) var weekWords: Int
    @Published private(set) var weekSeconds: Double
    @Published private(set) var weekStart: Date

    /// Assumed typing speed in WPM — used for "time saved" metric.
    @Published var typingWPM: Double {
        didSet { UserDefaults.standard.set(typingWPM, forKey: "stats.typingWPM") }
    }

    private init() {
        let ud = UserDefaults.standard
        totalWords = ud.integer(forKey: "stats.totalWords")
        totalSeconds = ud.double(forKey: "stats.totalSeconds")
        sessionCount = ud.integer(forKey: "stats.sessionCount")
        weekWords = ud.integer(forKey: "stats.weekWords")
        weekSeconds = ud.double(forKey: "stats.weekSeconds")
        if let d = ud.object(forKey: "stats.weekStart") as? Date {
            weekStart = d
        } else {
            weekStart = Self.startOfWeek(Date())
        }
        typingWPM = (ud.object(forKey: "stats.typingWPM") as? Double) ?? 45
        rotateWeekIfNeeded()
    }

    /// Average words per minute across all dictations.
    var averageWPM: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalWords) / (totalSeconds / 60.0)
    }

    /// Minutes saved vs. typing this week.
    var timeSavedThisWeekMinutes: Double {
        guard typingWPM > 0 else { return 0 }
        let typingMinutes = Double(weekWords) / typingWPM
        let speakingMinutes = weekSeconds / 60.0
        return max(0, typingMinutes - speakingMinutes)
    }

    func record(text: String, duration: TimeInterval) {
        let count = text.split(whereSeparator: { $0.isWhitespace }).count
        guard count > 0 else { return }

        rotateWeekIfNeeded()
        totalWords += count
        totalSeconds += max(0, duration)
        sessionCount += 1
        weekWords += count
        weekSeconds += max(0, duration)

        persist()
    }

    private func rotateWeekIfNeeded() {
        let current = Self.startOfWeek(Date())
        if current > weekStart {
            weekStart = current
            weekWords = 0
            weekSeconds = 0
        }
    }

    private func persist() {
        let ud = UserDefaults.standard
        ud.set(totalWords, forKey: "stats.totalWords")
        ud.set(totalSeconds, forKey: "stats.totalSeconds")
        ud.set(sessionCount, forKey: "stats.sessionCount")
        ud.set(weekWords, forKey: "stats.weekWords")
        ud.set(weekSeconds, forKey: "stats.weekSeconds")
        ud.set(weekStart, forKey: "stats.weekStart")
    }

    private static func startOfWeek(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }
}
