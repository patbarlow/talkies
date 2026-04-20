import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayViewModel: ObservableObject {
    enum Mode: Equatable { case hidden, recording, processing }
    @Published var mode: Mode = .hidden
}

/// A borderless floating panel that sits just below the menu bar and shows
/// recording / processing state. Uses macOS native window shadow, which auto-
/// masks to visible (non-transparent) pixels of the pill.
@MainActor
final class FloatingOverlay {
    static let shared = FloatingOverlay()

    private let viewModel = OverlayViewModel()
    private var panel: NSPanel?

    private init() {}

    func show(_ mode: OverlayViewModel.Mode) {
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

        reposition()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        // Re-trace the shadow outline after the pill shape changes.
        panel.invalidateShadow()
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
        // macOS native window shadow — auto-masks to the alpha>0 pixels of the pill.
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true

        // Force the panel's contentView and the hosting view to have clear layers.
        // Without this, NSHostingView paints an opaque backing, leaving visible
        // square corners around the rounded pill.
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

    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

// MARK: - Pill views

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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: vm.mode)
    }
}

private struct RecordingPill: View {
    @StateObject private var levels = AudioLevels.shared

    var body: some View {
        HStack(spacing: 3) {
            ForEach(levels.bars.indices, id: \.self) { i in
                let level = levels.bars[i]
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 6 + level * 20)
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.black.opacity(0.92)))
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
