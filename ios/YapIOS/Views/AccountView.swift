import SwiftUI
import PhotosUI
import StoreKit

struct AccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var profileImage = ProfileImage.shared
    @StateObject private var iap = IAPManager.shared

    @State private var nameDraft = ""
    @State private var photoPicker: PhotosPickerItem?
    @State private var showSignOutConfirm = false

    var body: some View {
        List {
            if let user = auth.currentUser {
                identitySection(user: user)
                usageSection(user: user)
                if user.plan == "free" {
                    upgradeSection
                }
                accountActions
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .task { await auth.refresh() }
        .onAppear {
            if nameDraft.isEmpty { nameDraft = auth.currentUser?.name ?? "" }
            Task { await iap.loadProducts() }
        }
        .onChange(of: auth.currentUser?.name) { _, new in nameDraft = new ?? "" }
        .onChange(of: photoPicker) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    profileImage.save(image: image)
                }
            }
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { auth.signOut() }
        }
    }

    // MARK: - Identity

    private func identitySection(_ user: PublicUser) -> some View {
        Section {
            HStack(spacing: 14) {
                PhotosPicker(selection: $photoPicker, matching: .images) {
                    avatarView(user: user)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Your name", text: $nameDraft)
                        .font(.headline)
                        .submitLabel(.done)
                        .onSubmit { Task { await saveName() } }
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                planBadge(user.plan)
            }
            .padding(.vertical, 4)
        }
    }

    private func avatarView(user: PublicUser) -> some View {
        ZStack {
            if let img = profileImage.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(initials(for: user.name, email: user.email))
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    )
            }
            if profileImage.isSyncing {
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 56, height: 56)
                    .overlay(ProgressView().tint(.white))
            } else {
                // Camera badge
                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    )
                    .offset(x: 20, y: 20)
            }
        }
    }

    // MARK: - Usage

    private func usageSection(_ user: PublicUser) -> some View {
        Section("Weekly usage") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let limit = user.weekLimit {
                        Text("\(user.weekWords.formatted()) / \(limit.formatted()) words")
                            .font(.callout).monospacedDigit()
                    } else {
                        Text("\(user.weekWords.formatted()) words · unlimited")
                            .font(.callout).monospacedDigit()
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        Text(resetLabel(weekStart: user.weekStart, at: ctx.date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let limit = user.weekLimit {
                    ProgressView(value: min(Double(user.weekWords) / Double(limit), 1.0))
                        .tint(user.weekWords >= limit ? .red : .mint)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Upgrade

    private var upgradeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Yap Pro", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.mint)
                Text("Unlimited words every week. Supports development.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if iap.isLoadingProducts {
                    ProgressView()
                } else {
                    ForEach(iap.products, id: \.id) { product in
                        upgradeButton(product)
                    }
                }

                if let error = iap.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Restore purchases") {
                    Task { await iap.restorePurchases() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func upgradeButton(_ product: Product) -> some View {
        Button {
            Task { await iap.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.callout.weight(.medium))
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.mint)
            }
        }
        .disabled(iap.isPurchasing)
        .buttonStyle(.plain)
    }

    // MARK: - Sign out

    private var accountActions: some View {
        Section {
            Button("Sign out", role: .destructive) {
                showSignOutConfirm = true
            }
        }
    }

    // MARK: - Helpers

    private var nameDirty: Bool {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (auth.currentUser?.name ?? "")
    }

    private func saveName() async {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (auth.currentUser?.name ?? "") else { return }
        await auth.updateName(trimmed)
    }

    private func initials(for name: String?, email: String) -> String {
        if let name, !name.isEmpty {
            let parts = name.split(separator: " ").prefix(2)
            return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        }
        return String(email.prefix(1)).uppercased()
    }

    private func planBadge(_ plan: String) -> some View {
        Text(plan.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(plan == "pro" ? Color.mint : Color.secondary.opacity(0.2)))
            .foregroundStyle(plan == "pro" ? Color.black : Color.secondary)
    }

    private func resetLabel(weekStart: String, at now: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        let start = iso.date(from: weekStart) ?? iso2.date(from: weekStart)
        guard let start,
              let next = Calendar.current.date(byAdding: .day, value: 7, to: start)
        else { return "Resets weekly" }
        let remaining = next.timeIntervalSince(now)
        guard remaining > 0 else { return "Resetting soon" }
        if remaining > 86400 {
            let df = DateFormatter(); df.dateFormat = "EEE h:mm a"
            return "Resets \(df.string(from: next))"
        } else {
            let h = Int(remaining) / 3600
            let m = (Int(remaining) % 3600) / 60
            return h > 0 ? "Resets in \(h) hr \(m) min" : "Resets in \(m) min"
        }
    }
}
