import SwiftUI
import AVFoundation

enum KeyboardState: Equatable {
    case notSignedIn
    case noFullAccess
    case needsAppActivation
    case idle
    case recording
    case processing
    case result(String)
    case error(String)
}

struct KeyboardView: View {
    let insertText: (String) -> Void
    let deleteBackward: () -> Void
    let hasFullAccess: Bool

    @StateObject private var settings = SharedSettings.shared
    @StateObject private var audioLevels = AudioLevels.shared
    @StateObject private var recorder = Recorder()

    @State private var state: KeyboardState = .idle
    @State private var recordingStart: Date?
    @State private var pulsing = false

    private let minimumRecordingDuration: TimeInterval = 0.5
    private let appWarmThreshold: TimeInterval = 180

    var body: some View {
        VStack(spacing: 0) {
            infoArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            micRow

            keyRow

            bottomStrip
        }
        .background(keyboardGlassBackground)
        .onAppear(perform: checkInitialState)
    }

    private var keyboardGlassBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.08),
                    Color.black.opacity(0.08),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.plusLighter)
        }
    }

    // MARK: - Info area

    @ViewBuilder
    private var infoArea: some View {
        switch state {
        case .notSignedIn:
            VStack(spacing: 8) {
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
            VStack(spacing: 4) {
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

        case .needsAppActivation:
            VStack(spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.mint)
                Text("Activate microphone once")
                    .font(.subheadline.weight(.medium))
                Text("Apple may require opening Yap first. Tap below, then swipe back here and try recording again.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Button("Open Yap") { openMainApp(warmup: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .controlSize(.small)
            }

        case .idle:
            VStack(spacing: 2) {
                Text("Hold to record")
                    .font(.subheadline.weight(.medium))
                Text("Release to transcribe & insert")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

        case .recording:
            VStack(spacing: 6) {
                WaveformView(bars: audioLevels.bars)
                    .frame(height: 32)
                    .padding(.horizontal, 24)
                Text("Release to stop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .processing:
            VStack(spacing: 6) {
                ProcessingDots()
                Text("Transcribing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .result(let text):
            VStack(spacing: 4) {
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
            VStack(spacing: 4) {
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

    // MARK: - Mic row (persistent — gesture survives state changes)

    private var micRow: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.mint.opacity(0.35), lineWidth: 2)
                .frame(width: pulsing ? 80 : 60, height: pulsing ? 80 : 60)
                .opacity(pulsing ? 0 : 1)
                .animation(
                    state == .recording
                        ? .easeOut(duration: 1.1).repeatForever(autoreverses: false)
                        : .linear(duration: 0.15),
                    value: pulsing
                )

            Circle()
                .fill(micFill)
                .frame(width: 56, height: 56)
                .shadow(color: state == .recording ? Color.mint.opacity(0.3) : .clear, radius: 8, y: 2)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: state == .recording)

            Image(systemName: micIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(micIconColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: 68)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard canAttemptRecording else { return }
                    startRecording()
                }
                .onEnded { _ in
                    stopRecording()
                }
        )
        .allowsHitTesting(state != .processing)
        .onChange(of: state) { _, new in pulsing = (new == .recording) }
    }

    private var micFill: Color {
        switch state {
        case .recording: return .mint
        case .processing: return Color(uiColor: .tertiarySystemFill)
        default: return Color(uiColor: .systemBackground)
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

    private var canAttemptRecording: Bool {
        switch state {
        case .idle, .needsAppActivation:
            return true
        default:
            return false
        }
    }

    // MARK: - Key row (space · backspace · return)

    private var keyRow: some View {
        HStack(spacing: 6) {
            keyButton(label: AnyView(
                Text("space").font(.system(size: 15))
            ), isWide: true) {
                insertText(" ")
            }

            keyButton(label: AnyView(
                Image(systemName: "delete.left").font(.system(size: 16))
            )) {
                deleteBackward()
            }

            keyButton(label: AnyView(
                Image(systemName: "return").font(.system(size: 16))
            )) {
                insertText("\n")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.clear)
    }

    private func keyButton(label: AnyView, isWide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .foregroundStyle(Color(uiColor: .label))
                .frame(minWidth: isWide ? nil : 46, maxWidth: isWide ? .infinity : nil, minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isWide ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.regularMaterial))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.7)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom strip (lang info · gear)

    private var bottomStrip: some View {
        HStack(spacing: 0) {
            if case .idle = state {
                HStack(spacing: 4) {
                    Text(settings.transcriptionLanguage.whisperCode.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color(uiColor: .quaternaryLabel))
                    if settings.cleanupLevel != .off {
                        Text("·").foregroundStyle(Color(uiColor: .quaternaryLabel))
                        Text(settings.cleanupLevel.label)
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: .quaternaryLabel))
                    }
                }
            }

            Spacer()

            Button(action: openMainApp) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 36)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 36)
        .background(.clear)
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        guard settings.sessionToken != nil else { state = .notSignedIn; return }
        guard hasFullAccess else { state = .noFullAccess; return }
        if needsAppWarmup {
            state = .needsAppActivation
            openMainApp(warmup: true)
            return
        }
        do {
            try recorder.start()
            recordingStart = Date()
            state = .recording
        } catch {
            if isKeyboardMicActivationError(error) {
                state = .needsAppActivation
                openMainApp(warmup: true)
                return
            }
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
        } else if needsAppWarmup {
            state = .needsAppActivation
        } else {
            state = .idle
        }
    }

    private var needsAppWarmup: Bool {
        guard let lastActive = SharedDefaults.date(for: .appBecameActiveAt) else { return true }
        return Date().timeIntervalSince(lastActive) > appWarmThreshold
    }

    private func isKeyboardMicActivationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.apple.coreaudio.avfaudio" && nsError.code == 2003329396
    }

    private func openMainApp(warmup: Bool = false) {
        let urlString = warmup ? "yapapp://keyboard-warmup" : "yapapp://"
        guard let url = URL(string: urlString) else { return }
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        let app = UIApplication.value(forKeyPath: "sharedApplication") as AnyObject
        if app.responds(to: sel) {
            _ = app.perform(sel, with: url, with: [:])
        }
    }
}
