import Foundation
import SwiftUI

/// Shared audio-level store. The `Recorder`'s tap pushes RMS values into it,
/// and the recording pill observes `bars` to animate in sync with the mic.
@MainActor
final class AudioLevels: ObservableObject {
    static let shared = AudioLevels()

    /// Fixed-size ring of recent levels, mapped to [0, 1]. Oldest → newest.
    @Published private(set) var bars: [CGFloat]

    private let barCount: Int

    private init(barCount: Int = 5) {
        self.barCount = barCount
        self.bars = Array(repeating: 0.08, count: barCount)
    }

    /// Called from an audio thread via the Recorder tap; dispatches to main.
    nonisolated func pushFromAudioThread(rms: Float) {
        // Map RMS → decibels → [0, 1]. Typical speech sits around −40…−10 dBFS.
        let db = 20 * log10f(max(rms, 0.0001))
        let normalized = max(0, min(1, CGFloat(db + 50) / 50))
        Task { @MainActor in
            self.push(normalized)
        }
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
