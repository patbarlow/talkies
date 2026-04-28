import AVFoundation

@MainActor
final class Recorder: ObservableObject {
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var outputURL: URL?

    func start() throws {
        // Build a fresh engine for each recording.
        // Keyboard extension hosts can rapidly change audio routes; reusing a
        // prior input node can leave it in a bad state and trigger AVAudioEngine
        // start failures (com.apple.coreaudio.avfaudio 2003329396).
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .allowBluetooth])
        try session.setActive(true)

        let eng = AVAudioEngine()
        engine = eng
        let input = eng.inputNode
        var sourceFormat = input.inputFormat(forBus: 0)
        if sourceFormat.sampleRate <= 0 || sourceFormat.channelCount == 0 {
            sourceFormat = input.outputFormat(forBus: 0)
        }
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw RecorderError.invalidInputFormat
        }

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
        engine = nil
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

enum RecorderError: LocalizedError {
    case invalidInputFormat

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            return "Microphone isn't ready yet. Please try again."
        }
    }
}
