import AppKit

/// A small-size adaptation of Sofa.icon's rounded back, twin cushions and arms.
/// The template lets the menu bar supply its own foreground in every appearance.
enum SofaStatusIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            let back = NSBezierPath()
            back.move(to: NSPoint(x: 3.5, y: 10))
            back.line(to: NSPoint(x: 3.5, y: 12.75))
            back.curve(to: NSPoint(x: 5.25, y: 14.5),
                       controlPoint1: NSPoint(x: 3.5, y: 13.75),
                       controlPoint2: NSPoint(x: 4.25, y: 14.5))
            back.line(to: NSPoint(x: 12.75, y: 14.5))
            back.curve(to: NSPoint(x: 14.5, y: 12.75),
                       controlPoint1: NSPoint(x: 13.75, y: 14.5),
                       controlPoint2: NSPoint(x: 14.5, y: 13.75))
            back.line(to: NSPoint(x: 14.5, y: 10))
            back.lineWidth = 1.25
            back.lineCapStyle = .round
            back.lineJoinStyle = .round
            back.stroke()

            let front = NSBezierPath()
            front.move(to: NSPoint(x: 1, y: 9.5))
            front.curve(to: NSPoint(x: 4, y: 9.5),
                        controlPoint1: NSPoint(x: 1, y: 11.5),
                        controlPoint2: NSPoint(x: 4, y: 11.5))
            front.line(to: NSPoint(x: 4, y: 7))
            front.line(to: NSPoint(x: 14, y: 7))
            front.line(to: NSPoint(x: 14, y: 9.5))
            front.curve(to: NSPoint(x: 17, y: 9.5),
                        controlPoint1: NSPoint(x: 14, y: 11.5),
                        controlPoint2: NSPoint(x: 17, y: 11.5))
            front.line(to: NSPoint(x: 17, y: 5.5))
            front.curve(to: NSPoint(x: 15.5, y: 4),
                        controlPoint1: NSPoint(x: 17, y: 4.5),
                        controlPoint2: NSPoint(x: 16.5, y: 4))
            front.line(to: NSPoint(x: 2.5, y: 4))
            front.curve(to: NSPoint(x: 1, y: 5.5),
                        controlPoint1: NSPoint(x: 1.5, y: 4),
                        controlPoint2: NSPoint(x: 1, y: 4.5))
            front.close()
            front.lineWidth = 1.25
            front.lineCapStyle = .round
            front.lineJoinStyle = .round
            front.stroke()

            let details = NSBezierPath()
            details.move(to: NSPoint(x: 9, y: 7))
            details.line(to: NSPoint(x: 9, y: 10.5))
            for x: CGFloat in [3, 15] {
                details.move(to: NSPoint(x: x, y: 4))
                details.line(to: NSPoint(x: x, y: 2.5))
            }
            details.lineWidth = 1.25
            details.lineCapStyle = .round
            details.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sofa"
        return image
    }
}
