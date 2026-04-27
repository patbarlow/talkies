import SwiftUI

struct WaveformView: View {
    let bars: [CGFloat]
    var color: Color = .mint

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(0.7 + 0.3 * bars[i]))
                    .frame(width: 4, height: max(6, bars[i] * 40))
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: bars[i])
            }
        }
    }
}

struct ProcessingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.mint)
                    .frame(width: 8, height: 8)
                    .scaleEffect(phase == i ? 1.3 : 0.7)
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever(autoreverses: false).delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .onAppear {
            withAnimation { phase = (phase + 1) % 3 }
            // Kick the repeating animation
            Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}
