import AppKit

/// Lounge Remote's optical-size outline, matching Resources/SofaMenuBar.svg.
/// macOS supplies the menu-bar foreground through the template image.
enum SofaStatusIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.translateX(by: 9, yBy: 9)
            transform.rotate(byDegrees: 16)
            transform.translateX(by: -9, yBy: -9)
            transform.concat()
            NSColor.black.setStroke()

            let outline = NSBezierPath(roundedRect: NSRect(x: 5.15, y: 1.35, width: 7.7, height: 15.3), xRadius: 3.4, yRadius: 3.4)
            let clickpad = NSBezierPath(ovalIn: NSRect(x: 6.8, y: 3.15, width: 4.4, height: 4.4))
            let seat = NSBezierPath()
            seat.move(to: NSPoint(x: 6.9, y: 12.7))
            seat.line(to: NSPoint(x: 6.9, y: 13.1))
            // Exact cubic equivalent of SVG Q9 14.25 11.1 13.1.
            seat.curve(to: NSPoint(x: 11.1, y: 13.1),
                       controlPoint1: NSPoint(x: 8.3, y: 13.8666666667),
                       controlPoint2: NSPoint(x: 9.7, y: 13.8666666667))
            seat.line(to: NSPoint(x: 11.1, y: 12.7))
            for path in [outline, clickpad, seat] {
                path.lineWidth = 1.25
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sofa"
        return image
    }
}
