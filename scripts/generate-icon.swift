// Erzeugt Resources/AppIcon.icns: Keycap mit ⌥-Symbol und Lupe.
// Aufruf:  swift scripts/generate-icon.swift
import AppKit

let canvas: CGFloat = 1024

// Geometrie der Lupe (in 1024er-Koordinaten, Ursprung unten links)
let lensCenter = CGPoint(x: 620, y: 420)
let lensRadius: CGFloat = 185
let handleLength: CGFloat = 170
let handleWidth: CGFloat = 62
let magnification: CGFloat = 1.4

func drawGlyph(scale: CGFloat = 1, around anchor: CGPoint? = nil) {
    let fontSize: CGFloat = 470 * scale
    let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1),
    ]
    let string = NSAttributedString(string: "⌥", attributes: attributes)
    let size = string.size()
    // Glyph-Zentrum leicht nach oben links, Lupe sitzt unten rechts
    var center = CGPoint(x: 450, y: 570)
    if let anchor {
        // Um den Ankerpunkt (Linsenmitte) vergrößern: Zentrum entsprechend verschieben
        center = CGPoint(x: anchor.x + (center.x - anchor.x) * scale,
                         y: anchor.y + (center.y - anchor.y) * scale)
    }
    string.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .calibratedRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)

    // ── Keycap (Squircle im Apple-Icon-Raster: ~82 % der Fläche) ──
    let capRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let cap = NSBezierPath(roundedRect: capRect, xRadius: 185, yRadius: 185)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.985, green: 0.985, blue: 0.995, alpha: 1),
        NSColor(calibratedRed: 0.82, green: 0.82, blue: 0.86, alpha: 1),
    ])!.draw(in: cap, angle: -90)
    // dezente Kante wie bei einer Taste
    NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
    cap.lineWidth = 6
    cap.stroke()

    // ── ⌥-Symbol ──
    cap.setClip()
    drawGlyph()

    // ── Linse: Hintergrund neu füllen, Symbol vergrößert hineinzeichnen ──
    let lensRect = CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
                          width: lensRadius * 2, height: lensRadius * 2)
    let lens = NSBezierPath(ovalIn: lensRect)

    cg.saveGState()
    lens.setClip()
    NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.97, alpha: 1).setFill()
    lensRect.fill()
    // leichter Glas-Schimmer (unter dem Symbol, sonst wirkt es ausgewaschen)
    NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.3),
        NSColor(calibratedWhite: 1, alpha: 0.0),
    ])!.draw(in: lens, angle: -60)
    drawGlyph(scale: magnification, around: lensCenter)
    cg.restoreGState()

    // ── Fassung und Griff ──
    let rim = NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.95, alpha: 1)
    rim.setStroke()
    lens.lineWidth = 40
    lens.stroke()

    let direction = CGPoint(x: cos(-CGFloat.pi / 4), y: sin(-CGFloat.pi / 4))
    let start = CGPoint(x: lensCenter.x + direction.x * (lensRadius + 14),
                        y: lensCenter.y + direction.y * (lensRadius + 14))
    let end = CGPoint(x: lensCenter.x + direction.x * (lensRadius + handleLength),
                      y: lensCenter.y + direction.y * (lensRadius + handleLength))
    let handle = NSBezierPath()
    handle.move(to: start)
    handle.line(to: end)
    handle.lineWidth = handleWidth
    handle.lineCapStyle = .round
    handle.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// ── Iconset schreiben und zu .icns packen ──
let fm = FileManager.default
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let repoRoot = scriptDir.deletingLastPathComponent()
let iconsetURL = repoRoot.appendingPathComponent("build/AppIcon.iconset")
let icnsURL = repoRoot.appendingPathComponent("Resources/AppIcon.icns")

try? fm.removeItem(at: iconsetURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in entries {
    let rep = render(pixels: px)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: iconsetURL.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil fehlgeschlagen")
}
print("OK: \(icnsURL.path)")
