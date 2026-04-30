import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class OverlayViewModel: ObservableObject {
    enum Mode: Equatable {
        case hidden, recording, processing
        case review(summary: String, hotkeyLabel: String)
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

        // Review card is interactive (close button, draggable); pills pass through clicks.
        if case .review = mode {
            panel.ignoresMouseEvents = false
            panel.isMovableByWindowBackground = true
        } else {
            panel.ignoresMouseEvents = true
            panel.isMovableByWindowBackground = false
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

        if case .review = mode {
            reviewDismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                self?.show(.hidden)
            }
        }
    }

    private func panelSize(for mode: OverlayViewModel.Mode) -> NSSize {
        switch mode {
        case .hidden, .recording, .processing:
            return NSSize(width: 220, height: 56)
        case .review:
            return NSSize(width: 380, height: 158)
        }
    }

    private func ensurePanel() {
        if panel != nil { return }
        let root = OverlayRoot().environmentObject(viewModel)
        let hosting = NSHostingController(rootView: root)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 56),
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
        let y = visible.maxY - size.height - 6
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: vm.mode)
    }
}

private struct RecordingPill: View {
    @StateObject private var levels = AudioLevels.shared
    @State private var idlePhase: Double = 0

    private let idleTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(levels.bars.indices, id: \.self) { i in
                let level = Double(levels.bars[i])
                let idle = sin(idlePhase + Double(i) * 1.2) * 3 + 5
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: idle + level * 26)
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.92)))
        .onReceive(idleTimer) { _ in
            idlePhase += 0.06
        }
    }
}

private struct ProcessingPill: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(phase == i ? 1.0 : 0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
        .background(Capsule().fill(Color.black.opacity(0.92)))
        .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = (phase + 1) % 3
            }
        }
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

                // Transparent tap target — activates the panel as key window on click so the
                // TextField can receive keyboard input. NOT called on hover, which would steal
                // keyboard focus from the terminal every time the user moved the mouse over the card.
                if !isTextFocused {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            FloatingOverlay.shared.activateForTextInput()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isTextFocused = true
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.12), value: showingTextInput)
            .onHover { hovering in
                hoveringBottom = hovering
            }
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
