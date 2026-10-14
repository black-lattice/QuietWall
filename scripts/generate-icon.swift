#!/usr/bin/env swift
import AppKit

// Run from the repository root: swift scripts/generate-icon.swift
// Draw vector shapes at each icon size; no downloaded artwork or runtime dependency.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let iconset = temporary.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func drawIcon(size: Int) throws -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                      cornerWidth: 200, cornerHeight: 200, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24,
                      color: color(0, 0.12, 0.08, 0.24))
    context.addPath(tile)
    context.setFillColor(color(0.06, 0.38, 0.28))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let background = CGGradient(colorsSpace: space,
                                colors: [color(0.22, 0.68, 0.45), color(0.035, 0.29, 0.24)] as CFArray,
                                locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 160, y: 930),
                               end: CGPoint(x: 860, y: 70), options: [])
    context.restoreGState()
    context.addPath(tile)
    context.setStrokeColor(color(1, 1, 1, 0.16))
    context.setLineWidth(2)
    context.strokePath()

    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: 332, y: 350))
    leaf.addCurve(to: CGPoint(x: 742, y: 744), control1: CGPoint(x: 248, y: 638),
                  control2: CGPoint(x: 496, y: 786))
    leaf.addCurve(to: CGPoint(x: 332, y: 350), control1: CGPoint(x: 792, y: 478),
                  control2: CGPoint(x: 580, y: 278))
    leaf.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 18,
                      color: color(0, 0.16, 0.10, 0.22))
    context.addPath(leaf)
    context.setFillColor(color(0.91, 1, 0.91))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(leaf)
    context.clip()
    let leafGradient = CGGradient(colorsSpace: space,
                                  colors: [color(0.98, 1, 0.93), color(0.63, 0.90, 0.70)] as CFArray,
                                  locations: [0, 1])!
    context.drawLinearGradient(leafGradient, start: CGPoint(x: 420, y: 780),
                               end: CGPoint(x: 640, y: 320), options: [])
    context.restoreGState()

    context.setLineCap(.round)
    context.setLineWidth(24)
    context.setStrokeColor(color(0.73, 0.95, 0.77))
    context.move(to: CGPoint(x: 282, y: 286))
    context.addQuadCurve(to: CGPoint(x: 368, y: 389), control: CGPoint(x: 316, y: 342))
    context.strokePath()
    context.setLineWidth(18)
    context.setStrokeColor(color(0.11, 0.44, 0.31, 0.70))
    context.move(to: CGPoint(x: 340, y: 358))
    context.addQuadCurve(to: CGPoint(x: 668, y: 672), control: CGPoint(x: 470, y: 552))
    context.strokePath()

    let image = context.makeImage()!
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(points)x\(points)\(suffix).png"
        try drawIcon(size: points * scale).write(to: iconset.appendingPathComponent(name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
let preview = FileManager.default.temporaryDirectory.appendingPathComponent("QuietWall-AppIcon.png")
try drawIcon(size: 1024).write(to: preview)
print("Generated Resources/AppIcon.icns; preview: \(preview.path)")
