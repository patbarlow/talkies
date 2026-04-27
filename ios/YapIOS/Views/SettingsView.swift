import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var settings: SharedSettings
    @StateObject private var profileImage = ProfileImage.shared

    var body: some View {
        NavigationStack {
            List {
                // Account row
                NavigationLink(destination: AccountView()) {
                    accountRow
                }

                // Keyboard setup
                NavigationLink(destination: KeyboardSetupView()) {
                    Label("Keyboard setup", systemImage: "keyboard.fill")
                }

                // Style
                NavigationLink(destination: StyleView()) {
                    Label("AI cleanup & language", systemImage: "sparkles")
                }

                // Vocabulary
                NavigationLink(destination: VocabularyView()) {
                    Label("Custom vocabulary", systemImage: "text.quote")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://yap.app")!) {
                        Label("Website", systemImage: "globe")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var accountRow: some View {
        HStack(spacing: 12) {
            if let img = profileImage.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(initials)
                            .font(.callout.bold())
                            .foregroundStyle(.white)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.currentUser?.name ?? auth.currentUser?.email ?? "Account")
                    .font(.callout.weight(.medium))
                if let plan = auth.currentUser?.plan {
                    Text(plan == "pro" ? "Yap Pro" : "Free plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var initials: String {
        if let name = auth.currentUser?.name, !name.isEmpty {
            let parts = name.split(separator: " ").prefix(2)
            return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        }
        return String(auth.currentUser.map { String($0.email.prefix(1)) } ?? "?").uppercased()
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
