import SwiftUI

struct FeedbackPane: View {
    @StateObject private var auth = AuthStore.shared

    @State private var message = ""
    @State private var state: SubmitState = .idle

    private enum SubmitState: Equatable {
        case idle, submitting, success, error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch state {
            case .success:
                VStack(spacing: 14) {
                    Spacer().frame(height: 20)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.mint)
                    Text("Thanks for the feedback!")
                        .font(.title3.weight(.semibold))
                    Text("We appreciate you taking the time to share your thoughts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)

            default:
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's on your mind?")
                            .font(.body.weight(.semibold))

                        TextEditor(text: $message)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(height: 120)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08))
                            )
                            .disabled(state == .submitting)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))

                    if case .error(let msg) = state {
                        Label(msg, systemImage: "exclamationmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Spacer()
                        if state == .submitting {
                            ProgressView().controlSize(.small).padding(.trailing, 4)
                        }
                        Button("Send Feedback") {
                            Task { await submit() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state == .submitting)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func submit() async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .submitting

        var req = URLRequest(url: URL(string: "https://speaking.computer/feedback")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "message": trimmed,
            "email": auth.currentUser?.email ?? "",
            "app": "Yap",
        ]

        do {
            req.httpBody = try JSONEncoder().encode(body)
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                state = .success
            } else {
                state = .error("Something went wrong. Please try again.")
            }
        } catch {
            state = .error("Couldn't send feedback. Check your connection.")
        }
    }
}
