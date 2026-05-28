import AppKit
import AVFoundation
import SwiftUI

struct PermissionsPane: View {
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var pollTimer: Timer?
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(.title2.bold())

            PermissionCard(
                tile: Tile.mic,
                symbol: "mic.fill",
                title: "Microphone",
                subtitle: "Capture audio while you hold the push-to-talk key.",
                granted: micStatus == .authorized,
                statusLabel: micStatusLabel,
                action: requestMicrophone
            )

            PermissionCard(
                tile: Tile.access,
                symbol: "figure.walk",
                title: "Accessibility",
                subtitle: "Listen for the global hotkey and paste text into the active field.",
                granted: axGranted,
                statusLabel: axGranted ? "Granted" : "Not granted",
                action: requestAccessibility
            )

            launchAtLoginRow

            Spacer(minLength: 0)
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    private var launchAtLoginRow: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(systemName: "power", gradient: Tile.account, size: 40, cornerRadius: 10, iconScale: 0.48)

            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at login").font(.body.weight(.semibold))
                Text("Start Yap automatically when you log in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            Toggle("", isOn: $launchAtLogin)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!LoginItem.isAvailable)
                .onChange(of: launchAtLogin) { _, new in
                    _ = LoginItem.setEnabled(new)
                    launchAtLogin = LoginItem.isEnabled
                }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var micStatusLabel: String {
        switch micStatus {
        case .authorized:   return "Granted"
        case .denied:       return "Denied"
        case .restricted:   return "Restricted"
        case .notDetermined: return "Not granted"
        @unknown default:   return "Unknown"
        }
    }

    private func requestMicrophone() {
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    // TCC dialog steals focus and macOS doesn't restore it.
                    bringYapWindowsToFront()
                }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    private func requestAccessibility() {
        // See OnboardingViewModel.requestAccessibility for the rationale —
        // the TCC prompt also registers Yap in the list, so we use it instead
        // of jumping straight to System Settings.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let newMic = AVCaptureDevice.authorizationStatus(for: .audio)
                let newAX = AXIsProcessTrusted()
                if newMic != micStatus { micStatus = newMic }
                if newAX != axGranted {
                    axGranted = newAX
                    NotificationCenter.default.post(name: .yapAccessibilityChanged, object: nil)
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

private struct PermissionCard: View {
    let tile: LinearGradient
    let symbol: String
    let title: String
    let subtitle: String
    let granted: Bool
    let statusLabel: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(systemName: symbol, gradient: tile, size: 40, cornerRadius: 10, iconScale: 0.48)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            if granted {
                Label(statusLabel, systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            } else {
                Button(action: action) {
                    Text("Allow").frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
