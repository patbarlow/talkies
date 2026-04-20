import Foundation
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var currentUser: PublicUser?
    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var isAuthenticating: Bool = false
    @Published private(set) var lastError: String?

    private init() {
        if Settings.shared.sessionToken != nil {
            isSignedIn = true
            Task { await refresh() }
        }
    }

    /// Exchange an Apple identity token for a Talkies session.
    func signInWithApple(
        identityToken: String,
        email: String?,
        fullName: String?
    ) async {
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        do {
            let result = try await APIClient.shared.authenticateWithApple(
                identityToken: identityToken,
                email: email,
                fullName: fullName
            )
            Settings.shared.setSessionToken(result.session)
            currentUser = result.user
            isSignedIn = true
        } catch {
            lastError = error.localizedDescription
            NSLog("Talkies sign-in failed: \(error)")
        }
    }

    /// Hit /v1/me to refresh the cached user snapshot (called after recordings, etc.).
    func refresh() async {
        guard let session = Settings.shared.sessionToken else {
            signOut()
            return
        }
        do {
            currentUser = try await APIClient.shared.me(session: session)
            isSignedIn = true
        } catch APIError.invalidSession {
            signOut()
        } catch {
            // Transient — keep the last-known user.
            NSLog("Talkies me refresh failed: \(error)")
        }
    }

    func signOut() {
        Settings.shared.setSessionToken(nil)
        currentUser = nil
        isSignedIn = false
    }
}
