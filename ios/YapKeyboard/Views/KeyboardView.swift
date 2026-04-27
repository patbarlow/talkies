import SwiftUI
import AVFoundation

enum KeyboardState: Equatable {
    case notSignedIn
    case noFullAccess
    case idle
    case recording
    case processing
    case result(String)
    case error(String)
}

struct KeyboardView: View {
    // Injected by KeyboardViewController so SwiftUI can call UIKit methods
    let advanceToNextKeyboard: () -> Void
    let insertText: (String) -> Void
    let hasFullAccess: Bool

    @StateObject private var settings = SharedSettings.shared
    @StateObject private var audioLevels = AudioLevels.shared
    @StateObject private var recorder = Recorder()

    @State private var state: KeyboardState = .idle
    @State private var recordingStart: Date?
    @State private var isDraggingMic = false

    private let minimumRecordingDuration: TimeInterval = 0.5

    var body: some View {
        VStack(spacing: 0) {
            centralArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            toolbar
                .frame(height: 44)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear(perform: checkInitialState)
    }

    // MARK: - Central area

    @ViewBuilder
    private var centralArea: some View {
        switch state {
        case .notSignedIn:
            notSignedInView

        case .noFullAccess:
            noFullAccessView

        case .idle:
            idleView

        case .recording:
            recordingView

        case .processing:
            processingView

        case .result(let text):
            resultView(text: text)

        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - State views

    private var notSignedInView: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Sign in to Yap")
                .font(.callout.weight(.medium))
            Text("Open the Yap app to sign in, then come back here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Open Yap") { openMainApp() }
                .buttonStyle(.bordered)
                .tint(.mint)
                .controlSize(.small)
        }
    }

    private var noFullAccessView: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Allow Full Access")
                .font(.callout.weight(.medium))
            Text("Settings → General → Keyboard → Keyboards → Yap → Allow Full Access")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            micButton
            Text("Hold to dictate")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var recordingView: some View {
        VStack(spacing: 12) {
            WaveformView(bars: audioLevels.bars)
                .frame(height: 48)
                .padding(.horizontal, 32)
            Text("Release to transcribe")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var processingView: some View {
        VStack(spacing: 12) {
            ProcessingDots()
            Text("Transcribing…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultView(text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.mint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            if case .result = state { state = .idle }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button("Dismiss") { state = .idle }
                .font(.caption)
                .foregroundStyle(.mint)
        }
    }

    // MARK: - Mic button

    private var micButton: some View {
        ZStack {
            Circle()
                .fill(isDraggingMic ? Color.mint : Color.mint.opacity(0.15))
                .frame(width: 64, height: 64)
                .animation(.easeInOut(duration: 0.1), value: isDraggingMic)

            Image(systemName: isDraggingMic ? "stop.fill" : "mic.fill")
                .font(.title2)
                .foregroundStyle(isDraggingMic ? .white : .mint)
                .animation(.easeInOut(duration: 0.1), value: isDraggingMic)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isDraggingMic {
                        isDraggingMic = true
                        startRecording()
                    }
                }
                .onEnded { _ in
                    isDraggingMic = false
                    stopRecording()
                }
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            // Globe: switch to next keyboard
            Button(action: advanceToNextKeyboard) {
                Image(systemName: "globe")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // Language code, or cleanup level while idle
            if case .idle = state {
                HStack(spacing: 6) {
                    Text(settings.transcriptionLanguage.whisperCode.uppercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if settings.cleanupLevel != .off {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(settings.cleanupLevel.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Gear: open main app settings
            Button(action: openMainApp) {
                Image(systemName: "gear")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 4)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        guard case .idle = state else { return }
        guard settings.sessionToken != nil else {
            state = .notSignedIn
            return
        }
        guard hasFullAccess else {
            state = .noFullAccess
            return
        }
        do {
            try recorder.start()
            recordingStart = Date()
            state = .recording
        } catch {
            state = .error("Couldn't start recording: \(error.localizedDescription)")
        }
    }

    private func stopRecording() {
        guard case .recording = state else {
            _ = recorder.stop()
            return
        }

        let elapsed = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        guard let wavURL = recorder.stop(), elapsed >= minimumRecordingDuration else {
            state = .idle
            return
        }

        state = .processing
        Task { await transcribeAndInsert(wavURL: wavURL, duration: elapsed) }
    }

    private func transcribeAndInsert(wavURL: URL, duration: TimeInterval) async {
        defer { try? FileManager.default.removeItem(at: wavURL) }

        guard let session = settings.sessionToken else {
            state = .notSignedIn
            return
        }

        do {
            let raw = try await APIClient.shared.transcribe(
                audio: wavURL,
                prompt: settings.customVocabulary,
                language: settings.transcriptionLanguage.whisperCode,
                session: session
            )

            var final = raw.text

            if settings.cleanupLevel != .off {
                final = (try? await APIClient.shared.cleanup(
                    text: raw.text,
                    appName: nil,
                    appBundleID: nil,
                    level: settings.cleanupLevel.rawValue,
                    tone: nil,
                    spellingVariant: settings.transcriptionLanguage.spellingVariant,
                    session: session
                )) ?? raw.text
            }

            let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                state = .idle
                return
            }

            insertText(trimmed + " ")

            // Persist to library
            Library.shared.record(
                raw: raw.text,
                final: trimmed,
                duration: duration,
                appName: nil,
                bundleID: nil,
                cleanupLevel: settings.cleanupLevel.rawValue,
                language: settings.transcriptionLanguage.whisperCode
            ).map { entry in
                Task { await SessionSyncer.shared.syncEntry(entry) }
            }

            state = .result(trimmed)

        } catch APIError.invalidSession {
            settings.setSessionToken(nil)
            state = .notSignedIn
        } catch APIError.weeklyLimitReached(let limit, let used) {
            state = .error("Weekly limit reached (\(used)/\(limit) words). Upgrade in the Yap app.")
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func checkInitialState() {
        if settings.sessionToken == nil {
            state = .notSignedIn
        } else if !hasFullAccess {
            state = .noFullAccess
        } else {
            state = .idle
        }
    }

    private func openMainApp() {
        guard let url = URL(string: "yapapp://") else { return }
        // Keyboard extensions can't open URLs via standard API. This reaches
        // through the responder chain to UIApplication, which works on iOS 17+
        // when the keyboard has Full Access. Silently no-ops if unavailable.
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        let app = UIApplication.value(forKeyPath: "sharedApplication") as AnyObject
        if app.responds(to: sel) {
            app.perform(sel, with: url, with: [:])
        }
    }
}
