#!/usr/bin/env swift
// Generates a 1024x1024 PNG icon for cc-manager at the path given by argv[1].

import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make_icon.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outPath = CommandLine.arguments[1]

let side: CGFloat = 1024
let size = NSSize(width: side, height: side)

// macOS Big-Sur-style icon: content lives inside an 824x824 rounded square,
// centered on a 1024x1024 transparent canvas (100px padding on all sides).
let inset: CGFloat = 100
let contentSide = side - inset * 2        // 824
let cornerRadius: CGFloat = contentSide * 0.225  // ≈185, Apple's squircle radius

let image = NSImage(size: size, flipped: false) { _ in
    let contentRect = NSRect(x: inset, y: inset, width: contentSide, height: contentSide)
    let bgPath = NSBezierPath(roundedRect: contentRect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.current!.saveGraphicsState()
    bgPath.addClip()

    // Warm Claude-adjacent gradient.
    let top = NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.36, alpha: 1.0)    // terracotta
    let bottom = NSColor(calibratedRed: 0.55, green: 0.24, blue: 0.43, alpha: 1.0) // deep plum
    NSGradient(colors: [top, bottom])!.draw(in: contentRect, angle: 300)

    // Scale factor so bubble dimensions track the 824 content area.
    let s = contentSide / 1024.0

    // Two overlapping speech bubbles, centered within contentRect.
    let cx = contentRect.midX
    let cy = contentRect.midY

    // Back bubble.
    do {
        let bw: CGFloat = 560 * s, bh: CGFloat = 420 * s
        let origin = NSPoint(x: cx - bw / 2 + 60 * s, y: cy - bh / 2 - 30 * s)
        let r = NSRect(origin: origin, size: NSSize(width: bw, height: bh))
        let radius: CGFloat = 90 * s
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        path.move(to: NSPoint(x: r.maxX - 170 * s, y: r.minY + 6 * s))
        path.line(to: NSPoint(x: r.maxX - 30 * s,  y: r.minY - 120 * s))
        path.line(to: NSPoint(x: r.maxX - 80 * s,  y: r.minY + 4 * s))
        path.close()
        NSColor(calibratedWhite: 1.0, alpha: 0.78).setFill()
        path.fill()
    }

    // Front bubble.
    do {
        let bw: CGFloat = 500 * s, bh: CGFloat = 360 * s
        let origin = NSPoint(x: cx - bw / 2 - 80 * s, y: cy - bh / 2 + 60 * s)
        let r = NSRect(origin: origin, size: NSSize(width: bw, height: bh))
        let radius: CGFloat = 82 * s
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        path.move(to: NSPoint(x: r.minX + 70 * s,  y: r.minY + 8 * s))
        path.line(to: NSPoint(x: r.minX - 20 * s,  y: r.minY - 110 * s))
        path.line(to: NSPoint(x: r.minX + 160 * s, y: r.minY + 4 * s))
        path.close()
        NSColor.white.withAlphaComponent(0.95).setFill()
        path.fill()

        // Three dots.
        let dotR: CGFloat = 34 * s
        let dotY = r.midY - dotR / 2
        let offsets: [CGFloat] = [-110 * s, 0, 110 * s]
        for off in offsets {
            let dotRect = NSRect(x: r.midX + off - dotR / 2, y: dotY, width: dotR, height: dotR)
            NSColor(calibratedRed: 0.55, green: 0.24, blue: 0.43, alpha: 1.0).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }

    NSGraphicsContext.current!.restoreGraphicsState()
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to render PNG\n".data(using: .utf8)!)
    exit(2)
}

do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("Wrote \(outPath)")
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(3)
}
