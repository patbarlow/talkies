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

    enum Pane: String, Hashable, CaseIterable, Identifiable {
        case home, library
        case hotkey, cleanup, vocabulary
        case account, permissions
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
            case .about: Tile.about
            }
        }
    }

    var body: some View {
        Group {
            if !auth.isSignedIn {
                SignInPane()
            } else {
                mainLayout
            }
        }
        .frame(width: 860, height: 580)
        .tint(.mint)
    }

    // Manual HStack layout rather than NavigationSplitView. NavigationSplitView
    // always applies a translucent sidebar material + a resizable splitter —
    // neither of which we want. This gives us a flat sidebar flush with the
    // window edge, fixed width, no splitter.
    private var mainLayout: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                sidebarRow(.home)
                sidebarRow(.library)

                sectionHeader("Dictation")
                sidebarRow(.hotkey)
                sidebarRow(.cleanup)
                sidebarRow(.vocabulary)

                sectionHeader("Setup")
                sidebarRow(.account)
                sidebarRow(.permissions)

                sectionHeader("Yap")
                sidebarRow(.about)
            }
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }

    private func sidebarRow(_ pane: Pane) -> some View {
        let selected = router.selection == pane
        return Button {
            router.selection = pane
        } label: {
            HStack(spacing: 10) {
                IconTile(systemName: pane.systemIcon, gradient: pane.tile, size: 22)
                Text(pane.title)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(router.selection.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Group {
                    switch router.selection {
                    case .home: HomePane()
                    case .library: LibraryPane()
                    case .hotkey: HotkeyPane()
                    case .cleanup: CleanupPane()
                    case .vocabulary: VocabularyPane()
                    case .account: AccountPane()
                    case .permissions: PermissionsPane()
                    case .about: AboutPane()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    subtitle: "Teach Yap names, jargon, or product terms."
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
