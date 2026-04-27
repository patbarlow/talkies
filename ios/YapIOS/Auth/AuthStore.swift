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
        if SharedSettings.shared.sessionToken != nil {
            isSignedIn = true
            Task { await refresh() }
        }
    }

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

    func verify(email: String, code: String, fullName: String?) async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let result = try await APIClient.shared.verifyEmailCode(email: email, code: code, fullName: fullName)
            SharedSettings.shared.setSessionToken(result.session)
            currentUser = result.user
            isSignedIn = true
            if result.user.hasAvatar {
                ProfileImage.shared.syncFromServer(session: result.session)
            }
            // Check for existing Apple IAP on sign-in
            await IAPManager.shared.syncActivePurchases(session: result.session)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func refresh() async {
        guard let session = SharedSettings.shared.sessionToken else {
            signOut()
            return
        }
        do {
            let user = try await APIClient.shared.me(session: session)
            currentUser = user
            isSignedIn = true
            if user.hasAvatar {
                ProfileImage.shared.syncFromServer(session: session)
            }
        } catch APIError.invalidSession {
            signOut()
        } catch {
            // Network failure — keep existing state
        }
    }

    func signOut() {
        SharedSettings.shared.setSessionToken(nil)
        currentUser = nil
        isSignedIn = false
        lastError = nil
        ProfileImage.shared.clear()
    }

    func updateName(_ name: String) async {
        guard let session = SharedSettings.shared.sessionToken else { return }
        do {
            currentUser = try await APIClient.shared.updateName(name, session: session)
        } catch APIError.invalidSession {
            signOut()
        } catch {}
    }
}
