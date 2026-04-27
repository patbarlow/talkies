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
    let advanceToNextKeyboard: () -> Void
    let insertText: (String) -> Void
    let hasFullAccess: Bool

    @StateObject private var settings = SharedSettings.shared
    @StateObject private var audioLevels = AudioLevels.shared
    @StateObject private var recorder = Recorder()

    @State private var state: KeyboardState = .idle
    @State private var recordingStart: Date?
    @State private var pulsing = false

    private let minimumRecordingDuration: TimeInterval = 0.5

    var body: some View {
        VStack(spacing: 0) {
            // State-specific info area fills remaining space
            infoArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Mic button is always in the layout so the DragGesture
            // persists through state transitions and onEnded always fires.
            micRow

            toolbar
                .frame(height: 44)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear(perform: checkInitialState)
    }

    // MARK: - Info area (state-specific, above the mic button)

    @ViewBuilder
    private var infoArea: some View {
        switch state {
        case .notSignedIn:
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Sign in to Yap")
                    .font(.subheadline.weight(.medium))
                Button("Open Yap") { openMainApp() }
                    .buttonStyle(.bordered)
                    .tint(.mint)
                    .controlSize(.small)
            }
            .padding(.horizontal)

        case .noFullAccess:
            VStack(spacing: 6) {
                Image(systemName: "mic.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Enable Full Access")
                    .font(.subheadline.weight(.medium))
                Text("Settings → General → Keyboard → Yap → Allow Full Access")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

        case .idle:
            VStack(spacing: 3) {
                Text("Hold to record")
                    .font(.subheadline.weight(.medium))
                Text("Release to transcribe & insert")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

        case .recording:
            VStack(spacing: 8) {
                WaveformView(bars: audioLevels.bars)
                    .frame(height: 36)
                    .padding(.horizontal, 20)
                Text("Release to stop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .processing:
            VStack(spacing: 8) {
                ProcessingDots()
                Text("Transcribing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .result(let text):
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
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

        case .error(let message):
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
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
    }

    // MARK: - Mic row (always visible so DragGesture survives state changes)

    private var micRow: some View {
        ZStack {
            // Expanding pulse ring shown only while recording
            Circle()
                .strokeBorder(Color.mint.opacity(0.35), lineWidth: 2)
                .frame(width: pulsing ? 84 : 62, height: pulsing ? 84 : 62)
                .opacity(pulsing ? 0 : 1)
                .animation(
                    state == .recording
                        ? .easeOut(duration: 1.1).repeatForever(autoreverses: false)
                        : .linear(duration: 0.15),
                    value: pulsing
                )

            // Main button circle
            Circle()
                .fill(micFill)
                .frame(width: 58, height: 58)
                .shadow(color: state == .recording ? Color.mint.opacity(0.35) : .clear, radius: 8, y: 2)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: state == .recording)

            Image(systemName: micIcon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(micIconColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: 72)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard case .idle = state else { return }
                    startRecording()
                }
                .onEnded { _ in
                    stopRecording()
                }
        )
        .allowsHitTesting(state != .processing)
        .onChange(of: state) { _, new in
            pulsing = (new == .recording)
        }
    }

    private var micFill: Color {
        switch state {
        case .recording: return .mint
        case .processing: return Color(uiColor: .tertiarySystemFill)
        default: return Color.mint.opacity(0.12)
        }
    }

    private var micIcon: String {
        switch state {
        case .recording: return "stop.fill"
        case .processing: return "ellipsis"
        default: return "mic.fill"
        }
    }

    private var micIconColor: Color {
        switch state {
        case .recording: return .white
        case .processing: return Color(uiColor: .tertiaryLabel)
        default: return .mint
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button(action: advanceToNextKeyboard) {
                Image(systemName: "globe")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            if case .idle = state {
                HStack(spacing: 5) {
                    Text(settings.transcriptionLanguage.whisperCode.uppercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                    if settings.cleanupLevel != .off {
                        Text("·")
                            .foregroundStyle(Color(uiColor: .quaternaryLabel))
                        Text(settings.cleanupLevel.label)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .transition(.opacity)
            }

            Spacer()

            Button(action: openMainApp) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 4)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        guard settings.sessionToken != nil else { state = .notSignedIn; return }
        guard hasFullAccess else { state = .noFullAccess; return }
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

    // MARK: - Transcription

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

            if let entry = Library.shared.record(
                raw: raw.text,
                final: trimmed,
                duration: duration,
                appName: nil,
                bundleID: nil,
                cleanupLevel: settings.cleanupLevel.rawValue,
                language: settings.transcriptionLanguage.whisperCode
            ) {
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
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        let app = UIApplication.value(forKeyPath: "sharedApplication") as AnyObject
        if app.responds(to: sel) {
            _ = app.perform(sel, with: url, with: [:])
        }
    }
}
