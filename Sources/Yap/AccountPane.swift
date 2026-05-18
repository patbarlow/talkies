import AppKit
import SwiftUI

struct AccountPane: View {
    @StateObject private var auth = AuthStore.shared
    @StateObject private var profileImage = ProfileImage.shared
    @StateObject private var stats = Stats.shared

    @State private var nameDraft: String = ""
    @State private var upgrading: Bool = false
    @State private var upgradeError: String?
    @State private var subInfo: APIClient.SubscriptionInfo?
    @State private var openingPortal: Bool = false
    @State private var portalError: String?

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
        .task {
            await auth.refresh()
            await loadSubscriptionIfNeeded()
        }
        .onAppear {
            if nameDraft.isEmpty { nameDraft = auth.currentUser?.name ?? "" }
        }
        .onChange(of: auth.currentUser?.name) { _, new in
            nameDraft = new ?? ""
        }
        .onChange(of: auth.currentUser?.plan) { _, _ in
            Task { await loadSubscriptionIfNeeded() }
        }
    }

    @ViewBuilder
    private var proPlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(.mint)
                    Text("Yap Pro").font(.body.weight(.semibold))
                }
                Spacer()
                if let info = subInfo {
                    Text(statusBadge(info))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor(info))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(statusColor(info).opacity(0.15)))
                }
            }

            if let info = subInfo {
                if let amount = formattedAmount(info) {
                    Text(amount).font(.callout).foregroundStyle(.secondary)
                }
                if let renewal = formattedRenewal(info) {
                    Text(renewal).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }

            Button(action: openPortal) {
                Text(openingPortal ? "Opening…" : "Manage subscription")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.bordered)
            .disabled(openingPortal)

            if let err = portalError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }

    private func statusBadge(_ info: APIClient.SubscriptionInfo) -> String {
        if info.cancelAtPeriodEnd { return "Cancels at period end" }
        switch info.status {
        case "active":   return "Active"
        case "trialing": return "Trialing"
        case "past_due": return "Past due"
        case "canceled", "unpaid": return "Inactive"
        default: return info.status.capitalized
        }
    }

    private func statusColor(_ info: APIClient.SubscriptionInfo) -> Color {
        if info.cancelAtPeriodEnd { return .orange }
        switch info.status {
        case "active", "trialing": return .mint
        case "past_due", "canceled", "unpaid": return .red
        default: return .secondary
        }
    }

    private func formattedAmount(_ info: APIClient.SubscriptionInfo) -> String? {
        guard let cents = info.amountCents, let currency = info.currency else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        let amount = Double(cents) / 100.0
        let priceStr = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        if let interval = info.interval {
            return "\(priceStr) / \(interval)"
        }
        return priceStr
    }

    private func formattedRenewal(_ info: APIClient.SubscriptionInfo) -> String? {
        guard let ts = info.currentPeriodEnd else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let df = DateFormatter()
        df.dateStyle = .medium
        let label = info.cancelAtPeriodEnd ? "Ends" : "Renews"
        return "\(label) \(df.string(from: date))"
    }

    private func openPortal() {
        guard let session = Settings.shared.sessionToken, !openingPortal else { return }
        openingPortal = true
        portalError = nil
        Task {
            defer { openingPortal = false }
            do {
                let url = try await APIClient.shared.stripePortal(session: session)
                NSWorkspace.shared.open(url)
            } catch {
                portalError = error.localizedDescription
            }
        }
    }

    private func loadSubscriptionIfNeeded() async {
        guard auth.currentUser?.plan == "pro",
              let session = Settings.shared.sessionToken else {
            subInfo = nil
            return
        }
        do {
            subInfo = try await APIClient.shared.stripeSubscription(session: session)
        } catch {
            // Not fatal — just leave subInfo nil and the card shows "Loading…".
            NSLog("Yap: subscription load error \(error)")
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

            let localWords = min(stats.weekWords, user.weekWords)
            let otherWords = max(0, user.weekWords - localWords)
            SplitProgressBar(thisMac: localWords, otherDevices: otherWords, limit: user.weekLimit)

            if user.weekWords > 0 {
                HStack(spacing: 16) {
                    Label {
                        Text("\(localWords.formatted()) this Mac")
                            .font(.caption).monospacedDigit()
                    } icon: {
                        Circle().fill(Color.mint).frame(width: 8, height: 8)
                    }
                    .labelStyle(DotLabelStyle())
                    if otherWords > 0 {
                        Label {
                            Text("\(otherWords.formatted()) other devices")
                                .font(.caption).monospacedDigit()
                        } icon: {
                            Circle().fill(Color.mint.opacity(0.4)).frame(width: 8, height: 8)
                        }
                        .labelStyle(DotLabelStyle())
                    }
                }
                .foregroundStyle(.secondary)
            }

            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                Text(resetLabel(weekStart: user.weekStart, at: ctx.date))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))

        // Plan card — different content for free vs pro
        if user.plan == "free" {
            VStack(alignment: .leading, spacing: 10) {
                Text("Upgrade to Yap Pro").font(.body.weight(.semibold))
                Text("Unlimited words per week. Refine selected text by voice. Supports development.")
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
        } else {
            proPlanCard
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

    // MARK: - Reset label

    private func resetLabel(weekStart: String, at now: Date) -> String {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        let start = isoFull.date(from: weekStart) ?? isoBasic.date(from: weekStart)
        guard let start,
              let nextReset = Calendar.current.date(byAdding: .day, value: 7, to: start)
        else { return "Resets weekly" }

        let remaining = nextReset.timeIntervalSince(now)
        guard remaining > 0 else { return "Resetting soon" }

        if remaining > 24 * 3600 {
            let df = DateFormatter()
            df.dateFormat = "EEE h:mm a"
            return "Resets \(df.string(from: nextReset))"
        } else {
            let hours = Int(remaining) / 3600
            let mins  = (Int(remaining) % 3600) / 60
            return hours > 0
                ? "Resets in \(hours) hr \(mins) min"
                : "Resets in \(mins) min"
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

// MARK: - SplitProgressBar

private struct SplitProgressBar: View {
    let thisMac: Int
    let otherDevices: Int
    let limit: Int?

    var body: some View {
        GeometryReader { geo in
            let cap = Double(max(limit ?? (thisMac + otherDevices), 1))
            let thisFrac  = min(Double(thisMac) / cap, 1.0)
            let otherFrac = min(Double(otherDevices) / cap, 1.0 - thisFrac)
            let w = geo.size.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 6)
                if thisFrac + otherFrac > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.mint.opacity(0.4))
                        .frame(width: w * CGFloat(thisFrac + otherFrac), height: 6)
                }
                if thisFrac > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.mint)
                        .frame(width: w * CGFloat(thisFrac), height: 6)
                }
            }
        }
        .frame(height: 6)
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
