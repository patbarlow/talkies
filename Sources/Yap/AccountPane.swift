import AppKit
import SwiftUI

struct AccountPane: View {
    @StateObject private var auth = AuthStore.shared
    @StateObject private var profileImage = ProfileImage.shared

    @State private var nameDraft: String = ""
    @State private var upgrading: Bool = false
    @State private var upgradeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let user = auth.currentUser {
                signedInView(user: user)
            } else {
                ProgressView("Loading account…")
                    .frame(maxWidth: .infinity)
                    .padding(40)
            }
            Spacer()
        }
        .task { await auth.refresh() }
        .onAppear {
            if nameDraft.isEmpty { nameDraft = auth.currentUser?.name ?? "" }
        }
        .onChange(of: auth.currentUser?.name) { _, new in
            nameDraft = new ?? ""
        }
    }

    @ViewBuilder
    private func signedInView(user: PublicUser) -> some View {
        // Identity card — avatar + name field + email + plan
        HStack(spacing: 16) {
            avatarButton

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Your name", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                        .onSubmit { Task { await saveName() } }
                    if nameDirty {
                        Button("Save") { Task { await saveName() } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                Text(user.email)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            planBadge(user.plan)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))

        // Usage card
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weekly usage").font(.body.weight(.medium))
                Spacer()
                if let limit = user.weekLimit {
                    Text("\(user.weekWords.formatted()) / \(limit.formatted()) words")
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("\(user.weekWords.formatted()) words · unlimited")
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let limit = user.weekLimit, limit > 0 {
                ProgressView(value: Double(min(user.weekWords, limit)), total: Double(limit))
                    .tint(.mint)
            }
            Text("Resets Mondays 00:00 UTC.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))

        // Upgrade card — shown only on free plan
        if user.plan == "free" {
            VStack(alignment: .leading, spacing: 10) {
                Text("Upgrade to Yap Pro").font(.body.weight(.semibold))
                Text("Unlimited words per week. Supports development.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(action: upgrade) {
                    Text(upgrading ? "Waiting for payment…" : "Upgrade…")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .disabled(upgrading)
                if let err = upgradeError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
        }

        HStack {
            Button("Sign out", role: .destructive) { auth.signOut() }
                .buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Avatar

    private var avatarButton: some View {
        Button {
            profileImage.pick()
        } label: {
            ZStack {
                if let img = profileImage.image {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Text(initials(for: auth.currentUser?.name, email: auth.currentUser?.email ?? ""))
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                        )
                }
                // Little camera badge to hint it's clickable
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .overlay(Image(systemName: "camera.fill").font(.caption2).foregroundStyle(.white))
                    .offset(x: 20, y: 20)
            }
        }
        .buttonStyle(.plain)
        .help("Click to change your profile picture")
    }

    private func initials(for name: String?, email: String) -> String {
        if let name, !name.isEmpty {
            let parts = name.split(separator: " ").prefix(2)
            return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        }
        return String(email.prefix(1)).uppercased()
    }

    // MARK: - Name save

    private var nameDirty: Bool {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (auth.currentUser?.name ?? "")
    }

    private func saveName() async {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (auth.currentUser?.name ?? "") else { return }
        await auth.updateName(trimmed)
    }

    // MARK: - Stripe upgrade

    private func upgrade() {
        guard let session = Settings.shared.sessionToken, !upgrading else { return }
        upgrading = true
        upgradeError = nil
        Task {
            do {
                let url = try await APIClient.shared.stripeCheckout(session: session)
                NSWorkspace.shared.open(url)
                // Poll /v1/me for up to 5 minutes while checkout happens in browser.
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await auth.refresh()
                    if auth.currentUser?.plan == "pro" {
                        upgrading = false
                        return
                    }
                }
                upgrading = false
                upgradeError = "Didn't pick up an upgrade — try Check for Updates… or reload later."
            } catch {
                upgrading = false
                upgradeError = error.localizedDescription
            }
        }
    }

    // MARK: - Plan badge

    private func planBadge(_ plan: String) -> some View {
        Text(plan.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(plan == "pro" ? Color.mint : Color.secondary.opacity(0.2)))
            .foregroundStyle(plan == "pro" ? Color.black : Color.secondary)
    }
}
