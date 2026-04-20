import SwiftUI

@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var selection: SettingsView.Pane = .home
    private init() {}
}

struct SettingsView: View {
    @StateObject private var router = SettingsRouter.shared
    @StateObject private var auth = AuthStore.shared
    @StateObject private var settings = Settings.shared

    enum Pane: String, Hashable, CaseIterable, Identifiable {
        case home, library
        case hotkey, cleanup, vocabulary
        case account, permissions, keys
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .library: "Library"
            case .hotkey: "Hotkey"
            case .cleanup: "Cleanup"
            case .vocabulary: "Vocabulary"
            case .account: "Account"
            case .permissions: "Permissions"
            case .keys: "API Keys"
            case .about: "About"
            }
        }

        var systemIcon: String {
            switch self {
            case .home: "house.fill"
            case .library: "waveform"
            case .hotkey: "keyboard.fill"
            case .cleanup: "sparkles"
            case .vocabulary: "book.fill"
            case .account: "person.fill"
            case .permissions: "checkmark.shield.fill"
            case .keys: "key.fill"
            case .about: "info.circle.fill"
            }
        }

        var tile: LinearGradient {
            switch self {
            case .home: Tile.home
            case .library: Tile.library
            case .hotkey: Tile.hotkey
            case .cleanup: Tile.cleanup
            case .vocabulary: Tile.vocab
            case .account: Tile.account
            case .permissions: Tile.perms
            case .keys: Tile.keys
            case .about: Tile.about
            }
        }
    }

    var body: some View {
        Group {
            if !auth.isSignedIn && !settings.hasSkippedSignIn {
                SignInPane()
            } else {
                splitView
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .tint(.mint)
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $router.selection) {
                row(.home)
                row(.library)

                Section("Dictation") {
                    row(.hotkey)
                    row(.cleanup)
                    row(.vocabulary)
                }

                Section("Setup") {
                    row(.account)
                    row(.permissions)
                    row(.keys)
                }

                Section("Talkies") {
                    row(.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ScrollView {
                Group {
                    switch router.selection {
                    case .home: HomePane()
                    case .library: LibraryPane()
                    case .hotkey: HotkeyPane()
                    case .cleanup: CleanupPane()
                    case .vocabulary: VocabularyPane()
                    case .account: AccountPane()
                    case .permissions: PermissionsPane()
                    case .keys: KeysPane()
                    case .about: AboutPane()
                    }
                }
                .padding(24)
            }
            .navigationTitle(router.selection.title)
        }
    }

    private func row(_ pane: Pane) -> some View {
        Label {
            Text(pane.title)
        } icon: {
            IconTile(systemName: pane.systemIcon, gradient: pane.tile)
        }
        .tag(pane)
    }
}

// MARK: - Home

struct HomePane: View {
    @StateObject private var stats = Stats.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back")
                    .font(.largeTitle.bold())
                Text("Hold **\(Settings.shared.hotkey.label)** anywhere to dictate.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                StatCell(value: stats.weekWords.formatted(), unit: nil, label: "Words this week")
                StatDivider()
                StatCell(value: stats.totalWords.formatted(), unit: nil, label: "Total words")
                StatDivider()
                StatCell(value: "\(Int(stats.averageWPM))", unit: "WPM", label: "Average speed")
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

            VStack(alignment: .leading, spacing: 0) {
                Text("Get started")
                    .font(.title3.bold())
                    .padding(.bottom, 8)

                ChecklistRow(
                    symbol: "smallcircle.filled.circle",
                    title: "Start recording",
                    subtitle: "Hold \(Settings.shared.hotkey.label) and speak. Release to paste."
                ) {
                    Text(Settings.shared.hotkey.label)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
                }
                ChecklistRow(
                    symbol: "hand.point.up.left",
                    title: "Customize your shortcut",
                    subtitle: "Change the push-to-talk key in Hotkey settings."
                )
                ChecklistRow(
                    symbol: "sparkles",
                    title: "Turn on cleanup",
                    subtitle: "Fix mis-hearings and strip filler words automatically."
                )
                ChecklistRow(
                    symbol: "book",
                    title: "Add vocabulary",
                    subtitle: "Teach Talkies names, jargon, or product terms."
                )
            }

            Spacer(minLength: 0)
        }
    }
}

private struct StatCell: View {
    let value: String
    let unit: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 6)
    }
}

private struct ChecklistRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    var trailing: Trailing

    init(symbol: String, title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 10)
    }
}

extension ChecklistRow where Trailing == EmptyView {
    init(symbol: String, title: String, subtitle: String) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Hotkey

struct HotkeyPane: View {
    @StateObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hold to dictate. Release to transcribe and paste into the frontmost app.")
                .foregroundStyle(.secondary)
                .font(.callout)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push to talk").font(.body.weight(.medium))
                    Text("Hold this key to start recording.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HotkeyRecorder(spec: Binding(
                    get: { settings.hotkey },
                    set: { settings.hotkey = $0 }
                ))
                .frame(width: 300)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

            Text("Modifier keys (Right ⌘, fn, …) cancel automatically if another key is pressed, so regular shortcuts like ⌘C still work.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Keys

struct KeysPane: View {
    @StateObject private var settings = Settings.shared
    @State private var groqDraft = ""
    @State private var anthropicDraft = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keys are stored in macOS Keychain under `app.talkies.Talkies`.")
                .foregroundStyle(.secondary)
                .font(.callout)

            VStack(spacing: 0) {
                keyRow(title: "Groq", subtitle: "Used for transcription (Whisper Large v3)", binding: $groqDraft)
                Divider()
                keyRow(title: "Anthropic", subtitle: "Optional — powers the cleanup pass", binding: $anthropicDraft)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

            HStack {
                Button("Save keys") {
                    if !groqDraft.isEmpty { settings.setGroqKey(groqDraft) }
                    if !anthropicDraft.isEmpty { settings.setAnthropicKey(anthropicDraft) }
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }
            Spacer()
        }
        .onAppear {
            groqDraft = settings.groqKey ?? ""
            anthropicDraft = settings.anthropicKey ?? ""
        }
    }

    private func keyRow(title: String, subtitle: String, binding: Binding<String>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SecureField("sk-…", text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
        }
        .padding(16)
    }
}

// MARK: - Cleanup

struct CleanupPane: View {
    @StateObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run cleanup pass after transcription").font(.body.weight(.medium))
                    Text("Uses Claude Haiku to polish the output.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.cleanupEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(.mint)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

            Text("Strips filler words (um, uh, like), fixes obvious mis-hearings, and gently matches the tone of the frontmost app. Adds ~200 ms of latency and costs fractions of a cent per dictation.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Vocabulary

struct VocabularyPane: View {
    @StateObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal dictionary").font(.title3.bold())
            Text("Add names, jargon, and product terms — one per line or comma-separated. Passed to Whisper as a prompt to bias recognition.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: Binding(
                get: { settings.customVocabulary ?? "" },
                set: { settings.customVocabulary = $0 }
            ))
            .font(.body.monospaced())
            .frame(minHeight: 240)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

            Spacer()
        }
    }
}
