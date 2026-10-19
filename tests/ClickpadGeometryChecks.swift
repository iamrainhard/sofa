import Foundation

@main struct ClickpadGeometryChecks {
    static func main() {
        let size = CGSize(width: 184, height: 184)
        let angles: [Double] = [-90, 0, 90, 180]
        for angle in angles {
            let anchor = ClickpadGeometry.anchor(angle: angle)
            let point = CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)
            precondition(angles.filter { ClickpadGeometry.contains(point, size: size, angle: $0) } == [angle])
        }
        for x in stride(from: 0, through: 184, by: 2) {
            for y in stride(from: 0, through: 184, by: 2) {
                let point = CGPoint(x: Double(x), y: Double(y))
                let count = angles.filter { ClickpadGeometry.contains(point, size: size, angle: $0) }.count
                let radius = hypot(Double(x) - 92, Double(y) - 92)
                precondition(count == (radius >= 92 * 0.49 && radius <= 92 ? 1 : 0), "Hover regions must partition only the ring")
            }
        }
        print("Clickpad hover checks passed: four directions, centre exclusion and non-overlapping ring")
    }
}
