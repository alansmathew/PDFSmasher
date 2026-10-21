// Draws all PDF Smasher artwork from code so every asset is original and reproducible.
//
//   swift Scripts/generate-assets.swift
//
// Outputs:
//   Resources/AppIcon.icns
//   Resources/ProfileIcon.icns          (icon for exported .pdfsmash profiles)
//   Resources/Assets/DropTarget.png     (+ @2x, template image for the empty state)
//   docs/icon.png                       (512 px icon for the README)

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: - Helpers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func render(size: Int, draw: (CGContext, CGFloat) -> Void) -> CGImage {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)
    draw(ctx, scale)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func makeIconset(named name: String, draw: @escaping (CGContext, CGFloat) -> Void) {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        writePNG(render(size: base, draw: draw), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
        writePNG(render(size: base * 2, draw: draw), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
    let output = root.appendingPathComponent("Resources/\(name).icns")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try! task.run()
    task.waitUntilExit()
    print("wrote \(output.path)")
}

// MARK: - App icon

/// A squashed document under a press plate on a warm gradient tile.
func drawAppIcon(_ ctx: CGContext, _ scale: CGFloat) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)

    // Tile shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale, color: color(0x000000, 0.35))
    ctx.addPath(roundedRect(tile, 185))
    ctx.setFillColor(color(0xF2513F))
    ctx.fillPath()
    ctx.restoreGState()

    // Tile gradient
    ctx.saveGState()
    ctx.addPath(roundedRect(tile, 185))
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFF9A3C), color(0xF2513F), color(0xD81F63)] as CFArray,
        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Soft top highlight
    let highlight = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(highlight, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])

    // Impact lines on both sides of the document
    ctx.setStrokeColor(color(0xFFFFFF, 0.85))
    ctx.setLineCap(.round)
    ctx.setLineWidth(22)
    for (x1, y1, x2, y2) in [
        (238.0, 470.0, 178.0, 500.0), (238.0, 400.0, 168.0, 400.0), (238.0, 330.0, 178.0, 300.0),
        (786.0, 470.0, 846.0, 500.0), (786.0, 400.0, 856.0, 400.0), (786.0, 330.0, 846.0, 300.0),
    ] {
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Press: piston and plate
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 18 * scale, color: color(0x5A0A22, 0.45))
    ctx.addPath(roundedRect(CGRect(x: 467, y: 700, width: 90, height: 190), 22))
    ctx.setFillColor(color(0x2B1830))
    ctx.fillPath()
    ctx.addPath(roundedRect(CGRect(x: 228, y: 640, width: 568, height: 86), 30))
    ctx.setFillColor(color(0x2B1830))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(roundedRect(CGRect(x: 248, y: 696, width: 528, height: 16), 8))
    ctx.setFillColor(color(0xFFFFFF, 0.16))
    ctx.fillPath()

    // Squashed document with folded corner
    let doc = CGRect(x: 262, y: 228, width: 500, height: 396)
    let fold: CGFloat = 96
    let page = CGMutablePath()
    page.move(to: CGPoint(x: doc.minX + 28, y: doc.minY))
    page.addLine(to: CGPoint(x: doc.maxX - 28, y: doc.minY))
    page.addQuadCurve(to: CGPoint(x: doc.maxX, y: doc.minY + 28), control: CGPoint(x: doc.maxX, y: doc.minY))
    page.addLine(to: CGPoint(x: doc.maxX, y: doc.maxY - fold))
    page.addLine(to: CGPoint(x: doc.maxX - fold, y: doc.maxY))
    page.addLine(to: CGPoint(x: doc.minX + 28, y: doc.maxY))
    page.addQuadCurve(to: CGPoint(x: doc.minX, y: doc.maxY - 28), control: CGPoint(x: doc.minX, y: doc.maxY))
    page.addLine(to: CGPoint(x: doc.minX, y: doc.minY + 28))
    page.addQuadCurve(to: CGPoint(x: doc.minX + 28, y: doc.minY), control: CGPoint(x: doc.minX, y: doc.minY))
    page.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: color(0x5A0A22, 0.5))
    ctx.addPath(page)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    let corner = CGMutablePath()
    corner.move(to: CGPoint(x: doc.maxX, y: doc.maxY - fold))
    corner.addLine(to: CGPoint(x: doc.maxX - fold + 14, y: doc.maxY - fold))
    corner.addQuadCurve(to: CGPoint(x: doc.maxX - fold, y: doc.maxY - fold + 14),
                        control: CGPoint(x: doc.maxX - fold, y: doc.maxY - fold))
    corner.addLine(to: CGPoint(x: doc.maxX - fold, y: doc.maxY))
    corner.closeSubpath()
    ctx.addPath(corner)
    ctx.setFillColor(color(0xF6C9C9))
    ctx.fillPath()

    // "PDF" label
    let label = NSAttributedString(string: "PDF", attributes: [
        .font: NSFont.systemFont(ofSize: 132, weight: .black),
        .foregroundColor: NSColor(cgColor: color(0xE0335A))!,
        .kern: 4,
    ])
    let line = CTLineCreateWithAttributedString(label)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: doc.minX + 52 - bounds.minX, y: doc.minY + 196 - bounds.minY)
    CTLineDraw(line, ctx)

    // Text lines
    ctx.setFillColor(color(0xE7DCE0))
    for (y, width) in [(150.0, 400.0), (104.0, 330.0), (58.0, 370.0)] {
        ctx.addPath(roundedRect(CGRect(x: doc.minX + 52, y: doc.minY + y - 30, width: width, height: 26), 13))
    }
    ctx.fillPath()
}

// MARK: - Profile document icon

func drawProfileIcon(_ ctx: CGContext, _ scale: CGFloat) {
    let doc = CGRect(x: 212, y: 100, width: 600, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 20 * scale, color: color(0x000000, 0.3))
    ctx.addPath(roundedRect(doc, 48))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Slider rows
    for (index, knob) in [0.7, 0.35, 0.55].enumerated() {
        let y = 640 - CGFloat(index) * 150
        ctx.addPath(roundedRect(CGRect(x: 292, y: y - 12, width: 440, height: 24), 12))
        ctx.setFillColor(color(0xEDE4E7))
        ctx.fillPath()
        let x = 292 + 440 * CGFloat(knob)
        ctx.addPath(roundedRect(CGRect(x: 292, y: y - 12, width: x - 292, height: 24), 12))
        ctx.setFillColor(color(0xF2513F))
        ctx.fillPath()
        ctx.addEllipse(in: CGRect(x: x - 40, y: y - 40, width: 80, height: 80))
        ctx.setFillColor(color(0xD81F63))
        ctx.fillPath()
    }

    let badge = CGRect(x: 292, y: 170, width: 440, height: 110)
    ctx.addPath(roundedRect(badge, 30))
    ctx.setFillColor(color(0x2B1830))
    ctx.fillPath()
    let label = NSAttributedString(string: "PROFILE", attributes: [
        .font: NSFont.systemFont(ofSize: 64, weight: .heavy),
        .foregroundColor: NSColor.white,
        .kern: 6,
    ])
    let line = CTLineCreateWithAttributedString(label)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: badge.midX - bounds.width / 2 - bounds.minX, y: badge.midY - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, ctx)
}

// MARK: - Empty state illustration (template: black on transparent)

func drawDropTarget(_ ctx: CGContext, _ scale: CGFloat) {
    ctx.setStrokeColor(color(0x000000))
    ctx.setFillColor(color(0x000000))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Dashed tray
    ctx.saveGState()
    ctx.setLineWidth(34)
    ctx.setLineDash(phase: 0, lengths: [70, 46])
    ctx.addPath(roundedRect(CGRect(x: 112, y: 112, width: 800, height: 520), 110))
    ctx.strokePath()
    ctx.restoreGState()

    // Document dropping in
    let doc = CGRect(x: 372, y: 300, width: 280, height: 360)
    let fold: CGFloat = 80
    let page = CGMutablePath()
    page.move(to: CGPoint(x: doc.minX, y: doc.minY + 24))
    page.addLine(to: CGPoint(x: doc.minX, y: doc.maxY - 24))
    page.addQuadCurve(to: CGPoint(x: doc.minX + 24, y: doc.maxY), control: CGPoint(x: doc.minX, y: doc.maxY))
    page.addLine(to: CGPoint(x: doc.maxX - fold, y: doc.maxY))
    page.addLine(to: CGPoint(x: doc.maxX, y: doc.maxY - fold))
    page.addLine(to: CGPoint(x: doc.maxX, y: doc.minY + 24))
    page.addQuadCurve(to: CGPoint(x: doc.maxX - 24, y: doc.minY), control: CGPoint(x: doc.maxX, y: doc.minY))
    page.addLine(to: CGPoint(x: doc.minX + 24, y: doc.minY))
    page.addQuadCurve(to: CGPoint(x: doc.minX, y: doc.minY + 24), control: CGPoint(x: doc.minX, y: doc.minY))
    ctx.setLineWidth(30)
    ctx.addPath(page)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: doc.maxX - fold, y: doc.maxY))
    ctx.addLine(to: CGPoint(x: doc.maxX - fold, y: doc.maxY - fold))
    ctx.addLine(to: CGPoint(x: doc.maxX, y: doc.maxY - fold))
    ctx.strokePath()

    // Down arrows above and squeeze arrows on the sides
    ctx.setLineWidth(34)
    ctx.move(to: CGPoint(x: 512, y: 930)); ctx.addLine(to: CGPoint(x: 512, y: 740))
    ctx.move(to: CGPoint(x: 440, y: 812)); ctx.addLine(to: CGPoint(x: 512, y: 740)); ctx.addLine(to: CGPoint(x: 584, y: 812))
    ctx.strokePath()

    ctx.setLineWidth(28)
    ctx.move(to: CGPoint(x: 230, y: 420)); ctx.addLine(to: CGPoint(x: 310, y: 420))
    ctx.move(to: CGPoint(x: 270, y: 466)); ctx.addLine(to: CGPoint(x: 316, y: 420)); ctx.addLine(to: CGPoint(x: 270, y: 374))
    ctx.move(to: CGPoint(x: 794, y: 420)); ctx.addLine(to: CGPoint(x: 714, y: 420))
    ctx.move(to: CGPoint(x: 754, y: 466)); ctx.addLine(to: CGPoint(x: 708, y: 420)); ctx.addLine(to: CGPoint(x: 754, y: 374))
    ctx.strokePath()

    // Text lines inside document
    ctx.setLineWidth(22)
    for (y, w) in [(560.0, 170.0), (500.0, 200.0), (440.0, 150.0), (380.0, 190.0)] {
        ctx.move(to: CGPoint(x: doc.minX + 50, y: y))
        ctx.addLine(to: CGPoint(x: doc.minX + 50 + w, y: y))
    }
    ctx.strokePath()
}

// MARK: - Main

makeIconset(named: "AppIcon", draw: drawAppIcon)
makeIconset(named: "ProfileIcon", draw: drawProfileIcon)

writePNG(render(size: 120, draw: drawDropTarget), to: root.appendingPathComponent("Resources/Assets/DropTarget.png"))
writePNG(render(size: 240, draw: drawDropTarget), to: root.appendingPathComponent("Resources/Assets/DropTarget@2x.png"))
writePNG(render(size: 512, draw: drawAppIcon), to: root.appendingPathComponent("docs/icon.png"))
print("wrote image assets")
