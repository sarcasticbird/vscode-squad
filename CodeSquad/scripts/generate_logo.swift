#!/usr/bin/env swift
import Cocoa
import CoreGraphics

let size = 1024
let cornerRadius = Double(size) * 0.22

func createContext() -> CGContext {
    let cs = CGColorSpaceCreateDeviceRGB()
    return CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func clipToIconShape(_ ctx: CGContext) {
    let path = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: cornerRadius, cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.addPath(path)
    ctx.clip()
}

func drawBackgroundGradient(_ ctx: CGContext) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let colors: [CGFloat] = [
        0.12, 0.12, 0.18, 1.0,
        0.06, 0.06, 0.10, 1.0,
    ]
    let gradient = CGGradient(
        colorSpace: cs, colorComponents: colors,
        locations: [0.0, 1.0], count: 2
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: size / 2, y: size),
        end: CGPoint(x: size / 2, y: 0),
        options: []
    )
}

func drawDot(_ ctx: CGContext, cx: Double, cy: Double, radius: Double,
             r: Double, g: Double, b: Double, alpha: Double = 1.0) {
    ctx.saveGState()
    ctx.setFillColor(red: r, green: g, blue: b, alpha: alpha)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius,
               startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawGlow(_ ctx: CGContext, cx: Double, cy: Double, radius: Double,
              r: Double, g: Double, b: Double, alpha: Double = 0.12) {
    drawDot(ctx, cx: cx, cy: cy, radius: radius * 2.5, r: r, g: g, b: b, alpha: alpha)
}

func drawRect(_ ctx: CGContext, x: Double, y: Double, w: Double, h: Double,
              r: Double, g: Double, b: Double, alpha: Double) {
    ctx.saveGState()
    ctx.setFillColor(red: r, green: g, blue: b, alpha: alpha)
    ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    ctx.restoreGState()
}

func drawIcon(_ ctx: CGContext) {
    clipToIconShape(ctx)
    drawBackgroundGradient(ctx)

    let center = Double(size) / 2
    let dotRadius = 52.0
    let spacing = 160.0

    let positions: [(Double, Double)] = [
        (center - spacing / 2, center + spacing / 2),
        (center + spacing / 2, center + spacing / 2),
        (center - spacing / 2, center - spacing / 2),
        (center + spacing / 2, center - spacing / 2),
    ]

    let dotColors: [(Double, Double, Double)] = [
        (0.30, 0.85, 0.45),  // green
        (1.00, 0.60, 0.20),  // orange
        (0.30, 0.80, 0.90),  // cyan
        (0.30, 0.85, 0.45),  // green
    ]

    // Glows
    for (i, pos) in positions.enumerated() {
        let c = dotColors[i]
        drawGlow(ctx, cx: pos.0, cy: pos.1, radius: dotRadius, r: c.0, g: c.1, b: c.2)
    }

    // Dots
    for (i, pos) in positions.enumerated() {
        let c = dotColors[i]
        drawDot(ctx, cx: pos.0, cy: pos.1, radius: dotRadius, r: c.0, g: c.1, b: c.2)
    }

    // Dot highlights
    for (i, pos) in positions.enumerated() {
        let c = dotColors[i]
        drawDot(ctx, cx: pos.0 - dotRadius * 0.2, cy: pos.1 + dotRadius * 0.2,
                radius: dotRadius * 0.4,
                r: min(c.0 + 0.3, 1.0), g: min(c.1 + 0.3, 1.0), b: min(c.2 + 0.3, 1.0),
                alpha: 0.3)
    }

    // Code brackets
    let margin = 100.0
    let bracketW = 60.0
    let bracketH = Double(size) - margin * 2
    let thick = 12.0
    let bracketColor = (r: 1.0, g: 1.0, b: 1.0, a: 0.15)

    // Left bracket [
    drawRect(ctx, x: margin, y: margin + bracketH - thick, w: bracketW, h: thick,
             r: bracketColor.r, g: bracketColor.g, b: bracketColor.b, alpha: bracketColor.a)
    drawRect(ctx, x: margin, y: margin, w: bracketW, h: thick,
             r: bracketColor.r, g: bracketColor.g, b: bracketColor.b, alpha: bracketColor.a)
    drawRect(ctx, x: margin, y: margin, w: thick, h: bracketH,
             r: bracketColor.r, g: bracketColor.g, b: bracketColor.b, alpha: bracketColor.a)

    // Right bracket ]
    let rx = Double(size) - margin
    drawRect(ctx, x: rx - bracketW, y: margin + bracketH - thick, w: bracketW, h: thick,
             r: bracketColor.r, g: bracketColor.g, b: bracketColor.b, alpha: bracketColor.a)
    drawRect(ctx, x: rx - bracketW, y: margin, w: bracketW, h: thick,
             r: bracketColor.r, g: bracketColor.g, b: bracketColor.b, alpha: bracketColor.a)
    drawRect(ctx, x: rx - thick, y: margin, w: thick, h: bracketH,
             r: bracketColor.r, g: bracketColor.g, b: bracketColor.b, alpha: bracketColor.a)

    // Connection lines between dots
    let lineT = 4.0
    let lineAlpha = 0.06

    // Horizontal
    drawRect(ctx, x: positions[0].0, y: positions[0].1 - lineT / 2, w: spacing, h: lineT,
             r: 1, g: 1, b: 1, alpha: lineAlpha)
    drawRect(ctx, x: positions[2].0, y: positions[2].1 - lineT / 2, w: spacing, h: lineT,
             r: 1, g: 1, b: 1, alpha: lineAlpha)

    // Vertical
    drawRect(ctx, x: positions[2].0 - lineT / 2, y: positions[2].1, w: lineT, h: spacing,
             r: 1, g: 1, b: 1, alpha: lineAlpha)
    drawRect(ctx, x: positions[3].0 - lineT / 2, y: positions[3].1, w: lineT, h: spacing,
             r: 1, g: 1, b: 1, alpha: lineAlpha)
}

func savePNG(_ ctx: CGContext, path: String) {
    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// Main
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let outputPath = "\(scriptDir)/icon_source.png"

let ctx = createContext()
drawIcon(ctx)
savePNG(ctx, path: outputPath)
print("Generated \(outputPath)")
