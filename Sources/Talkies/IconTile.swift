import SwiftUI

/// A colored rounded-square icon tile — the Alcove / macOS Settings visual pattern.
struct IconTile: View {
    let systemName: String
    let gradient: LinearGradient
    var size: CGFloat = 22
    var cornerRadius: CGFloat = 6
    var iconScale: CGFloat = 0.55

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * iconScale, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(gradient))
    }
}

enum Tile {
    static let home      = grad(.orange, .red)
    static let library   = grad(.purple, .pink)
    static let hotkey    = grad(.teal, .blue)
    static let cleanup   = grad(.pink, .purple)
    static let vocab     = grad(.indigo, .blue)
    static let account   = grad(.mint, .teal)
    static let perms     = grad(.mint, .green)
    static let keys      = grad(.yellow, .orange)
    static let about     = grad(.gray, Color.gray.opacity(0.55))

    // Permission card tiles
    static let mic       = grad(.pink, .red)
    static let access    = grad(.cyan, .blue)

    private static func grad(_ a: Color, _ b: Color) -> LinearGradient {
        LinearGradient(
            colors: [a, b],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
