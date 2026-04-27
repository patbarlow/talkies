import AVFoundation

@MainActor
final class Recorder: ObservableObject {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var outputURL: URL?

    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
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
            let level = Self.rms(from: buffer)
            AudioLevels.shared.pushFromAudioThread(rms: level)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
