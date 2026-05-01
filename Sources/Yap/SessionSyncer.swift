import Foundation

@MainActor
final class SessionSyncer {
    static let shared = SessionSyncer()
    private init() {}

    private let batchSize = 200

    func syncEntry(_ entry: RecordingEntry) async {
        guard let session = Settings.shared.sessionToken else { return }
        do {
            try await APIClient.shared.syncSessions(events: [entry], session: session)
            Library.shared.markSynced(ids: [entry.id])
            // Server recomputed user totals from sessions — pull fresh counts so
            // both the Home and Account screens reflect the updated number.
            await AuthStore.shared.refresh()
        } catch {
            // Will be picked up by syncPending on next launch
        }
    }

    func syncPending() async {
        guard let session = Settings.shared.sessionToken else { return }
        let pending = Library.shared.entries.filter { $0.syncedAt == nil }
        guard !pending.isEmpty else { return }

        var synced = false
        for chunk in pending.chunked(into: batchSize) {
            do {
                try await APIClient.shared.syncSessions(events: chunk, session: session)
                Library.shared.markSynced(ids: chunk.map { $0.id })
                synced = true
            } catch {
                break
            }
        }
        if synced { await AuthStore.shared.refresh() }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
