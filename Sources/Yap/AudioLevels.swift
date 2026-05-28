import Foundation
import SwiftUI

/// Shared audio-level store. The `Recorder`'s tap pushes RMS values into it,
/// and the recording pill observes `bars` to animate in sync with the mic.
@MainActor
final class AudioLevels: ObservableObject {
    static let shared = AudioLevels()

    /// Current normalized mic level in [0, 1], updated each tap fire (~11Hz
    /// at the recorder's default buffer size). The recording pill uses this
    /// as the source of truth — every bar reacts to the *same* current
    /// reading with a per-bar amplitude shape, so the visualization moves
    /// with the voice instead of scrolling left-to-right like a ring buffer.
    @Published private(set) var currentLevel: CGFloat = 0
    /// Highest level seen since `resetForRecording`. Used by the dictation
    /// pipeline to gate out silent recordings (where Whisper would otherwise
    /// hallucinate "Thank you." or similar) before they hit the API.
    private(set) var peakLevel: CGFloat = 0

    private init() {}

    /// Called from an audio thread via the Recorder tap; dispatches to main.
    nonisolated func pushFromAudioThread(rms: Float) {
        // Map RMS → decibels → [0, 1]. Typical speech sits around −40…−10 dBFS.
        let db = 20 * log10f(max(rms, 0.0001))
        let normalized = max(0, min(1, CGFloat(db + 50) / 50))
        Task { @MainActor in
            self.push(normalized)
        }
    }

    /// Clears the visual level only. Called when the visual pill goes away;
    /// preserves peakLevel so the pipeline can still gate on silence after
    /// stop().
    func reset() {
        currentLevel = 0
    }

    /// Clears level *and* peak. Call at the start of each recording.
    func resetForRecording() {
        currentLevel = 0
        peakLevel = 0
    }

    private func push(_ value: CGFloat) {
        currentLevel = value
        if value > peakLevel { peakLevel = value }
    }
}
