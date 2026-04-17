#!/usr/bin/swift
import Foundation
import CoreGraphics
import CoreText
import ImageIO

// MARK: - Drawing

func drawIcon(size: Int) -> CGImage {
    let s  = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // ── Rounded rect background clip ──────────────────────────────────────
    let corner = s * 0.22
    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: s, height: s),
                          cornerWidth: corner, cornerHeight: corner)
    ctx.addPath(bgPath)
    ctx.clip()

    // ── Background: indigo → navy gradient (bottom-left → top-right) ──────
    let bgGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.09, green: 0.06, blue: 0.26, alpha: 1.0),
            CGColor(red: 0.04, green: 0.12, blue: 0.30, alpha: 1.0)
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(bgGrad,
                           start: CGPoint(x: 0, y: 0),
                           end:   CGPoint(x: s, y: s),
                           options: [])

    // ── Ambient glow (soft purple spot, upper area) ───────────────────────
    let glowGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.42, green: 0.30, blue: 0.85, alpha: 0.30),
            CGColor(red: 0.42, green: 0.30, blue: 0.85, alpha: 0.00)
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(glowGrad,
                           startCenter: CGPoint(x: s * 0.35, y: s * 0.62),
                           startRadius: 0,
                           endCenter:   CGPoint(x: s * 0.35, y: s * 0.62),
                           endRadius:   s * 0.55,
                           options: [])

    // ── Waveform ──────────────────────────────────────────────────────────
    // [0..0.48] → complex WAV shape   [0.52..1] → clean sine (MP3 quality)
    // Crossfade in the middle.
    let waveY      = s * 0.50
    let waveLeft   = s * 0.10
    let waveRight  = s * 0.90
    let waveW      = waveRight - waveLeft
    let lw         = max(1.5, s * 0.040)
    let steps      = size * 3

    func sample(_ t: CGFloat) -> CGFloat {
        let blend  = smoothstep(0.40, 0.62, t)   // fade WAV→sine
        let wav    = sin(t * .pi * 7)
                   + 0.40 * sin(t * .pi * 15 + 0.9)
                   + 0.18 * sin(t * .pi * 31 - 0.6)
        let sine   = sin(t * .pi * 7)
        let amp    = sin(t * .pi) * s * 0.215     // envelope
        return ((1 - blend) * wav + blend * sine) * amp
    }

    func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    var wavePoints = [(CGFloat, CGFloat)]()
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let x = waveLeft + t * waveW
        let y = waveY + sample(t)
        wavePoints.append((x, y))
    }

    let wavePath = CGMutablePath()
    for (i, pt) in wavePoints.enumerated() {
        if i == 0 { wavePath.move(to:    CGPoint(x: pt.0, y: pt.1)) }
        else       { wavePath.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
    }

    // Outer glow
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 0.50, green: 0.72, blue: 1.0, alpha: 0.20))
    ctx.setLineWidth(lw * 4)
    ctx.setLineCap(.round)
    ctx.addPath(wavePath)
    ctx.strokePath()
    ctx.restoreGState()

    // Main stroke via gradient clip
    ctx.saveGState()
    let strokeClip = wavePath.copy(strokingWithWidth: lw,
                                   lineCap: .round,
                                   lineJoin: .round,
                                   miterLimit: 4)
    ctx.addPath(strokeClip)
    ctx.clip()
    let strokeGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.60, green: 0.76, blue: 1.00, alpha: 1.0),  // blue-white (left)
            CGColor(red: 0.87, green: 0.80, blue: 1.00, alpha: 1.0)   // lavender (right)
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(strokeGrad,
                           start: CGPoint(x: waveLeft,  y: waveY),
                           end:   CGPoint(x: waveRight, y: waveY),
                           options: [])
    ctx.restoreGState()

    // ── Divider dot trail at crossfade point ──────────────────────────────
    let midX = waveLeft + waveW * 0.51
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(max(0.6, s * 0.009))
    ctx.setLineDash(phase: 0, lengths: [s * 0.022, s * 0.018])
    ctx.move(to:    CGPoint(x: midX, y: s * 0.22))
    ctx.addLine(to: CGPoint(x: midX, y: s * 0.78))
    ctx.strokePath()
    ctx.restoreGState()

    // ── Small arrow → at crossfade midpoint ───────────────────────────────
    drawArrow(ctx: ctx, cx: midX, cy: waveY, size: s)

    return ctx.makeImage()!
}

func drawArrow(ctx: CGContext, cx: CGFloat, cy: CGFloat, size s: CGFloat) {
    let r  = s * 0.038
    let hw = r * 0.7   // half-width of arrowhead
    let al = r * 1.2   // arrow length

    let path = CGMutablePath()
    path.move(to:    CGPoint(x: cx - al, y: cy))
    path.addLine(to: CGPoint(x: cx + al, y: cy))
    path.move(to:    CGPoint(x: cx + al - hw * 1.1, y: cy - hw))
    path.addLine(to: CGPoint(x: cx + al,            y: cy))
    path.addLine(to: CGPoint(x: cx + al - hw * 1.1, y: cy + hw))

    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.setLineWidth(max(0.8, s * 0.013))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - PNG export

func savePNG(_ image: CGImage, to path: String) {
    let url  = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Main

let iconsetPath = "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath,
                                          withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16",        16),
    ("icon_16x16@2x",     32),
    ("icon_32x32",        32),
    ("icon_32x32@2x",     64),
    ("icon_128x128",     128),
    ("icon_128x128@2x",  256),
    ("icon_256x256",     256),
    ("icon_256x256@2x",  512),
    ("icon_512x512",     512),
    ("icon_512x512@2x", 1024)
]

for (name, px) in sizes {
    let img  = drawIcon(size: px)
    let path = "\(iconsetPath)/\(name).png"
    savePNG(img, to: path)
    print("  ✓ \(path)")
}
print("Done.")
