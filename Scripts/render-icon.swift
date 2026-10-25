// Renders Alexandria's app icon — the Pharos of Alexandria on a Lapis night,
// its lamp throwing light out as sound waves — as vector art at 1024×1024.
//
//   swift Scripts/render-icon.swift <out.png>
//
// The artwork sits on the macOS icon grid: an 824pt continuous-corner tile
// centred on the 1024 canvas, with the standard soft drop shadow.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, like the sketches.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

func polygon(_ points: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: points)
    p.closeSubpath()
    return p
}

/// Fills `path` with a left-lit horizontal gradient across [x0, x1]: the
/// lamp-side face bright ivory, the far side in warm shadow.
func ivory(_ path: CGPath, _ x0: CGFloat, _ x1: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([
        (0.00, rgb(0xFFF8E8)), (0.42, rgb(0xF2E4C4)), (0.62, rgb(0xD8C196)), (1.00, rgb(0xA88D62)),
    ]), start: CGPoint(x: x0, y: 0), end: CGPoint(x: x1, y: 0), options: [])
    ctx.restoreGState()
}

// MARK: Tile

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: rgb(0x000000, 0.30))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x0B1433))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

// Night: deep ink at the top, Lapis toward the horizon.
ctx.drawLinearGradient(gradient([
    (0.00, rgb(0x0A1230)), (0.55, rgb(0x1A2F72)), (0.80, rgb(0x2B4FB8)), (1.00, rgb(0x3C67D9)),
]), start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

// Stars, kept clear of the beam.
for (x, y, r, a) in [(210.0, 230.0, 4.0, 0.75), (300, 170, 3, 0.55), (760, 200, 4, 0.7), (830, 300, 3, 0.5),
                     (180, 420, 3, 0.45), (850, 470, 3, 0.4), (690, 150, 2.5, 0.5), (380, 140, 2.5, 0.45)] {
    ctx.setFillColor(rgb(0xFFF4D6, a))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// MARK: Light

let lamp = CGPoint(x: 512, y: 372)

// The glow the whole scene is lit by.
ctx.drawRadialGradient(gradient([
    (0.0, rgb(0xFFE3A3, 0.80)), (0.18, rgb(0xFFC35C, 0.40)), (0.45, rgb(0xE8A04A, 0.10)), (1.0, rgb(0xE8A04A, 0)),
]), startCenter: lamp, startRadius: 0, endCenter: lamp, endRadius: 300, options: [])

// Sound waves: the beam, as fine arcs either side of the lamp.
ctx.setLineCap(.round)
for (radius, width, alpha) in [(112.0, 13.0, 0.95), (172.0, 11.0, 0.66), (232.0, 9.0, 0.40), (292.0, 7.0, 0.20)] {
    ctx.setStrokeColor(rgb(0xFFD27A, alpha))
    ctx.setLineWidth(width)
    let spread = CGFloat.pi * 0.16
    for centre in [0, CGFloat.pi] {
        ctx.addArc(center: lamp, radius: radius, startAngle: centre - spread, endAngle: centre + spread,
                   clockwise: false)
        ctx.strokePath()
    }
}

// MARK: Sea and island

ctx.drawLinearGradient(gradient([(0, rgb(0x0E1D52)), (1, rgb(0x070D26))]),
                       start: CGPoint(x: 0, y: 840), end: CGPoint(x: 0, y: 924), options: [])
// The lamp's reflection, broken by the water.
ctx.setLineCap(.round)
for (y, half, alpha) in [(872.0, 70.0, 0.55), (890.0, 46.0, 0.40), (906.0, 30.0, 0.28), (920.0, 16.0, 0.18)] {
    ctx.setStrokeColor(rgb(0xFFD27A, alpha))
    ctx.setLineWidth(5)
    ctx.move(to: CGPoint(x: 512 - half, y: y))
    ctx.addLine(to: CGPoint(x: 512 + half, y: y))
    ctx.strokePath()
}
let island = polygon([CGPoint(x: 318, y: 862), CGPoint(x: 352, y: 834), CGPoint(x: 410, y: 822),
                      CGPoint(x: 614, y: 822), CGPoint(x: 676, y: 834), CGPoint(x: 712, y: 862)])
ctx.addPath(island)
ctx.setFillColor(rgb(0x0A1433))
ctx.fillPath()

// MARK: Pharos

// Base tier: square and tall, barely tapering, with a crenellated parapet.
let base = polygon([CGPoint(x: 398, y: 612), CGPoint(x: 626, y: 612), CGPoint(x: 642, y: 828), CGPoint(x: 382, y: 828)])
ivory(base, 382, 642)
for i in 0..<7 {
    let x = 392 + CGFloat(i) * 35
    let merlon = CGPath(roundedRect: CGRect(x: x, y: 586, width: 22, height: 28), cornerWidth: 2,
                        cornerHeight: 2, transform: nil)
    ivory(merlon, 392, 632)
}
// Middle tier: octagonal — two faint arrises mark the faces.
let middle = polygon([CGPoint(x: 444, y: 476), CGPoint(x: 580, y: 476), CGPoint(x: 590, y: 590), CGPoint(x: 434, y: 590)])
ivory(middle, 434, 590)
ctx.setStrokeColor(rgb(0x8C7350, 0.35))
ctx.setLineWidth(2)
for (xt, xb) in [(478.0, 474.0), (546.0, 550.0)] {
    ctx.move(to: CGPoint(x: xt, y: 478)); ctx.addLine(to: CGPoint(x: xb, y: 588)); ctx.strokePath()
}
// Top tier: round.
let top = polygon([CGPoint(x: 472, y: 410), CGPoint(x: 552, y: 410), CGPoint(x: 558, y: 474), CGPoint(x: 466, y: 474)])
ivory(top, 466, 558)

// Cornices between tiers, a touch wider.
for (y, x0, x1, h) in [(574.0, 424.0, 600.0, 12.0), (466.0, 452.0, 572.0, 12.0), (400.0, 462.0, 562.0, 12.0)] {
    let band = CGPath(roundedRect: CGRect(x: x0, y: y, width: x1 - x0, height: h),
                      cornerWidth: 3, cornerHeight: 3, transform: nil)
    ivory(band, x0, x1)
}

// Windows: small dark slits, a column per tier.
for (x, y, w, h) in [(505.0, 650.0, 14.0, 30.0), (505.0, 712.0, 14.0, 30.0), (505.0, 774.0, 14.0, 30.0),
                     (506.0, 506.0, 12.0, 26.0), (507.0, 428.0, 10.0, 22.0)] {
    let slit = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: w / 2,
                      cornerHeight: w / 2, transform: nil)
    ctx.addPath(slit)
    ctx.setFillColor(rgb(0x4A3A2C, 0.80))
    ctx.fillPath()
}

// Lantern: two columns framing the lamp, a small dome, and the statue's
// finial on top.
for x in [480.0, 534.0] {
    let column = CGPath(roundedRect: CGRect(x: x, y: 338, width: 10, height: 64), cornerWidth: 3,
                        cornerHeight: 3, transform: nil)
    ivory(column, x, x + 10)
}
let dome = CGMutablePath()
dome.move(to: CGPoint(x: 472, y: 342))
dome.addQuadCurve(to: CGPoint(x: 552, y: 342), control: CGPoint(x: 512, y: 284))
dome.closeSubpath()
ivory(dome, 472, 552)
let finial = CGMutablePath()
finial.addRoundedRect(in: CGRect(x: 508, y: 262, width: 8, height: 54), cornerWidth: 3, cornerHeight: 3)
finial.addEllipse(in: CGRect(x: 503, y: 250, width: 18, height: 18))
ivory(finial, 503, 521)

// The lamp.
ctx.drawRadialGradient(gradient([(0, rgb(0xFFFFFF)), (0.45, rgb(0xFFF1C9)), (1, rgb(0xFFC35C, 0))]),
                       startCenter: lamp, startRadius: 0, endCenter: lamp, endRadius: 46, options: [])

// A hairline of light on the tile's edge, so it reads on dark Docks.
ctx.restoreGState()
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
ctx.setLineWidth(2)
ctx.strokePath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
