import SwiftUI

struct StyleView: View {
    @EnvironmentObject private var settings: SharedSettings

    var body: some View {
        List {
            cleanupSection
            languageSection
        }
        .navigationTitle("Style")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Cleanup

    private var cleanupSection: some View {
        Section {
            ForEach(CleanupLevel.allCases, id: \.self) { level in
                cleanupRow(level)
            }
        } header: {
            Text("AI cleanup")
        } footer: {
            Text("Applied to every transcription from the Yap keyboard and the in-app recorder.")
        }
    }

    private func cleanupRow(_ level: CleanupLevel) -> some View {
        Button {
            settings.cleanupLevel = level
        } label: {
            HStack(spacing: 14) {
                cleanupIcon(level)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if settings.cleanupLevel == level {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.mint)
                        .font(.callout.weight(.semibold))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func cleanupIcon(_ level: CleanupLevel) -> some View {
        Image(systemName: iconName(for: level))
            .font(.title3)
            .foregroundStyle(level == settings.cleanupLevel ? .mint : .secondary)
            .frame(width: 28)
    }

    private func iconName(for level: CleanupLevel) -> String {
        switch level {
        case .off:    return "xmark.circle"
        case .clean:  return "sparkles"
        case .polish: return "wand.and.stars"
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section("Language") {
            Picker("Language", selection: $settings.transcriptionLanguage) {
                ForEach(TranscriptionLanguage.all) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }
}
