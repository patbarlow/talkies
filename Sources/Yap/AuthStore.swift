import Foundation
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var currentUser: PublicUser?
    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var isWorking: Bool = false
    @Published private(set) var lastError: String?

    private init() {
        if Settings.shared.sessionToken != nil {
            isSignedIn = true
            Task { await refresh() }
        }
    }

    /// Ask the backend to send a 6-digit code to `email`.
    func requestCode(email: String) async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await APIClient.shared.requestEmailCode(email: email)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Exchange `email` + `code` for a Yap session.
    func verify(email: String, code: String, fullName: String?) async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let result = try await APIClient.shared.verifyEmailCode(
                email: email,
                code: code,
                fullName: fullName
            )
            Settings.shared.setSessionToken(result.session)
            currentUser = result.user
            isSignedIn = true
            NotificationCenter.default.post(name: .yapAuthStateChanged, object: nil)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Hit /v1/me to refresh the cached user snapshot.
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
            NSLog("Yap me refresh failed: \(error)")
        }
    }

    func signOut() {
        Settings.shared.setSessionToken(nil)
        currentUser = nil
        isSignedIn = false
        lastError = nil
        NotificationCenter.default.post(name: .yapAuthStateChanged, object: nil)
    }

    /// Persist a new display name via PATCH /v1/me.
    func updateName(_ name: String) async {
        guard let session = Settings.shared.sessionToken else { return }
        do {
            currentUser = try await APIClient.shared.updateName(name, session: session)
        } catch APIError.invalidSession {
            signOut()
        } catch {
            NSLog("Yap updateName failed: \(error)")
        }
    }
}
