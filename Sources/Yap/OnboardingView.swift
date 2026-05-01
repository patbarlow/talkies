import AVFoundation
import Carbon.HIToolbox
import SwiftUI

// MARK: - View Model

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, permissions, testMic, tryShortcut

        var progress: Double { Double(rawValue + 1) / Double(Step.allCases.count) }
    }

    @Published var step: Step = .welcome
    @Published var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var axGranted: Bool = AXIsProcessTrusted()
    @Published var isRecordingShortcut = false
    @Published var shortcutResult: String?

    var showLoginAfter = true

    private var micRecorder: Recorder?
    private var shortcutRecorder: Recorder?
    private var shortcutHotkey: Hotkey?
    private var pollTimer: Timer?

    func advance() {
        let next = step.rawValue + 1
        if next < Step.allCases.count {
            withAnimation(.easeOut(duration: 0.2)) { step = Step(rawValue: next)! }
        } else {
            complete()
        }
    }

    // MARK: Permissions

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let m = AVCaptureDevice.authorizationStatus(for: .audio)
                let a = AXIsProcessTrusted()
                if m != self.micStatus { self.micStatus = m }
                if a != self.axGranted { self.axGranted = a }
            }
        }
    }

    func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    func requestMicrophone() {
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: Mic test

    func startMicRecorder() {
        guard micStatus == .authorized, micRecorder == nil else { return }
        let r = Recorder()
        try? r.start()
        micRecorder = r
    }

    func stopMicRecorder() {
        if let url = micRecorder?.stop() { try? FileManager.default.removeItem(at: url) }
        micRecorder = nil
        AudioLevels.shared.reset()
    }

    // MARK: Try shortcut

    func installShortcutHotkey() {
        guard AXIsProcessTrusted(), shortcutHotkey == nil else { return }
        NotificationCenter.default.post(name: .yapSuspendHotkey, object: nil)
        let hk = Hotkey(spec: Settings.shared.hotkey)
        hk.onPress = { [weak self] in Task { @MainActor in self?.beginRecording() } }
        hk.onRelease = { [weak self] in Task { @MainActor in self?.endRecording() } }
        hk.onCancel = { [weak self] in Task { @MainActor in self?.cancelRecording() } }
        if hk.install() { shortcutHotkey = hk }
    }

    func uninstallShortcutHotkey() {
        shortcutHotkey?.uninstall()
        shortcutHotkey = nil
        if isRecordingShortcut {
            if let url = shortcutRecorder?.stop() { try? FileManager.default.removeItem(at: url) }
            shortcutRecorder = nil
            isRecordingShortcut = false
        }
        NotificationCenter.default.post(name: .yapResumeHotkey, object: nil)
    }

    private func beginRecording() {
        guard !isRecordingShortcut else { return }
        let r = Recorder()
        try? r.start()
        shortcutRecorder = r
        isRecordingShortcut = true
    }

    private func endRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        if let url = shortcutRecorder?.stop() { try? FileManager.default.removeItem(at: url) }
        shortcutRecorder = nil
        shortcutResult = "Voice captured! After signing in, your text pastes automatically into any app."
    }

    private func cancelRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        if let url = shortcutRecorder?.stop() { try? FileManager.default.removeItem(at: url) }
        shortcutRecorder = nil
    }

    // MARK: Complete

    private func complete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        NotificationCenter.default.post(name: .yapOnboardingComplete, object: showLoginAfter)
    }
}

// MARK: - Stationary waveform

@MainActor
final class OnboardingWaveform: ObservableObject {
    private let barCount = 28
    @Published var bars: [CGFloat]
    private let phases: [Double]
    private var phase: Double = 0
    private var timer: Timer?

    init() {
        bars = Array(repeating: 0.05, count: 28)
        // Give each bar a unique idle phase so they move independently
        phases = (0..<28).map { Double($0) * 0.45 }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.phase += 0.08
                let level = AudioLevels.shared.bars.last ?? 0.0
                self.bars = (0..<self.barCount).map { i in
                    let idle = sin(self.phase + self.phases[i]) * 0.04 + 0.06
                    let audio = level * (0.65 + sin(self.phases[i] * 1.4) * 0.35)
                    return min(1.0, idle + audio)
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        phase = 0
        bars = Array(repeating: 0.05, count: barCount)
    }
}

// MARK: - Root view

struct OnboardingView: View {
    let showLoginAfter: Bool
    @StateObject private var vm = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            stepView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
        }
        .frame(width: 380, height: 490)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { vm.showLoginAfter = showLoginAfter }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.08))
                Rectangle()
                    .fill(Color.mint)
                    .frame(width: geo.size.width * vm.step.progress)
                    .animation(.easeInOut(duration: 0.4), value: vm.step)
            }
        }
        .frame(height: 3)
    }

    @ViewBuilder
    private var stepView: some View {
        switch vm.step {
        case .welcome:     WelcomeStep(vm: vm)
        case .permissions: OnboardingPermissionsStep(vm: vm)
        case .testMic:     TestMicStep(vm: vm)
        case .tryShortcut: TryShortcutStep(vm: vm)
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconTile(
                systemName: "waveform",
                gradient: LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                size: 64,
                cornerRadius: 16,
                iconScale: 0.55
            )
            .padding(.bottom, 20)

            Text("Welcome to Yap")
                .font(.title.bold())
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            Text("Push to talk, release to paste. Yap transcribes your voice and types it instantly.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.mint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Your shortcut")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                        Text(Settings.shared.hotkey.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.mint.opacity(0.25)))
                            .overlay(Capsule().stroke(Color.mint.opacity(0.5), lineWidth: 1))
                    }
                    Text("You can change this in Settings at any time.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))

            Spacer(minLength: 20)

            Button("Get started") { vm.advance() }
                .buttonStyle(OnboardingButton())
        }
    }
}

// MARK: - Step 2: Permissions

private struct OnboardingPermissionsStep: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Set up permissions")
                .font(.title.bold())
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            Text("Yap needs microphone access to hear you, and accessibility to paste text into any app.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                OnboardingPermissionRow(
                    icon: "mic.fill",
                    gradient: Tile.mic,
                    title: "Microphone",
                    subtitle: "Capture audio while you hold the push-to-talk key.",
                    granted: vm.micStatus == .authorized,
                    action: vm.requestMicrophone
                )
                OnboardingPermissionRow(
                    icon: "figure.walk",
                    gradient: Tile.access,
                    title: "Accessibility",
                    subtitle: "Listen for the global hotkey and paste into the active field.",
                    granted: vm.axGranted,
                    action: vm.requestAccessibility
                )
            }

            Spacer(minLength: 20)

            Button("Continue") { vm.advance() }
                .buttonStyle(OnboardingButton())
        }
        .onAppear { vm.startPolling() }
        .onDisappear { vm.stopPolling() }
    }
}

private struct OnboardingPermissionRow: View {
    let icon: String
    let gradient: LinearGradient
    let title: String
    let subtitle: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: icon, gradient: gradient, size: 38, cornerRadius: 10, iconScale: 0.48)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.caption.weight(.bold))
                    Text("Allowed").font(.callout.weight(.semibold))
                }
                .foregroundStyle(.mint)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Button("Allow", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: granted)
    }
}

// MARK: - Step 3: Test Microphone

private struct TestMicStep: View {
    @ObservedObject var vm: OnboardingViewModel
    @StateObject private var waveform = OnboardingWaveform()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Test your microphone")
                .font(.title.bold())
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            Text("Speak and watch the waveform react. If nothing moves, check your System Settings input device.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))

                HStack(alignment: .center, spacing: 3) {
                    ForEach(waveform.bars.indices, id: \.self) { i in
                        let h = max(3.0, waveform.bars[i] * 80)
                        Capsule()
                            .fill(Color.mint.opacity(0.4 + 0.6 * Double(waveform.bars[i])))
                            .frame(maxWidth: .infinity)
                            .frame(height: h)
                            .animation(.easeOut(duration: 0.06), value: h)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
            }
            .frame(height: 120)
            .onAppear {
                waveform.start()
                vm.startMicRecorder()
            }
            .onDisappear {
                waveform.stop()
                vm.stopMicRecorder()
            }

            Spacer(minLength: 20)

            Button("Continue") { vm.advance() }
                .buttonStyle(OnboardingButton())
        }
    }
}

// MARK: - Step 4: Try the Shortcut

private struct TryShortcutStep: View {
    @ObservedObject var vm: OnboardingViewModel
    @StateObject private var levels = AudioLevels.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Try the shortcut")
                .font(.title.bold())
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            HStack(spacing: 5) {
                Text("Hold")
                Text(Settings.shared.hotkey.label)
                    .font(.callout.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.2), lineWidth: 1))
                Text("and start speaking")
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.bottom, 12)

            if !vm.axGranted {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Accessibility permission is needed to detect the shortcut.")
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.9))
                }
                .padding(.bottom, 12)
            }

            // Result / recording area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(vm.isRecordingShortcut ? Color.mint.opacity(0.07) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                vm.isRecordingShortcut ? Color.mint.opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.2), value: vm.isRecordingShortcut)

                if vm.isRecordingShortcut {
                    VStack(spacing: 10) {
                        RecordingBarsView(levels: levels)
                        Text("Listening…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.mint)
                    }
                } else if let result = vm.shortcutResult {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text(result)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Text("Your transcription will appear here…")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.2))
                        .padding()
                }
            }
            .frame(height: 130)
            .animation(.easeOut(duration: 0.2), value: vm.shortcutResult != nil)

            Spacer(minLength: 20)

            Button("Complete onboarding") { vm.advance() }
                .buttonStyle(OnboardingButton())
        }
        .onAppear { vm.installShortcutHotkey() }
        .onDisappear { vm.uninstallShortcutHotkey() }
    }
}

private struct RecordingBarsView: View {
    @ObservedObject var levels: AudioLevels
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(levels.bars.indices, id: \.self) { i in
                let level = Double(levels.bars[i])
                let idle = sin(phase + Double(i) * 1.2) * 3 + 5
                Capsule()
                    .fill(Color.mint)
                    .frame(width: 4, height: max(4, idle + level * 34))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            phase += 0.06
        }
    }
}

// MARK: - Shared button style

private struct OnboardingButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.mint)
                    .opacity(configuration.isPressed ? 0.72 : 1.0)
            )
    }
}
