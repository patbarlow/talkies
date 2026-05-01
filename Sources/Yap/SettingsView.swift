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
    @Environment(\.colorScheme) private var colorScheme

    private var background: Color {
        colorScheme == .dark
            ? Color(nsColor: .underPageBackgroundColor)
            : Color(white: 0.945)
    }

    enum Pane: String, Hashable, CaseIterable, Identifiable {
        case home, library
        case hotkey, style, vocabulary
        case account, permissions
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .library: "Library"
            case .hotkey: "Hotkey"
            case .style: "Style"
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
            case .style: "sparkles"
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
            case .style: Tile.cleanup
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
        .background(background.ignoresSafeArea())
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
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(background)
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            sidebarRow(.home)
            sidebarRow(.library)

            sectionHeader("Dictation")
            sidebarRow(.hotkey)
            sidebarRow(.style)
            sidebarRow(.vocabulary)

            sectionHeader("Setup")
            sidebarRow(.account)
            sidebarRow(.permissions)

            sectionHeader("Yap")
            sidebarRow(.about)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
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
                Group {
                    switch router.selection {
                    case .home: HomePane()
                    case .library: LibraryPane()
                    case .hotkey: HotkeyPane()
                    case .style: StylePane()
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
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Home

struct HomePane: View {
    @StateObject private var stats = Stats.shared
    @StateObject private var auth = AuthStore.shared
    @StateObject private var library = Library.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back")
                    .font(.largeTitle.bold())
                Text("Hold **\(Settings.shared.hotkey.label)** anywhere to dictate.")
                    .foregroundStyle(.secondary)
            }

            // Prefer server totals (cross-device, source of truth); fall back to local
            // while the user object is loading or if offline.
            let weekWords  = auth.currentUser?.weekWords  ?? stats.weekWords
            let totalWords = auth.currentUser?.totalWords ?? stats.totalWords

            HStack(spacing: 0) {
                StatCell(value: weekWords.formatted(),  unit: nil,   label: "Words this week")
                StatDivider()
                StatCell(value: totalWords.formatted(), unit: nil,   label: "Total words")
                StatDivider()
                StatCell(value: "\(Int(stats.averageWPM))", unit: "WPM", label: "Average speed")
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))

            if !library.entries.isEmpty {
                InsightsCard(entries: library.entries)
            }

            Spacer(minLength: 0)
        }
        .task { await auth.refresh() }
    }
}

private struct InsightsCard: View {
    let entries: [RecordingEntry]

    private var topApps: [(name: String, words: Int)] {
        Dictionary(grouping: entries.filter { $0.appName != nil }, by: { $0.appName! })
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.wordCount }) }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0 }
    }

    private var peakHour: Int? {
        Dictionary(grouping: entries, by: { Calendar.current.component(.hour, from: $0.timestamp) })
            .mapValues { $0.count }
            .max(by: { $0.value < $1.value })?.key
    }

    private var peakWeekday: Int? {
        Dictionary(grouping: entries, by: { Calendar.current.component(.weekday, from: $0.timestamp) })
            .mapValues { $0.count }
            .max(by: { $0.value < $1.value })?.key
    }

    private var topAppPerWeekday: [(day: String, app: String)] {
        let cal = Calendar.current
        let syms = cal.shortWeekdaySymbols
        let byDay = Dictionary(
            grouping: entries.filter { $0.appName != nil },
            by: { cal.component(.weekday, from: $0.timestamp) }
        )
        return (1...7).compactMap { wd -> (String, String)? in
            guard let day = byDay[wd] else { return nil }
            let top = Dictionary(grouping: day, by: { $0.appName! })
                .mapValues { $0.reduce(0) { $0 + $1.wordCount } }
                .max(by: { $0.value < $1.value })?.key
            guard let top else { return nil }
            return (syms[wd - 1], top)
        }
    }

    private func hourRangeLabel(_ hour: Int) -> String {
        var c1 = DateComponents(); c1.hour = hour
        var c2 = DateComponents(); c2.hour = (hour + 1) % 24
        let fmt = DateFormatter(); fmt.dateFormat = "ha"
        let cal = Calendar.current
        let d1 = cal.date(from: c1) ?? Date()
        let d2 = cal.date(from: c2) ?? Date()
        return "\(fmt.string(from: d1).lowercased())–\(fmt.string(from: d2).lowercased())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your patterns")
                .font(.body.weight(.semibold))

            let apps = topApps
            if !apps.isEmpty {
                topAppsSection(apps)
            }

            let hour = peakHour
            let wd   = peakWeekday
            if hour != nil || wd != nil {
                Divider()
                HStack(alignment: .top, spacing: 32) {
                    if let hour {
                        insightCell(label: "Peak hour", value: hourRangeLabel(hour))
                    }
                    if let wd {
                        insightCell(label: "Most active day",
                                    value: Calendar.current.weekdaySymbols[wd - 1])
                    }
                }
            }

            let perDay = topAppPerWeekday
            if perDay.count >= 2 {
                Divider()
                perDaySection(perDay)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }

    @ViewBuilder
    private func topAppsSection(_ apps: [(name: String, words: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top apps")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            let maxWords = CGFloat(apps.first?.words ?? 1)
            ForEach(Array(apps.enumerated()), id: \.offset) { i, app in
                HStack(spacing: 8) {
                    Text("#\(i + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, alignment: .leading)
                    Text(app.name)
                        .font(.callout)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.1)).frame(width: 90, height: 6)
                        Capsule().fill(Color.mint)
                            .frame(width: 90 * CGFloat(app.words) / maxWords, height: 6)
                    }
                    Text(app.words.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private func insightCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
        }
    }

    @ViewBuilder
    private func perDaySection(_ items: [(day: String, app: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top app by day")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()),
                          GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading, spacing: 8
            ) {
                ForEach(items, id: \.day) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.day)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(item.app)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
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

// MARK: - Hotkey

struct HotkeyPane: View {
    @StateObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
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
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))

            Text("Modifier keys (Right ⌘, fn, …) cancel automatically if another key is pressed, so regular shortcuts like ⌘C still work.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Style

struct StylePane: View {
    @StateObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            languageSection
            cleanupSection
            Spacer(minLength: 0)
        }
    }

    // MARK: Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Language").font(.body.weight(.semibold))
            Text("The language you speak. Sets spelling for English variants.")
                .font(.callout).foregroundStyle(.secondary)

            Picker("Language", selection: $settings.transcriptionLanguage) {
                ForEach(TranscriptionLanguage.all) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }

    // MARK: Cleanup level

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup").font(.body.weight(.semibold))

            HStack(spacing: 10) {
                ForEach(CleanupLevel.allCases, id: \.self) { level in
                    cleanupCard(level)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }

    private func cleanupCard(_ level: CleanupLevel) -> some View {
        let selected = settings.cleanupLevel == level
        return Button { settings.cleanupLevel = level } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(level.label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? .white : .primary)
                Text(level.description)
                    .font(.caption)
                    .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.clear : Color.primary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

}

// MARK: - Vocabulary

struct VocabularyPane: View {
    @StateObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal dictionary").font(.body.weight(.semibold))
            Text("Add names, jargon, and product terms — one per line or comma-separated. Passed to the transcription engine as context to bias recognition.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: Binding(
                get: { settings.customVocabulary ?? "" },
                set: { settings.customVocabulary = $0 }
            ))
            .font(.body.monospaced())
            .frame(minHeight: 240)
            .scrollContentBackground(.hidden)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }
}
