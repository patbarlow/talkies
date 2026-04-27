import Foundation

@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var entries: [RecordingEntry] = []

    private let fileURL: URL
    private let maxEntries = 5_000

    private init() {
        // Store in App Group container so both app and extension can append entries.
        let fm = FileManager.default
        let base: URL
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.app.yap") {
            base = groupURL
        } else {
            base = (try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fm.temporaryDirectory
        }
        let dir = base.appendingPathComponent("Library", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("library.json")
        load()
    }

    @discardableResult
    func record(
        raw: String,
        final: String,
        duration: TimeInterval,
        appName: String?,
        bundleID: String?,
        cleanupLevel: String?,
        language: String?
    ) -> RecordingEntry? {
        let wc = final.split(whereSeparator: { $0.isWhitespace }).count
        guard wc > 0 else { return nil }
        let entry = RecordingEntry(
            id: UUID(),
            timestamp: Date(),
            rawText: raw,
            finalText: final,
            durationSeconds: max(0, duration),
            wordCount: wc,
            appName: appName,
            bundleID: bundleID,
            cleanupLevel: cleanupLevel,
            language: language,
            syncedAt: nil
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
        return entry
    }

    func markSynced(ids: [UUID]) {
        let idSet = Set(ids)
        let now = Date()
        for i in entries.indices where idSet.contains(entries[i].id) {
            entries[i].syncedAt = now
        }
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        entries = []
        save()
    }

    // Called after the keyboard extension adds an entry while the app is open.
    func reload() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([RecordingEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
