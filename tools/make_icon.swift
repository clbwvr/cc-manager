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

let image = NSImage(size: size, flipped: false) { rect in
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded-square background with a warm Claude-adjacent gradient.
    let cornerRadius: CGFloat = 224
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgPath.addClip()

    let top = NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.36, alpha: 1.0)    // warm terracotta
    let bottom = NSColor(calibratedRed: 0.55, green: 0.24, blue: 0.43, alpha: 1.0) // deep plum
    let gradient = NSGradient(colors: [top, bottom])!
    gradient.draw(in: rect, angle: 300)

    // Two overlapping speech bubbles.
    let bubbleWhite = NSColor.white.withAlphaComponent(0.95)
    let bubbleCream = NSColor(calibratedWhite: 1.0, alpha: 0.78)

    // Back bubble (slightly larger, behind).
    do {
        let bw: CGFloat = 560, bh: CGFloat = 420
        let origin = NSPoint(x: (side - bw) / 2 + 60, y: (side - bh) / 2 - 30)
        let r = NSRect(origin: origin, size: NSSize(width: bw, height: bh))
        let radius: CGFloat = 90
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        // Tail.
        let tailStart = NSPoint(x: r.maxX - 170, y: r.minY + 6)
        let tailTip   = NSPoint(x: r.maxX - 30,  y: r.minY - 120)
        let tailEnd   = NSPoint(x: r.maxX - 80,  y: r.minY + 4)
        path.move(to: tailStart)
        path.line(to: tailTip)
        path.line(to: tailEnd)
        path.close()
        bubbleCream.setFill()
        path.fill()
    }

    // Front bubble (smaller, in front, offset the other way).
    do {
        let bw: CGFloat = 500, bh: CGFloat = 360
        let origin = NSPoint(x: (side - bw) / 2 - 80, y: (side - bh) / 2 + 60)
        let r = NSRect(origin: origin, size: NSSize(width: bw, height: bh))
        let radius: CGFloat = 82
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        let tailStart = NSPoint(x: r.minX + 70, y: r.minY + 8)
        let tailTip   = NSPoint(x: r.minX - 20, y: r.minY - 110)
        let tailEnd   = NSPoint(x: r.minX + 160, y: r.minY + 4)
        path.move(to: tailStart)
        path.line(to: tailTip)
        path.line(to: tailEnd)
        path.close()
        bubbleWhite.setFill()
        path.fill()

        // Three dots to suggest a conversation.
        let dotR: CGFloat = 34
        let dotY = r.midY - dotR / 2
        let centers: [CGFloat] = [r.midX - 110, r.midX, r.midX + 110]
        for cx in centers {
            let dotRect = NSRect(x: cx - dotR / 2, y: dotY, width: dotR, height: dotR)
            let dotPath = NSBezierPath(ovalIn: dotRect)
            NSColor(calibratedRed: 0.55, green: 0.24, blue: 0.43, alpha: 1.0).setFill()
            dotPath.fill()
        }
    }

    _ = ctx // silence unused warning
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
