import SwiftUI
import AVFoundation

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var settings: SharedSettings
    @StateObject private var audioLevels = AudioLevels.shared
    @StateObject private var recorder = Recorder()

    enum RecordState { case idle, recording, processing }
    @State private var recordState: RecordState = .idle
    @State private var recordingStart: Date?
    @State private var lastResult: String?
    @State private var isDragging = false
    @State private var errorMessage: String?
    @State private var micPermission: AVAuthorizationStatus = .notDetermined

    private let minimumDuration: TimeInterval = 0.5

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let user = auth.currentUser {
                        usageCard(user)
                    }
                    keyboardSetupCard
                    recordCard
                }
                .padding()
            }
            .navigationTitle("Yap")
            .task { await auth.refresh() }
            .onAppear { micPermission = AVCaptureDevice.authorizationStatus(for: .audio) }
        }
    }

    // MARK: - Usage card

    private func usageCard(_ user: PublicUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week")
                    .font(.subheadline.weight(.medium))
                Spacer()
                planBadge(user.plan)
            }

            if let limit = user.weekLimit {
                let fraction = min(Double(user.weekWords) / Double(max(limit, 1)), 1.0)
                ProgressView(value: fraction)
                    .tint(fraction >= 1 ? .red : .mint)
                Text("\(user.weekWords.formatted()) / \(limit.formatted()) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(user.weekWords.formatted()) words · unlimited")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            resetCountdown(weekStart: user.weekStart)
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Keyboard setup card

    private var keyboardSetupCard: some View {
        NavigationLink(destination: KeyboardSetupView()) {
            HStack(spacing: 14) {
                Image(systemName: "keyboard.fill")
                    .font(.title2)
                    .foregroundStyle(.mint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up Yap Keyboard")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Dictate in any app with the custom keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Record card (standalone record-and-copy)

    private var recordCard: some View {
        VStack(spacing: 16) {
            Text("Record & Copy")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Dictate something, copy the transcript to your clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let result = lastResult, recordState == .idle {
                Text(result)
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button {
                    UIPasteboard.general.string = result
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.mint)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            micRecordButton
        }
        .padding()
        .background(cardBackground)
    }

    private var micRecordButton: some View {
        Group {
            switch recordState {
            case .idle:
                Button(action: {}) {
                    ZStack {
                        Circle()
                            .fill(isDragging ? Color.mint : Color.mint.opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: isDragging ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundStyle(isDragging ? .white : .mint)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isDragging {
                                isDragging = true
                                requestMicAndRecord()
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            stopAndProcess()
                        }
                )
                .buttonStyle(.plain)

            case .recording:
                VStack(spacing: 8) {
                    WaveformView(bars: audioLevels.bars)
                        .frame(height: 36)
                    Text("Recording… release to stop")
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
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: recordState)
    }

    // MARK: - Recording actions

    private func requestMicAndRecord() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    self.micPermission = granted ? .authorized : .denied
                    if granted { self.startRecording() }
                }
            }
        default:
            errorMessage = "Microphone access denied. Enable it in Settings → Yap → Microphone."
            isDragging = false
        }
    }

    private func startRecording() {
        errorMessage = nil
        lastResult = nil
        do {
            try recorder.start()
            recordingStart = Date()
            recordState = .recording
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            isDragging = false
        }
    }

    private func stopAndProcess() {
        guard recordState == .recording else {
            _ = recorder.stop()
            return
        }
        let elapsed = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        guard let wavURL = recorder.stop(), elapsed >= minimumDuration else {
            recordState = .idle
            return
        }
        recordState = .processing
        Task { await transcribe(wavURL: wavURL, duration: elapsed) }
    }

    private func transcribe(wavURL: URL, duration: TimeInterval) async {
        defer { try? FileManager.default.removeItem(at: wavURL) }
        guard let session = settings.sessionToken else {
            recordState = .idle
            errorMessage = "Not signed in."
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
            lastResult = trimmed
            UIPasteboard.general.string = trimmed
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
            await auth.refresh()
            recordState = .idle
        } catch APIError.invalidSession {
            auth.signOut()
        } catch APIError.weeklyLimitReached(let limit, let used) {
            errorMessage = "Weekly limit reached (\(used)/\(limit) words). Upgrade to Pro."
            recordState = .idle
        } catch {
            errorMessage = error.localizedDescription
            recordState = .idle
        }
    }

    // MARK: - Helpers

    private func resetCountdown(weekStart: String) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            Text(resetLabel(weekStart: weekStart, at: ctx.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func resetLabel(weekStart: String, at now: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        let start = iso.date(from: weekStart) ?? iso2.date(from: weekStart)
        guard let start,
              let next = Calendar.current.date(byAdding: .day, value: 7, to: start)
        else { return "Resets weekly" }
        let remaining = next.timeIntervalSince(now)
        guard remaining > 0 else { return "Resetting soon" }
        if remaining > 24 * 3600 {
            let df = DateFormatter()
            df.dateFormat = "EEE h:mm a"
            return "Resets \(df.string(from: next))"
        } else {
            let h = Int(remaining) / 3600
            let m = (Int(remaining) % 3600) / 60
            return h > 0 ? "Resets in \(h) hr \(m) min" : "Resets in \(m) min"
        }
    }

    private func planBadge(_ plan: String) -> some View {
        Text(plan.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(plan == "pro" ? Color.mint : Color.secondary.opacity(0.2)))
            .foregroundStyle(plan == "pro" ? Color.black : Color.secondary)
    }

    private var cardBackground: some ShapeStyle {
        Color(uiColor: .secondarySystemGroupedBackground)
            .shadow(.drop(color: .black.opacity(0.04), radius: 4, y: 2))
    }
}
