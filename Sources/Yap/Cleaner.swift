import AppKit
import Foundation

enum CleanerError: Error {
    case notSignedIn
}

/// Cleanup always goes through the Yap Worker, which proxies to Claude Haiku
/// with app-aware tone matching.
final class Cleaner {
    static let shared = Cleaner()

    func clean(_ raw: String) async throws -> String {
        guard let session = await Settings.shared.sessionToken, !session.isEmpty else {
            throw CleanerError.notSignedIn
        }
        let frontApp = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        return try await APIClient.shared.cleanup(
            text: raw,
            appName: frontApp?.localizedName,
            appBundleID: frontApp?.bundleIdentifier,
            session: session
        )
    }
}
