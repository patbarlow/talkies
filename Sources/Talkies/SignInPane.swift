import AuthenticationServices
import SwiftUI

struct SignInPane: View {
    @StateObject private var auth = AuthStore.shared
    @StateObject private var settings = Settings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            IconTile(
                systemName: "waveform",
                gradient: LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                size: 96,
                cornerRadius: 22,
                iconScale: 0.55
            )

            VStack(spacing: 6) {
                Text("Welcome to Talkies")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Sign in to start dictating. Your voice, transcripts, and settings stay on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await handle(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(width: 280, height: 44)
            .disabled(auth.isAuthenticating)

            Button("Use my own API keys →") {
                settings.hasSkippedSignIn = true
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(.secondary)

            if let err = auth.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Text("Free plan includes 2,000 words per week.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                auth.objectWillChange.send()
                NSLog("Talkies: missing Apple identity token")
                return
            }
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            await auth.signInWithApple(
                identityToken: token,
                email: credential.email,
                fullName: fullName.isEmpty ? nil : fullName
            )
        case .failure(let error):
            // User cancelled is ASAuthorizationError.Code.canceled — don't show as an error.
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                NSLog("Talkies Apple sign-in failure: \(error)")
            }
        }
    }
}
