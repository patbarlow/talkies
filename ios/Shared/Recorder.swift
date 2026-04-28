import AVFoundation

@MainActor
final class Recorder: ObservableObject {
    // Engine and session are created once and kept alive for the lifetime of
    // the Recorder. Recreating the engine or toggling setActive(false/true)
    // between recordings causes AVAudioEngine.start() to throw error 'what'
    // (com.apple.coreaudio.avfaudio 2003329396) on iOS keyboard extensions —
    // the session reactivates but the input node reports a stale format before
    // the hardware has re-initialized.
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var outputURL: URL?

    func start() throws {
        // Drop any tap from a previous recording before installing a new one.
        engine?.inputNode.removeTap(onBus: 0)

        if engine == nil {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            engine = AVAudioEngine()
        }

        let eng = engine!
        let input = eng.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("yap-\(UUID().uuidString).wav")
        outputURL = url

        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sourceFormat.sampleRate,
            AVNumberOfChannelsKey: sourceFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: fileSettings)
        AudioLevels.shared.reset()

        input.installTap(onBus: 0, bufferSize: 4096, format: sourceFormat) { [weak self] buffer, _ in
            try? self?.file?.write(from: buffer)
            AudioLevels.shared.pushFromAudioThread(rms: Self.rms(from: buffer))
        }
        eng.prepare()
        try eng.start()
    }

    func stop() -> URL? {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        Task { @MainActor in AudioLevels.shared.reset() }
        let url = outputURL
        file = nil
        outputURL = nil
        return url
    }

    private static func rms(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let samples = channelData[0]
        var sum: Float = 0
        var i = 0
        while i < frames {
            let s = samples[i]
            sum += s * s
            i += 1
        }
        return (sum / Float(frames)).squareRoot()
    }
}
