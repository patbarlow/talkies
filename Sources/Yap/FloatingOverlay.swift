import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class OverlayViewModel: ObservableObject {
    enum Mode: Equatable {
        case hidden, recording, processing
        case review(summary: String, hotkeyLabel: String)
        case limitReached
        case editRecording(selection: String, prompt: String)
        case editProcessing(selection: String, prompt: String)
        case editPreview(original: String, draft: String, hotkeyLabel: String)
        case editToast(message: String)
    }
    @Published var mode: Mode = .hidden
}

/// A borderless floating panel that sits just below the menu bar and shows
/// recording / processing / review state. Uses macOS native window shadow, which
/// auto-masks to visible (non-transparent) pixels of the pill/card.
@MainActor
final class FloatingOverlay {
    static let shared = FloatingOverlay()

    private let viewModel = OverlayViewModel()
    private var panel: NSPanel?
    private var reviewDismissTask: Task<Void, Never>?

    private init() {}

    func activateForTextInput() {
        panel?.makeKeyAndOrderFront(nil)
    }

    func show(_ mode: OverlayViewModel.Mode) {
        reviewDismissTask?.cancel()
        reviewDismissTask = nil

        ensurePanel()
        viewModel.mode = mode
        guard let panel else { return }

        if mode == .hidden {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak panel] in
                panel?.orderOut(nil)
            })
            return
        }

        // Review and limit cards are interactive; pills pass through clicks.
        // isMovableByWindowBackground must stay false — true causes the window to consume
        // mouseDown events before SwiftUI tap gestures can fire on the text input area.
        switch mode {
        case .review, .limitReached, .editRecording, .editProcessing, .editPreview, .editToast:
            panel.ignoresMouseEvents = false
        default:
            panel.ignoresMouseEvents = true
        }

        let size = panelSize(for: mode)
        reposition(to: size)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        panel.invalidateShadow()

        switch mode {
        case .review:
            reviewDismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                self?.show(.hidden)
            }
        case .limitReached:
            reviewDismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                self?.show(.hidden)
            }
        case .editToast:
            reviewDismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self?.show(.hidden)
            }
        case .editRecording, .editPreview:
            // Make the panel key so SwiftUI .keyboardShortcut handlers (esc/return) fire.
            panel.makeKeyAndOrderFront(nil)
        default:
            break
        }
    }

    private func panelSize(for mode: OverlayViewModel.Mode) -> NSSize {
        switch mode {
        case .hidden, .recording, .processing:
            return NSSize(width: 96, height: 36)
        case .review:
            return NSSize(width: 380, height: 158)
        case .limitReached:
            return NSSize(width: 320, height: 120)
        case .editRecording, .editProcessing:
            return NSSize(width: 380, height: 132)
        case .editPreview:
            return NSSize(width: 560, height: 380)
        case .editToast:
            return NSSize(width: 320, height: 64)
        }
    }

    private func ensurePanel() {
        if panel != nil { return }
        let root = OverlayRoot().environmentObject(viewModel)
        let hosting = NSHostingController(rootView: root)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true

        if let cv = panel.contentView {
            cv.wantsLayer = true
            cv.layer?.backgroundColor = NSColor.clear.cgColor
            cv.layer?.isOpaque = false
        }
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layer?.isOpaque = false

        self.panel = panel
    }

    private func reposition(to size: NSSize) {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        // Place pills well clear of the menu bar; larger cards stay near the top.
        let topGap: CGFloat
        switch viewModel.mode {
        case .recording, .processing:
            topGap = 72
        default:
            topGap = 6
        }
        let y = visible.maxY - size.height - topGap
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }
}

// MARK: - Pill/card views

private struct OverlayRoot: View {
    @EnvironmentObject var vm: OverlayViewModel

    var body: some View {
        ZStack {
            Color.clear
            switch vm.mode {
            case .hidden:
                EmptyView()
            case .recording:
                RecordingPill()
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            case .processing:
                ProcessingPill()
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            case .review(let summary, let hotkeyLabel):
                ReviewCard(summary: summary, hotkeyLabel: hotkeyLabel)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            case .limitReached:
                LimitReachedCard()
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            case .editRecording(let selection, let prompt):
                EditPromptCard(selection: selection, phase: .recording, prompt: prompt)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            case .editProcessing(let selection, let prompt):
                EditPromptCard(selection: selection, phase: .processing, prompt: prompt)
                    .transition(.opacity)
            case .editPreview(let original, let draft, let hotkeyLabel):
                EditPreviewCard(original: original, draft: draft, hotkeyLabel: hotkeyLabel)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            case .editToast(let message):
                EditToastCard(message: message)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: vm.mode)
    }
}

/// Fixed-size recording pill. Every bar reacts to `AudioLevels.currentLevel`
/// with its own amplitude curve, so the visualization moves with the voice
/// (not a scrolling ring buffer). Background uses `.regularMaterial` so
/// light/dark mode is handled by the system.
private struct RecordingPill: View {
    @StateObject private var levels = AudioLevels.shared

    private let pillWidth: CGFloat = 96
    private let pillHeight: CGFloat = 36
    private let barWidth: CGFloat = 1.5
    private let barSpacing: CGFloat = 2
    private let barCount = 21
    private let maxBarHeight: CGFloat = 28
    private let minBarHeight: CGFloat = 2.5

    var body: some View {
        ZStack {
            Capsule()
                .fill(.regularMaterial)
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.3)
                )

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color.primary.opacity(0.85))
                        .frame(width: barWidth, height: height(for: i, level: Double(levels.currentLevel)))
                        .animation(.spring(response: 0.18, dampingFraction: 0.78), value: levels.currentLevel)
                }
            }
        }
        .frame(width: pillWidth, height: pillHeight)
    }

    /// Per-bar activation threshold. Center bars have the lowest threshold
    /// (they light up first on quiet speech); outer bars have progressively
    /// higher thresholds, so the waveform "blooms" outward from the center as
    /// the input gets louder. Adjacent bars get a small offset so the bloom
    /// doesn't look like a perfectly symmetric ramp.
    private func height(for index: Int, level: Double) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let signedDistance = (Double(index) - center) / center  // -1…+1
        let normalizedDistance = abs(signedDistance)

        // Threshold ramps from `lowThreshold` at the center (most sensitive)
        // to `highThreshold` at the edges (only respond to loud speech).
        // The steep exponent makes the drop-off pronounced so the centre
        // reads as a clear peak.
        let lowThreshold = 0.04
        let highThreshold = 0.95
        let curve = pow(normalizedDistance, 3.0)

        // Very subtle left/right skew so the waveform doesn't look perfectly
        // mirror-symmetric. Left bars are slightly less sensitive than right.
        let sideBias = signedDistance < 0 ? 0.015 : 0.0

        let threshold = lowThreshold + (highThreshold - lowThreshold) * curve + sideBias

        // How much headroom this bar has above its threshold determines how
        // much of the remaining 0…1 range it gets to climb. The pow(0.6) is
        // a gentle ease — at moderate speech levels the centre bar already
        // climbs near the top of the pill, rather than topping out only on a
        // shout.
        let headroom = max(0.001, 1 - threshold)
        let activation = max(0, (level - threshold) / headroom)
        let eased = pow(activation, 0.6)

        // Per-bar height cap. Even at full activation, outer bars are capped
        // dramatically shorter than the centre — this is what produces the
        // tall central peak with a steep dropoff instead of a plateau.
        // Centre: 100% of max. By two bars out: ~60%. By half-way to the
        // edge: ~25%. At the edge: 8%.
        let heightCap = 0.08 + 0.92 * pow(1 - normalizedDistance, 2.6)
        let effectiveMax = maxBarHeight * CGFloat(heightCap)

        let h = minBarHeight + CGFloat(eased) * effectiveMax
        return min(max(h, minBarHeight), minBarHeight + maxBarHeight)
    }
}

/// Same pill geometry as `RecordingPill`, but bars are driven by a synthetic
/// "blob" that bounces left↔right across the pill. Starts as a single blob in
/// the centre and oscillates between the ends while we wait for the API.
private struct ProcessingPill: View {
    private let pillWidth: CGFloat = 96
    private let pillHeight: CGFloat = 36
    private let barWidth: CGFloat = 1.5
    private let barSpacing: CGFloat = 2
    private let barCount = 21
    private let maxBarHeight: CGFloat = 28
    private let minBarHeight: CGFloat = 2.5

    // Captured when this view is first constructed (each .processing entry
    // builds a fresh ProcessingPill) so the blob always starts at centre and
    // travels outward from there.
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(startedAt)
            ZStack {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.3)
                    )

                HStack(spacing: barSpacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        Capsule()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: barWidth, height: bounceHeight(for: i, t: t))
                    }
                }
            }
            .frame(width: pillWidth, height: pillHeight)
        }
    }

    private func bounceHeight(for index: Int, t: Double) -> CGFloat {
        // Triangle wave instead of `sin` — sin's velocity goes to zero at its
        // peaks so the blob would slow down and "stick" at each edge before
        // reversing. A triangle wave has constant velocity, so the bounce is
        // crisp and the blob never dwells at the ends.
        //
        // Period: one full bounce (centre → right → centre → left → centre).
        let period = 2.1  // seconds per full bounce
        let phase = t.truncatingRemainder(dividingBy: period) / period  // 0…1

        // tri ∈ [-1, +1], starts at 0 at phase 0, peaks +1 at phase 0.25,
        // crosses 0 at 0.5, troughs -1 at 0.75, back to 0 at 1.0.
        let tri: Double
        if phase < 0.25 {
            tri = phase * 4
        } else if phase < 0.75 {
            tri = 2 - phase * 4
        } else {
            tri = phase * 4 - 4
        }

        let center = Double(barCount - 1) / 2
        let peakPos = center + center * tri

        // Gaussian falloff around the peak. Narrow sigma → tighter blob.
        let sigma = 1.6
        let dist = Double(index) - peakPos
        let intensity = exp(-(dist * dist) / (2 * sigma * sigma))

        // Peak deliberately well below the recording pill's max so the
        // processing state reads as quieter than active mic pickup.
        let peakHeight: CGFloat = maxBarHeight * 0.55
        return minBarHeight + CGFloat(intensity) * peakHeight
    }
}

private struct ReviewCard: View {
    let summary: String
    let hotkeyLabel: String

    @State private var hoveringBottom = false
    @State private var replyText = ""
    @FocusState private var isTextFocused: Bool

    private var showingTextInput: Bool { hoveringBottom || isTextFocused || !replyText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text(summary.isEmpty ? "Claude finished" : summary)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    FloatingOverlay.shared.show(.hidden)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 10)

            ZStack(alignment: .leading) {
                if showingTextInput {
                    HStack(spacing: 6) {
                        TextField("Type your reply…", text: $replyText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .focused($isTextFocused)
                            .onSubmit { sendTextReply() }
                        Button(action: sendTextReply) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(replyText.isEmpty ? .white.opacity(0.25) : .white)
                        }
                        .buttonStyle(.plain)
                        .disabled(replyText.isEmpty)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.1)))
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 10, weight: .medium))
                        Text("Hold \(hotkeyLabel) to reply")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.white.opacity(0.45))
                    .transition(.opacity)
                }

            }
            .animation(.easeInOut(duration: 0.12), value: showingTextInput)
            .onHover { hovering in
                hoveringBottom = hovering
            }
            .simultaneousGesture(TapGesture().onEnded {
                guard !isTextFocused else { return }
                FloatingOverlay.shared.activateForTextInput()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFocused = true
                }
            })
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 380, height: 158)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
    }

    private func sendTextReply() {
        guard !replyText.isEmpty else { return }
        let text = replyText
        replyText = ""
        isTextFocused = false
        FloatingOverlay.shared.show(.hidden)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            Paster.paste(text)
            try? await Task.sleep(nanoseconds: 150_000_000)
            let src = CGEventSource(stateID: .combinedSessionState)
            CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: true)?
                .post(tap: .cgAnnotatedSessionEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: false)?
                .post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

// MARK: - Limit reached card

private struct LimitReachedCard: View {
    @StateObject private var auth = AuthStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Weekly limit reached")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button {
                    FloatingOverlay.shared.show(.hidden)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            Button {
                FloatingOverlay.shared.show(.hidden)
                NotificationCenter.default.post(name: .yapOpenAccount, object: nil)
            } label: {
                Text("Upgrade to Pro")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.mint))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 320, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
    }

    private var subtitle: String {
        guard let user = auth.currentUser else { return "Resets weekly." }
        return resetText(from: user.weekStart)
    }

    private func resetText(from weekStart: String) -> String {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        let start = isoFull.date(from: weekStart) ?? isoBasic.date(from: weekStart)
        guard let start,
              let nextReset = Calendar.current.date(byAdding: .day, value: 7, to: start),
              nextReset > Date()
        else { return "Resets weekly." }
        let df = DateFormatter()
        df.dateFormat = "EEE h:mm a"
        return "Resets \(df.string(from: nextReset))."
    }
}

// MARK: - Edit-mode cards

private struct EditPromptCard: View {
    enum Phase { case recording, processing }

    let selection: String
    let phase: Phase
    let prompt: String

    @StateObject private var levels = AudioLevels.shared
    @State private var dotPhase = 0
    private let dotTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    private let editBarCount = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.mint)
                        Text(prompt)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text(selectionPreview)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Button {
                    EditModeController.shared.cancel(reason: .userClosed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            indicator
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 380, height: 132)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
    }

    private var selectionPreview: String {
        let collapsed = selection
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if collapsed.count <= 120 { return collapsed }
        return String(collapsed.prefix(117)) + "…"
    }

    @ViewBuilder
    private var indicator: some View {
        switch phase {
        case .recording:
            HStack(spacing: 3) {
                ForEach(0..<editBarCount, id: \.self) { i in
                    let level = Double(levels.currentLevel)
                    let center = Double(editBarCount - 1) / 2
                    let dist = abs(Double(i) - center) / center
                    let asymmetry = (Int(i) % 2 == 0 ? 1.0 : -1.0) * 0.04
                    let threshold = 0.08 + (0.55 - 0.08) * pow(dist, 1.3) + asymmetry
                    let headroom = max(0.001, 1 - threshold)
                    let activation = max(0, (level - threshold) / headroom)
                    let eased = pow(activation, 0.6)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: 3 + CGFloat(eased) * 22)
                        .animation(.spring(response: 0.18, dampingFraction: 0.78), value: levels.currentLevel)
                }
            }
        case .processing:
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(dotPhase == i ? 1.0 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .onReceive(dotTimer) { _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    dotPhase = (dotPhase + 1) % 3
                }
            }
        }
    }
}

private struct EditPreviewCard: View {
    let original: String
    let draft: String
    let hotkeyLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.mint)
                    Text("Preview")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button {
                    EditModeController.shared.cancel(reason: .userClosed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            ScrollView {
                Text(draft)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Button {
                    EditModeController.shared.confirm()
                } label: {
                    HStack(spacing: 4) {
                        Text("Apply")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "return")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.mint))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])

                Text("Hold \(hotkeyLabel) to refine")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 560, height: 380)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
    }
}

private struct EditToastCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.mint)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 320, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
    }
}
