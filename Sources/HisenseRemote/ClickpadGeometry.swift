import Foundation

/// One shared geometry for hover regions and arrow anchors. Half-open sectors
/// ensure diagonal boundaries belong to one direction, never all four buttons.
struct ClickpadGeometry {
    static func contains(_ point: CGPoint, size: CGSize, angle: Double) -> Bool {
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        let outer = min(size.width, size.height) / 2
        let radius = hypot(dx, dy)
        guard outer > 0, radius >= outer * 0.49, radius <= outer else { return false }
        let degrees = atan2(dy, dx) * 180 / .pi
        let delta = (degrees - angle + 405).truncatingRemainder(dividingBy: 360)
        return delta < 90
    }
    static func anchor(angle: Double) -> CGPoint {
        CGPoint(x: 0.5 + cos(angle * .pi / 180) * 70 / 184,
                y: 0.5 + sin(angle * .pi / 180) * 70 / 184)
    }
}
