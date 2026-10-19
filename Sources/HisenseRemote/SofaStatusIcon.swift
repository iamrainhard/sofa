import AppKit

/// The same 24-unit couch outline used by website/index.html's menu-bar preview.
/// A template image lets macOS supply the appropriate menu-bar foreground.
enum SofaStatusIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let scale = NSAffineTransform()
            scale.scale(by: 0.75)
            scale.concat()
            NSColor.black.setStroke()
            let path = NSBezierPath()

            // Back: M6 10 V6 a2 2 0 0 1 2-2 h8 a2 2 0 0 1 2 2 v4.
            path.move(to: NSPoint(x: 6, y: 10))
            path.line(to: NSPoint(x: 6, y: 6))
            path.curve(to: NSPoint(x: 8, y: 4), controlPoint1: NSPoint(x: 6, y: 4.89543), controlPoint2: NSPoint(x: 6.89543, y: 4))
            path.line(to: NSPoint(x: 16, y: 4))
            path.curve(to: NSPoint(x: 18, y: 6), controlPoint1: NSPoint(x: 17.10457, y: 4), controlPoint2: NSPoint(x: 18, y: 4.89543))
            path.line(to: NSPoint(x: 18, y: 10))

            for x: CGFloat in [4, 20] {
                path.move(to: NSPoint(x: x, y: 19))
                path.line(to: NSPoint(x: x, y: 21))
            }

            // Rounded arms and the open seat/base outline; no filled areas.
            path.move(to: NSPoint(x: 2, y: 11))
            path.curve(to: NSPoint(x: 4, y: 9), controlPoint1: NSPoint(x: 2, y: 9.89543), controlPoint2: NSPoint(x: 2.89543, y: 9))
            path.curve(to: NSPoint(x: 6, y: 11), controlPoint1: NSPoint(x: 5.10457, y: 9), controlPoint2: NSPoint(x: 6, y: 9.89543))
            path.line(to: NSPoint(x: 6, y: 14))
            path.line(to: NSPoint(x: 18, y: 14))
            path.line(to: NSPoint(x: 18, y: 11))
            path.curve(to: NSPoint(x: 20, y: 9), controlPoint1: NSPoint(x: 18, y: 9.89543), controlPoint2: NSPoint(x: 18.89543, y: 9))
            path.curve(to: NSPoint(x: 22, y: 11), controlPoint1: NSPoint(x: 21.10457, y: 9), controlPoint2: NSPoint(x: 22, y: 9.89543))
            path.line(to: NSPoint(x: 22, y: 17))
            path.curve(to: NSPoint(x: 20, y: 19), controlPoint1: NSPoint(x: 22, y: 18.10457), controlPoint2: NSPoint(x: 21.10457, y: 19))
            path.line(to: NSPoint(x: 4, y: 19))
            path.curve(to: NSPoint(x: 2, y: 17), controlPoint1: NSPoint(x: 2.89543, y: 19), controlPoint2: NSPoint(x: 2, y: 18.10457))
            path.close()
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sofa"
        return image
    }
}
