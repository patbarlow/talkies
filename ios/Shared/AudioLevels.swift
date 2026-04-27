import Foundation
import SwiftUI

@MainActor
final class AudioLevels: ObservableObject {
    static let shared = AudioLevels()

    @Published private(set) var bars: [CGFloat]

    private let barCount: Int

    private init(barCount: Int = 5) {
        self.barCount = barCount
        self.bars = Array(repeating: 0.08, count: barCount)
    }

    nonisolated func pushFromAudioThread(rms: Float) {
        let db = 20 * log10f(max(rms, 0.0001))
        let normalized = max(0, min(1, CGFloat(db + 50) / 50))
        Task { @MainActor in self.push(normalized) }
    }

    func reset() {
        bars = Array(repeating: 0.08, count: barCount)
    }

    private func push(_ value: CGFloat) {
        var next = bars
        next.removeFirst()
        next.append(value)
        bars = next
    }
}
