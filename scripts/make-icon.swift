import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, pixels) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
] {
    let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    let scale = CGFloat(pixels) / 1024
    let transform = AffineTransform(scale: scale)
    (transform as NSAffineTransform).concat()
    NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 36, y: 36, width: 952, height: 952), xRadius: 210, yRadius: 210).fill()
    // Original chip artwork; the application icon does not embed an SF Symbol.
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 282, y: 310, width: 460, height: 460), xRadius: 64, yRadius: 64).fill()
    for offset in [350, 462, 574, 686] {
        for rect in [NSRect(x: 214, y: offset, width: 92, height: 34),
                     NSRect(x: 718, y: offset, width: 92, height: 34),
                     NSRect(x: offset, y: 242, width: 34, height: 92),
                     NSRect(x: offset, y: 746, width: 34, height: 92)] {
            NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15).fill()
        }
    }
    NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.20, alpha: 1).setFill()
    for y in [430, 515, 600] {
        NSBezierPath(roundedRect: NSRect(x: 366, y: y, width: 292, height: 36), xRadius: 18, yRadius: 18).fill()
    }
    NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 700, y: 146, width: 204, height: 204)).fill()
    NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.59, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 722, y: 168, width: 160, height: 160)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = representation.representation(using: .png, properties: [:])!
    try data.write(to: folder.appendingPathComponent(name + ".png"))
}
