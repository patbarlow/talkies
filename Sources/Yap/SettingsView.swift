import Carbon.HIToolbox
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
    @State private var hoveredPane: Pane?

    private var background: Color {
        colorScheme == .dark
            ? Color(nsColor: .underPageBackgroundColor)
            : Color(white: 0.945)
    }

    enum Pane: String, Hashable, CaseIterable, Identifiable {
        case home, library
        case dictate, refine
        case account, permissions
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .library: "Library"
            case .dictate: "Dictate"
            case .refine: "Refine"
            case .account: "Account"
            case .permissions: "Permissions"
            case .about: "About"
            }
        }

        var systemIcon: String {
            switch self {
            case .home: "house.fill"
            case .library: "waveform"
            case .dictate: "mic.fill"
            case .refine: "wand.and.stars"
            case .account: "person.fill"
            case .permissions: "checkmark.shield.fill"
            case .about: "info.circle.fill"
            }
        }

        var tile: LinearGradient {
            switch self {
            case .home: Tile.home
            case .library: Tile.library
            case .dictate: Tile.hotkey
            case .refine: Tile.edit
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

            sectionHeader("Voice")
            sidebarRow(.dictate)
            sidebarRow(.refine)

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
        let hovered = hoveredPane == pane && !selected
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
                    .fill(selected ? Color.accentColor : hovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .onHover { isHovering in hoveredPane = isHovering ? pane : nil }
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
                    case .dictate: DictatePane()
                    case .refine: RefinePane()
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

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        default:      base = "Good evening"
        }
        if let name = auth.currentUser?.name,
           let first = name.split(separator: " ").first.map(String.init),
           !first.isEmpty {
            return "\(base), \(first)"
        }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(greetingText)
                .font(.largeTitle.bold())

            let weekWords  = auth.currentUser?.weekWords  ?? stats.weekWords
            let totalWords = auth.currentUser?.totalWords ?? stats.totalWords

            HStack(spacing: 0) {
                StatCell(value: weekWords.formatted(),  unit: nil,   label: "Words this week")
                StatCell(value: totalWords.formatted(), unit: nil,   label: "Total words")
                StatCell(value: "\(Int(stats.averageWPM))", unit: "WPM", label: "Average speed")
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))

            if !library.entries.isEmpty || auth.currentUser?.patterns != nil {
                InsightsCard(
                    localEntries: library.entries,
                    serverPatterns: auth.currentUser?.patterns
                )
            }

            Spacer(minLength: 0)
        }
    }
}

private struct InsightsCard: View {
    let localEntries: [RecordingEntry]
    let serverPatterns: ServerPatterns?

    @State private var showAllDevices = true

    private struct AppUsage: Identifiable {
        let id = UUID()
        let name: String
        let bundleID: String?
        let words: Int
        let sessions: Int
    }

    private var topApps: [AppUsage] {
        if showAllDevices, let p = serverPatterns {
            return p.topApps.map { AppUsage(name: $0.appName, bundleID: $0.bundleID, words: $0.words, sessions: $0.sessions) }
        }
        return Dictionary(grouping: localEntries.filter { $0.appName != nil }, by: { $0.appName! })
            .map { name, group in
                AppUsage(name: name, bundleID: group.first?.bundleID,
                         words: group.reduce(0) { $0 + $1.wordCount }, sessions: group.count)
            }
            .sorted { $0.words > $1.words }
            .prefix(5).map { $0 }
    }

    private var wordsByDay: [(label: String, words: Int, pct: Double)] {
        if showAllDevices, let p = serverPatterns {
            let total = Double(p.wordsByWeekday.reduce(0) { $0 + $1.words })
            guard total > 0 else { return [] }
            let wdMap = Dictionary(uniqueKeysWithValues: p.wordsByWeekday.map { ($0.weekday, $0.words) })
            // Server: 0=Sun, 1=Mon…6=Sat → display Mon first
            let order: [(Int, String)] = [(1,"Mon"),(2,"Tue"),(3,"Wed"),(4,"Thu"),(5,"Fri"),(6,"Sat"),(0,"Sun")]
            return order.map { wd, label in
                let words = wdMap[wd] ?? 0
                return (label, words, Double(words) / total)
            }
        }
        let cal = Calendar.current
        let byDay = Dictionary(grouping: localEntries, by: { cal.component(.weekday, from: $0.timestamp) })
        let total = localEntries.reduce(0) { $0 + $1.wordCount }
        guard total > 0 else { return [] }
        // Cal weekday: 1=Sun, 2=Mon…7=Sat → display Mon first
        let order: [(Int, String)] = [(2,"Mon"),(3,"Tue"),(4,"Wed"),(5,"Thu"),(6,"Fri"),(7,"Sat"),(1,"Sun")]
        return order.map { wd, label in
            let words = (byDay[wd] ?? []).reduce(0) { $0 + $1.wordCount }
            return (label, words, Double(words) / Double(total))
        }
    }

    private var topHours: [(label: String, pct: Double)] {
        if showAllDevices, let p = serverPatterns {
            let total = Double(p.wordsByHour.reduce(0) { $0 + $1.words })
            guard total > 0 else { return [] }
            return p.wordsByHour
                .map { (hourRangeLabel($0.hour), Double($0.words) / total) }
                .sorted { $0.1 > $1.1 }
                .prefix(4).map { $0 }
        }
        let byHour = Dictionary(grouping: localEntries, by: { Calendar.current.component(.hour, from: $0.timestamp) })
        let total = localEntries.reduce(0) { $0 + $1.wordCount }
        guard total > 0 else { return [] }
        return byHour
            .map { hour, group in
                (hourRangeLabel(hour), Double(group.reduce(0) { $0 + $1.wordCount }) / Double(total))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(4).map { $0 }
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
        let apps = topApps
        let days = wordsByDay
        let hours = topHours
        let hasDays = days.contains(where: { $0.words > 0 })

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your patterns")
                    .font(.body.weight(.semibold))
                Spacer()
                if serverPatterns != nil {
                    DeviceToggle(showAllDevices: $showAllDevices)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                if !apps.isEmpty {
                    topAppsSection(apps)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !apps.isEmpty && (hasDays || !hours.isEmpty) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1)
                        .padding(.horizontal, 16)
                }

                if hasDays || !hours.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        if hasDays { byDaySection(days) }
                        if !hours.isEmpty { byHourSection(hours) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }

    @ViewBuilder
    private func topAppsSection(_ apps: [AppUsage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top apps")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(apps) { app in
                HStack(spacing: 8) {
                    AppIconView(bundleID: app.bundleID, size: 22, appName: app.name)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text("\(app.words.formatted()) words · \(app.sessions) session\(app.sessions == 1 ? "" : "s")")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func byDaySection(_ days: [(label: String, words: Int, pct: Double)]) -> some View {
        let maxPct = days.map(\.pct).max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            Text("Words by day")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(days, id: \.label) { item in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        if item.words > 0 {
                            Text("\(Int(item.pct * 100))%")
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(item.pct == maxPct ? Color.mint : Color.mint.opacity(0.3))
                            .frame(height: max(3, 36 * CGFloat(item.pct / (maxPct > 0 ? maxPct : 1))))
                        Text(item.label)
                            .font(.system(size: 9).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60)
        }
    }

    @ViewBuilder
    private func byHourSection(_ hours: [(label: String, pct: Double)]) -> some View {
        let maxPct = hours.map(\.pct).max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            Text("Peak hours")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(hours, id: \.label) { item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 140, height: 5)
                        Capsule()
                            .fill(Color.mint.opacity(0.8))
                            .frame(width: 140 * CGFloat(item.pct / maxPct), height: 5)
                    }
                    Text("\(Int(item.pct * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }
}

private struct DeviceToggle: View {
    @Binding var showAllDevices: Bool

    var body: some View {
        HStack(spacing: 0) {
            pill("All devices", selected: showAllDevices) { showAllDevices = true }
            pill("This Mac", selected: !showAllDevices) { showAllDevices = false }
        }
        .background(Capsule().stroke(Color.mint.opacity(0.4), lineWidth: 1))
        .clipShape(Capsule())
    }

    private func pill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(selected ? Color.mint : Color.clear)
                .foregroundStyle(selected ? Color.black : Color.secondary)
        }
        .buttonStyle(.plain)
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


// MARK: - Dictate

struct DictatePane: View {
    @StateObject private var settings = Settings.shared
    @State private var newVocabWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            shortcutRow
            languageRow
            cleanupSection
            vocabularySection
            Spacer(minLength: 0)
        }
    }

    private var shortcutRow: some View {
        HStack(alignment: .center) {
            Text("Shortcut").font(.body.weight(.semibold))
            Spacer()
            HotkeyPicker(spec: $settings.hotkey)
                .frame(width: 240)
        }
        .padding(16)
        .background(SettingsCard())
    }

    private var languageRow: some View {
        HStack(alignment: .center) {
            Text("Language").font(.body.weight(.semibold))
            Spacer()
            Picker("Language", selection: $settings.transcriptionLanguage) {
                ForEach(TranscriptionLanguage.all) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 240)
        }
        .padding(16)
        .background(SettingsCard())
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup").font(.body.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(CleanupLevel.allCases, id: \.self) { level in
                    cleanupCard(level)
                }
            }
        }
        .padding(16)
        .background(SettingsCard())
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
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
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

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal dictionary").font(.body.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Add a word or phrase, press Return", text: $newVocabWord)
                    .textFieldStyle(.plain)
                    .onSubmit { addVocabWord() }
                if !newVocabWord.isEmpty {
                    Button(action: addVocabWord) {
                        Image(systemName: "return")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))

            if !settings.vocabularyWords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(settings.vocabularyWords, id: \.self) { word in
                        HStack(spacing: 5) {
                            Text(word).font(.callout)
                            Button {
                                settings.vocabularyWords.removeAll { $0 == word }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
            }
        }
        .padding(16)
        .background(SettingsCard())
    }

    private func addVocabWord() {
        let word = newVocabWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !settings.vocabularyWords.contains(word) else {
            newVocabWord = ""
            return
        }
        settings.vocabularyWords.append(word)
        newVocabWord = ""
    }
}

// MARK: - Refine

struct RefinePane: View {
    @StateObject private var settings = Settings.shared
    @StateObject private var auth = AuthStore.shared
    @StateObject private var prefsCoord = PreferenceRecordingCoordinator()
    @State private var newPreference = ""
    @State private var exampleIndex = 0

    private let preferenceExamples: [String] = [
        "I prefer Australian spelling",
        "Don't use the word 'utilize'",
        "Use bullet points for lists",
        "Keep things casual and direct",
        "End emails with 'Cheers'",
        "Avoid em dashes",
        "Don't start sentences with 'So'",
    ]

    private var isPro: Bool { auth.currentUser?.plan == "pro" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isPro {
                ProUpgradeCard(
                    title: "Refine is a Pro feature",
                    detail: "Hold a shortcut to refine selected or copied text with a voice instruction. Set personal writing preferences so rewrites sound like you."
                )
            }
            Group {
                shortcutRow
                personalizationSection
            }
            .opacity(isPro ? 1.0 : 0.55)
            Spacer(minLength: 0)
        }
    }

    private var shortcutRow: some View {
        HStack(alignment: .center) {
            Text("Shortcut").font(.body.weight(.semibold))
            Spacer()
            HotkeyPicker(
                spec: Binding(
                    get: { settings.editHotkey },
                    set: { settings.editHotkey = $0 }
                ),
                disabled: !isPro
            )
            .frame(width: 240)
        }
        .padding(16)
        .background(SettingsCard())
    }

    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Personalisation").font(.body.weight(.semibold))
                Spacer()
                if case .recording = prefsCoord.phase {
                    Label("Recording…", systemImage: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if case .processing = prefsCoord.phase {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Extracting…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if case .error(let msg) = prefsCoord.phase {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }

            HStack(spacing: 10) {
                holdToRecordButton
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hold to record a preference")
                        .font(.callout.weight(.medium))
                    Text("e.g. \"\(preferenceExamples[exampleIndex])\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .id(exampleIndex)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onReceive(Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()) { _ in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        exampleIndex = (exampleIndex + 1) % preferenceExamples.count
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            HStack(spacing: 8) {
                TextField("Or type a preference and press Return", text: $newPreference)
                    .textFieldStyle(.plain)
                    .onSubmit { addPreference() }
                if !newPreference.isEmpty {
                    Button(action: addPreference) {
                        Image(systemName: "return")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))

            if !settings.personalPreferences.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(settings.personalPreferences, id: \.self) { pref in
                        HStack(spacing: 5) {
                            Text(pref).font(.callout).lineLimit(1)
                            Button {
                                settings.personalPreferences.removeAll { $0 == pref }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
            }
        }
        .padding(16)
        .background(SettingsCard())
    }

    private var holdToRecordButton: some View {
        let recording = (prefsCoord.phase == .recording)
        let processing = (prefsCoord.phase == .processing)
        return ZStack {
            Circle()
                .fill(recording ? Color.red : Color.accentColor)
                .frame(width: 44, height: 44)
            Image(systemName: recording ? "mic.fill" : "mic")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .opacity(processing ? 0.4 : 1.0)
        .scaleEffect(recording ? 1.08 : 1.0)
        .animation(.easeOut(duration: 0.12), value: recording)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard prefsCoord.phase == .idle else { return }
                    prefsCoord.start()
                }
                .onEnded { _ in
                    guard prefsCoord.phase == .recording else { return }
                    Task { await prefsCoord.stopAndExtract(appendingTo: settings) }
                }
        )
    }

    private func addPreference() {
        let p = newPreference.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !settings.personalPreferences.contains(p) else {
            newPreference = ""
            return
        }
        settings.personalPreferences.append(p)
        newPreference = ""
    }
}

// MARK: - Shared bits

private struct SettingsCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08))
            )
    }
}

struct ProUpgradeCard: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(.mint)
                    Text(title).font(.body.weight(.semibold))
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Upgrade") {
                NotificationCenter.default.post(name: .yapOpenAccount, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.mint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.mint.opacity(0.4)))
    }
}

@MainActor
final class PreferenceRecordingCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case processing
        case error(String)
    }

    @Published var phase: Phase = .idle

    private let recorder = Recorder()
    private var startedAt: Date?

    func start() {
        do {
            try recorder.start()
            startedAt = Date()
            phase = .recording
        } catch {
            phase = .error("Mic error: \(error.localizedDescription)")
            Self.scheduleErrorClear { [weak self] in
                if case .error = self?.phase { self?.phase = .idle }
            }
        }
    }

    func stopAndExtract(appendingTo settings: Settings) async {
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        let peak = AudioLevels.shared.peakLevel
        guard let url = recorder.stop() else {
            phase = .idle
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        if duration < 0.5 || peak < 0.15 {
            phase = .idle
            return
        }

        phase = .processing
        do {
            let (raw, _) = try await Transcriber.shared.transcribe(wavURL: url)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                phase = .idle
                return
            }
            guard let token = Settings.shared.sessionToken, !token.isEmpty else {
                phase = .error("Not signed in.")
                Self.scheduleErrorClear { [weak self] in
                    if case .error = self?.phase { self?.phase = .idle }
                }
                return
            }
            let extracted = try await APIClient.shared.extractPreferences(text: trimmed, session: token)
            for p in extracted {
                if !settings.personalPreferences.contains(p) {
                    settings.personalPreferences.append(p)
                }
            }
            phase = .idle
        } catch {
            phase = .error("Couldn't extract: \(error.localizedDescription)")
            Self.scheduleErrorClear { [weak self] in
                if case .error = self?.phase { self?.phase = .idle }
            }
        }
    }

    private static func scheduleErrorClear(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            MainActor.assumeIsolated { action() }
        }
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
