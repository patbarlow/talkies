#!/usr/bin/env swift
// Render Resources/AppIcon.icns from the Icon Composer bundle at
// /Users/pat/Documents/talkies-icon.icon (or first CLI arg).
//
// Usage: swift Scripts/make-icon.swift [path/to/bundle.icon]

import AppKit
import Foundation

let sourceBundle = CommandLine.arguments.count >= 2
    ? CommandLine.arguments[1]
    : "/Users/pat/Documents/talkies-icon.icon"
let sourcePNG = URL(fileURLWithPath: sourceBundle)
    .appendingPathComponent("Assets/waveform.mid.png")

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputICNS = projectRoot.appendingPathComponent("Resources/AppIcon.icns")

guard let symbol = NSImage(contentsOf: sourcePNG) else {
    fputs("Could not load \(sourcePNG.path)\n", stderr)
    exit(1)
}

// Render a 1024x1024 master: dark gradient + centered white waveform with shadow.
func renderMaster(size: CGFloat) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // Background: gentle top-to-bottom dark gradient (lifts the waveform's contrast
    // without going muddy at 16–32 px).
    let bg = NSGradient(
        starting: NSColor(srgbRed: 0.18, green: 0.18, blue: 0.20, alpha: 1),
        ending:   NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1)
    )
    bg?.draw(in: rect, angle: -90)

    // Waveform symbol, centered, ~72% width. Full white with a pronounced
    // inner-lit feel via a soft halo + ground shadow.
    let targetWidth = size * 0.72
    let aspect = symbol.size.height / symbol.size.width
    let targetHeight = targetWidth * aspect
    let symbolRect = NSRect(
        x: (size - targetWidth) / 2,
        y: (size - targetHeight) / 2,
        width: targetWidth,
        height: targetHeight
    )

    // Subtle glow underneath
    let halo = NSShadow()
    halo.shadowColor = NSColor(white: 1, alpha: 0.18)
    halo.shadowOffset = .zero
    halo.shadowBlurRadius = size * 0.04
    halo.set()
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    // Second pass: crisp white on top with a slight drop shadow for depth
    let drop = NSShadow()
    drop.shadowColor = NSColor(white: 0, alpha: 0.55)
    drop.shadowOffset = NSSize(width: 0, height: -size * 0.015)
    drop.shadowBlurRadius = size * 0.03
    drop.set()
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let masterPNGData = renderMaster(size: 1024)
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("talkies-master-\(UUID().uuidString).png")
try masterPNGData.write(to: tmp)
defer { try? FileManager.default.removeItem(at: tmp) }

// Build iconset directory with all required sizes.
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

let sizes: [(pixels: Int, name: String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for entry in sizes {
    let out = iconset.appendingPathComponent(entry.name)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    p.arguments = ["-z", "\(entry.pixels)", "\(entry.pixels)", tmp.path, "--out", out.path]
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        fputs("sips failed for size \(entry.pixels)\n", stderr)
        exit(2)
    }
}

// Pack the iconset into .icns.
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputICNS.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(3)
}

print("Wrote \(outputICNS.path)")
