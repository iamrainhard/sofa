import AppKit
// Deterministic artwork composed from the native icon export and real app screenshots.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let transform = NSAffineTransform(); transform.translateX(by: 0, yBy: 630); transform.scaleX(by: 1, yBy: -1); transform.concat()
let background = NSColor(srgbRed: 0.063, green: 0.102, blue: 0.094, alpha: 1)
background.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform(); t.translateX(by: x, yBy: y + size * 1.18); t.scaleX(by: 1, yBy: -1); t.concat()
    (value as NSString).draw(at: .zero, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    NSGraphicsContext.restoreGraphicsState()
}
func image(_ name: String, _ r: NSRect) {
    let image = NSImage(contentsOf: root.appendingPathComponent("docs/images/\(name)"))!
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform(); t.translateX(by: r.minX, yBy: r.maxY); t.scaleX(by: 1, yBy: -1); t.concat()
    image.draw(in: NSRect(origin: .zero, size: r.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
}
let white = NSColor(srgbRed: 0.95, green: 0.96, blue: 0.92, alpha: 1)
let mint = NSColor(srgbRed: 0.84, green: 0.94, blue: 0.69, alpha: 1)
let secondary = NSColor(srgbRed: 0.66, green: 0.71, blue: 0.68, alpha: 1)
image("icon.png", NSRect(x: 58, y: 55, width: 84, height: 84))
text("Sofa", 159, 66, 40, .semibold, white)
text("for Mac", 162, 115, 16, .regular, secondary)
text("Your TV,", 60, 218, 66, .semibold, white)
text("from your Mac.", 60, 296, 66, .semibold, mint)
text("A little remote in your menu bar.", 64, 405, 24, .regular, secondary)
text("Free & open source  ·  macOS 26+", 64, 555, 18, .medium, mint)
image("home-transparent.png", NSRect(x: 696, y: 82, width: 244, height: 425))
image("remote-transparent.png", NSRect(x: 900, y: 156, width: 244, height: 425))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("docs/images/sofa-social-v2.png"))
