import SwiftUI

struct SignInPane: View {
    @StateObject private var auth = AuthStore.shared

    @State private var step: Step = .enterEmail
    @State private var email: String = ""
    @State private var code: String = ""
    @FocusState private var focused: Field?

    enum Step { case enterEmail, enterCode }
    enum Field { case email, code }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            IconTile(
                systemName: "waveform",
                gradient: LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                size: 88,
                cornerRadius: 22,
                iconScale: 0.55
            )

            VStack(spacing: 6) {
                Text("Welcome to Yap")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(headline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            formBody
                .frame(maxWidth: 320)
                .padding(.top, 4)

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
        .onAppear { focused = (step == .enterEmail ? .email : .code) }
    }

    private var headline: String {
        switch step {
        case .enterEmail:
            "We'll email you a 6-digit code to sign in. No password."
        case .enterCode:
            "Check \(email) for a code. It expires in 10 minutes."
        }
    }

    @ViewBuilder
    private var formBody: some View {
        switch step {
        case .enterEmail:
            VStack(spacing: 10) {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .disableAutocorrection(true)
                    .focused($focused, equals: .email)
                    .onSubmit(sendCode)
                Button(action: sendCode) {
                    Text(auth.isWorking ? "Sending…" : "Send code")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .controlSize(.large)
                .disabled(email.isEmpty || auth.isWorking)
            }

        case .enterCode:
            VStack(spacing: 10) {
                TextField("6-digit code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .disableAutocorrection(true)
                    .focused($focused, equals: .code)
                    .onChange(of: code) { _, new in
                        // Strip non-digits, cap at 6
                        let digits = String(new.filter(\.isNumber).prefix(6))
                        if digits != new { code = digits }
                        if digits.count == 6 { verify() }
                    }
                    .onSubmit(verify)
                Button(action: verify) {
                    Text(auth.isWorking ? "Verifying…" : "Verify")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .controlSize(.large)
                .disabled(code.count != 6 || auth.isWorking)

                HStack {
                    Button("Use a different email") {
                        step = .enterEmail
                        code = ""
                        focused = .email
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("Resend code") { sendCode() }
                        .buttonStyle(.borderless)
                        .disabled(auth.isWorking)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func sendCode() {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        email = normalized
        Task {
            let ok = await auth.requestCode(email: normalized)
            if ok {
                step = .enterCode
                code = ""
                focused = .code
            }
        }
    }

    private func verify() {
        guard code.count == 6, !auth.isWorking else { return }
        Task {
            _ = await auth.verify(email: email, code: code, fullName: nil)
        }
    }
}
