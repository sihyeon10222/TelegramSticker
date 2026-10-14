// Run on macOS: swift Scripts/GenerateSampleStickers.swift
// Original geometric test fixtures, dedicated to this project under CC0-1.0.
// Each PNG is RGBA: transparent background, opaque shapes, and antialiased/partial-alpha pixels.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = projectRoot.appendingPathComponent("StickerSamples/Resources", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func heart(_ context: CGContext, rect: CGRect, fill: CGColor) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.minY)
    context.scaleBy(x: rect.width, y: rect.height)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0.5, y: 0.1))
    path.addCurve(to: CGPoint(x: 0.08, y: 0.55), control1: CGPoint(x: 0.35, y: 0.26), control2: CGPoint(x: 0.08, y: 0.37))
    path.addCurve(to: CGPoint(x: 0.5, y: 0.76), control1: CGPoint(x: 0.02, y: 0.93), control2: CGPoint(x: 0.38, y: 1.03))
    path.addCurve(to: CGPoint(x: 0.92, y: 0.55), control1: CGPoint(x: 0.62, y: 1.03), control2: CGPoint(x: 0.98, y: 0.93))
    path.addCurve(to: CGPoint(x: 0.5, y: 0.1), control1: CGPoint(x: 0.92, y: 0.37), control2: CGPoint(x: 0.65, y: 0.26))
    path.closeSubpath()
    context.setFillColor(fill)
    context.addPath(path)
    context.fillPath()
    context.restoreGState()
}

func sparkle(_ context: CGContext, center: CGPoint, radius: CGFloat, fill: CGColor) {
    let path = CGMutablePath()
    let vertices: [(CGFloat, CGFloat)] = [(0,1), (0.2,0.2), (1,0), (0.2,-0.2), (0,-1), (-0.2,-0.2), (-1,0), (-0.2,0.2)]
    for (i, point) in vertices.enumerated() {
        let p = CGPoint(x: center.x + point.0 * radius, y: center.y + point.1 * radius)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    context.setFillColor(fill)
    context.addPath(path)
    context.fillPath()
}

for name in ["sample-smile", "sample-hearts", "sample-sparkle"] {
    guard let context = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("RGBA context unavailable") }
    switch name {
    case "sample-smile":
        context.setFillColor(color(1, 0.76, 0.16))
        context.fillEllipse(in: CGRect(x: 64, y: 64, width: 384, height: 384))
        context.setFillColor(color(0.22, 0.18, 0.14))
        context.fillEllipse(in: CGRect(x: 166, y: 276, width: 28, height: 40))
        context.fillEllipse(in: CGRect(x: 318, y: 276, width: 28, height: 40))
        context.setStrokeColor(color(0.22, 0.18, 0.14))
        context.setLineWidth(20)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 168, y: 220))
        context.addCurve(to: CGPoint(x: 344, y: 220), control1: CGPoint(x: 202, y: 130), control2: CGPoint(x: 310, y: 130))
        context.strokePath()
    case "sample-hearts":
        heart(context, rect: CGRect(x: 42, y: 84, width: 330, height: 330), fill: color(0.95, 0.24, 0.4))
        heart(context, rect: CGRect(x: 242, y: 36, width: 240, height: 240), fill: color(0.45, 0.27, 0.95, 0.48))
    default:
        context.setFillColor(color(0.13, 0.61, 0.91, 0.22))
        context.fillEllipse(in: CGRect(x: 42, y: 42, width: 428, height: 428))
        sparkle(context, center: CGPoint(x: 256, y: 256), radius: 202, fill: color(0.1, 0.48, 0.93))
        sparkle(context, center: CGPoint(x: 395, y: 398), radius: 50, fill: color(1, 0.76, 0.16))
    }
    let url = output.appendingPathComponent(name).appendingPathExtension("png")
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("PNG destination unavailable") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
    print("Created \(url.lastPathComponent)")
}
