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
        } catch {
            // Will be picked up by syncPending on next launch
        }
    }

    func syncPending() async {
        guard let session = Settings.shared.sessionToken else { return }
        let pending = Library.shared.entries.filter { $0.syncedAt == nil }
        guard !pending.isEmpty else { return }

        for chunk in pending.chunked(into: batchSize) {
            do {
                try await APIClient.shared.syncSessions(events: chunk, session: session)
                Library.shared.markSynced(ids: chunk.map { $0.id })
            } catch {
                break
            }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
