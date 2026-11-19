import AppKit
import Foundation

// Generates Xavier brand assets from the two official logo files.
// Writes RGBA bytes directly (setColor is unreliable on this SDK).
// - XavierMark: template image (alpha = mark) for menu bar + in-app identity
// - AppIcon: 1024x1024 black icon with centered white mark

let whiteOnBlackPath = "/tmp/IMG_5780.png"
let blackOnWhitePath = "/tmp/IMG_5607.png"
// Resolve the asset catalog relative to this script so any checkout works.
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outDir = repoRoot
    .appendingPathComponent("Sources/Resources/Assets.xcassets").path

func load(_ path: String) -> NSBitmapImageRep {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { fatalError("cannot load \(path)") }
    return NSBitmapImageRep(cgImage: cg)
}

func lumAt(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
    guard let c = rep.colorAt(x: x, y: y) else { return 0 }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r + g + b) / 3 * a
}

func contentBounds(_ rep: NSBitmapImageRep, darkContent: Bool) -> CGRect {
    var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            let lum = lumAt(rep, x, y)
            let isContent = darkContent ? lum < 0.5 : lum > 0.5
            if isContent {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    return CGRect(x: minX, y: minY, width: max(1, maxX - minX + 1), height: max(1, maxY - minY + 1))
}

func makeRep(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
}

func setPixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) {
    guard let data = rep.bitmapData else { return }
    let i = y * rep.bytesPerRow + x * 4
    data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = a
}

// Downsample the content region into a square template image (alpha = mark coverage).
func templateMark(from rep: NSBitmapImageRep, darkContent: Bool, size: Int) -> NSBitmapImageRep {
    let b = contentBounds(rep, darkContent: darkContent)
    let side = Int(max(b.width, b.height))
    let out = makeRep(size, size)
    let cx = b.midX, cy = b.midY
    let originX = cx - CGFloat(side) / 2
    let originY = cy - CGFloat(side) / 2
    let scale = CGFloat(side) / CGFloat(size)
    for y in 0..<size {
        for x in 0..<size {
            var acc: CGFloat = 0
            var count = 0
            let sx0 = Int(originX + CGFloat(x) * scale)
            let sy0 = Int(originY + CGFloat(y) * scale)
            let sx1 = max(sx0 + 1, Int(originX + CGFloat(x + 1) * scale))
            let sy1 = max(sy0 + 1, Int(originY + CGFloat(y + 1) * scale))
            for sy in max(0, sy0)..<min(sy1, rep.pixelsHigh) {
                for sx in max(0, sx0)..<min(sx1, rep.pixelsWide) {
                    let lum = lumAt(rep, sx, sy)
                    acc += darkContent ? (1 - lum) : lum
                    count += 1
                }
            }
            let alpha = count > 0 ? UInt8(min(255, max(0, acc / CGFloat(count) * 255))) : 0
            setPixel(out, x, y, 0, 0, 0, alpha)
        }
    }
    return out
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try! data.write(to: URL(fileURLWithPath: path))
}

// 1) Template mark (menu bar + in-app), from black-on-white logo.
let markRep = load(blackOnWhitePath)
savePNG(templateMark(from: markRep, darkContent: true, size: 44), to: "\(outDir)/XavierMark.imageset/XavierMark.png")
savePNG(templateMark(from: markRep, darkContent: true, size: 88), to: "\(outDir)/XavierMark.imageset/XavierMark@2x.png")

// 2) App icon: white mark centered on black 1024 canvas.
let markSide = 576
let whiteMark = templateMark(from: load(whiteOnBlackPath), darkContent: false, size: markSide)
let icon = makeRep(1024, 1024)
let offset = (1024 - markSide) / 2
for y in 0..<1024 {
    for x in 0..<1024 {
        let mx = x - offset, my = y - offset
        var px: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 255)
        if mx >= 0, mx < markSide, my >= 0, my < markSide,
           let c = whiteMark.colorAt(x: mx, y: my) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            if a > 0 { px = (255, 255, 255, UInt8(min(255, max(0, a * 255)))) }
        }
        setPixel(icon, x, y, px.0, px.1, px.2, px.3)
    }
}
savePNG(icon, to: "\(outDir)/AppIcon.appiconset/AppIcon.png")
print("assets generated")
