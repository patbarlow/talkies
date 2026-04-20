#!/usr/bin/env swift
// Render Resources/dmg-background.png — a 540×360 PNG used as the backdrop
// of Yap.dmg's installer window. Pure CoreGraphics so we don't depend on
// a design tool; tweak the constants below and re-run if you want changes.
//
// Usage: swift Scripts/make-dmg-background.swift

import AppKit
import Foundation

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let output = projectRoot.appendingPathComponent("Resources/dmg-background.png")

let size = NSSize(width: 540, height: 360)

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
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

let rect = NSRect(origin: .zero, size: size)

// Subtle top-to-bottom gradient — near-white fading to a hint of grey.
let bg = NSGradient(
    starting: NSColor(srgbRed: 0.985, green: 0.985, blue: 0.99, alpha: 1),
    ending:   NSColor(srgbRed: 0.93,  green: 0.93,  blue: 0.95, alpha: 1)
)
bg?.draw(in: rect, angle: -90)

// Tagline at the top.
let title = "Drag Yap to Applications to install"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(srgbRed: 0.28, green: 0.28, blue: 0.32, alpha: 1)
]
let titleSize = title.size(withAttributes: titleAttrs)
title.draw(
    at: NSPoint(x: (size.width - titleSize.width) / 2, y: size.height - 70),
    withAttributes: titleAttrs
)

// Arrow between the two icon positions. create-dmg places icons at
// (140, 180) and (400, 180) in Finder coords (y from the top). Our
// CoreGraphics y runs bottom-up, so icon row is at size.height - 180 = 180.
let arrowY: CGFloat = 180
let arrowColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.62, alpha: 0.55)
arrowColor.setStroke()
arrowColor.setFill()

let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: 220, y: arrowY))
shaft.line(to: NSPoint(x: 320, y: arrowY))
shaft.lineWidth = 2.5
shaft.lineCapStyle = .round
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 330, y: arrowY))
head.line(to: NSPoint(x: 315, y: arrowY + 9))
head.line(to: NSPoint(x: 315, y: arrowY - 9))
head.close()
head.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
try png.write(to: output, options: .atomic)
print("Wrote \(output.path)")
