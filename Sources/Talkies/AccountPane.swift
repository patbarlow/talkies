import SwiftUI

struct AccountPane: View {
    @StateObject private var auth = AuthStore.shared

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
    }

    @ViewBuilder
    private func signedInView(user: PublicUser) -> some View {
        // Header card
        HStack(spacing: 14) {
            IconTile(
                systemName: "person.fill",
                gradient: LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                size: 48,
                cornerRadius: 12,
                iconScale: 0.52
            )
            VStack(alignment: .leading, spacing: 2) {
                if let name = user.name, !name.isEmpty {
                    Text(name).font(.headline)
                }
                Text(user.email).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            planBadge(user.plan)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

        // Usage card
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weekly usage").font(.body.weight(.medium))
                Spacer()
                if let limit = user.weekLimit {
                    Text("\(user.weekWords.formatted()) / \(limit.formatted()) words")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(user.weekWords.formatted()) words · unlimited")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let limit = user.weekLimit, limit > 0 {
                ProgressView(value: Double(min(user.weekWords, limit)), total: Double(limit))
                    .tint(.mint)
            }
            Text("Resets Mondays 00:00 UTC.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

        // Plan / actions card
        if user.plan == "free" {
            VStack(alignment: .leading, spacing: 10) {
                Text("Upgrade to Pro").font(.body.weight(.semibold))
                Text("Unlimited words per week and priority access to new features.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Upgrade…") {
                    // TODO: hit /v1/stripe/checkout, open returned URL in browser
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .disabled(true)
                .help("Stripe integration coming soon.")
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        }

        HStack {
            Button("Sign out", role: .destructive) { auth.signOut() }
                .buttonStyle(.bordered)
            Spacer()
            Button("Refresh") { Task { await auth.refresh() } }
                .buttonStyle(.bordered)
        }
    }

    private func planBadge(_ plan: String) -> some View {
        Text(plan.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(plan == "pro" ? Color.mint : Color.secondary.opacity(0.2)))
            .foregroundStyle(plan == "pro" ? Color.black : Color.secondary)
    }
}
