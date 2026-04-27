import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var email = ""
    @State private var code = ""
    @State private var fullName = ""
    @State private var step: Step = .email

    enum Step { case email, code }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Logo / wordmark
                VStack(spacing: 8) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.mint)
                    Text("Yap")
                        .font(.largeTitle.bold())
                    Text("Dictate anything, anywhere.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Form
                VStack(spacing: 16) {
                    switch step {
                    case .email:
                        emailStep
                    case .code:
                        codeStep
                    }

                    if let error = auth.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Email step

    private var emailStep: some View {
        VStack(spacing: 12) {
            TextField("Email address", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.continue)
                .onSubmit { Task { await sendCode() } }

            TextField("Your name (optional)", text: $fullName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .submitLabel(.continue)
                .onSubmit { Task { await sendCode() } }

            Button(action: { Task { await sendCode() } }) {
                Group {
                    if auth.isWorking {
                        ProgressView()
                    } else {
                        Text("Continue")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .disabled(email.isEmpty || auth.isWorking)
        }
    }

    // MARK: - Code step

    private var codeStep: some View {
        VStack(spacing: 12) {
            Text("Enter the 6-digit code sent to\n**\(email)**")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            TextField("000000", text: $code)
                .textFieldStyle(.roundedBorder)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.title2.monospaced())
                .multilineTextAlignment(.center)
                .onChange(of: code) { _, new in
                    let digits = new.filter(\.isNumber)
                    code = String(digits.prefix(6))
                    if code.count == 6 { Task { await verify() } }
                }

            Button(action: { Task { await verify() } }) {
                Group {
                    if auth.isWorking {
                        ProgressView()
                    } else {
                        Text("Sign in")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .disabled(code.count < 6 || auth.isWorking)

            Button("Use a different email") {
                step = .email
                code = ""
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func sendCode() async {
        guard !email.isEmpty else { return }
        let ok = await auth.requestCode(email: email)
        if ok { step = .code }
    }

    private func verify() async {
        guard code.count == 6 else { return }
        _ = await auth.verify(
            email: email,
            code: code,
            fullName: fullName.isEmpty ? nil : fullName
        )
    }
}
