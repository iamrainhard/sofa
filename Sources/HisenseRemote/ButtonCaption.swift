import SwiftUI

enum ButtonCaptionPlacement { case above, below, leading, trailing }

private struct ButtonCaptionValue {
    let title: String
    let anchor: Anchor<CGRect>
    let point: CGPoint?
    let placement: ButtonCaptionPlacement
}

private struct ButtonCaptionKey: PreferenceKey {
    static var defaultValue: ButtonCaptionValue? { nil }
    static func reduce(value: inout ButtonCaptionValue?, nextValue: () -> ButtonCaptionValue?) {
        if let next = nextValue() { value = next }
    }
}

private struct ButtonCaption: ViewModifier {
    let title: String
    @State private var hovering = false
    func body(content: Content) -> some View {
        content

            .onContinuousHover { phase in
                switch phase {
                case .active: hovering = true
                case .ended: hovering = false
                }
            }
            .anchorPreference(key: ButtonCaptionKey.self, value: .bounds) { anchor in
                hovering ? ButtonCaptionValue(title: title, anchor: anchor, point: nil, placement: .below) : nil
            }
            .onDisappear { hovering = false }
    }
}

/// One hover observer owns the whole pad. Overlapping SwiftUI button bounds
/// cannot steal hover events or overwrite another arrow's caption.
private struct ClickpadCaption: ViewModifier {
    @State private var location: CGPoint?
    @State private var size = CGSize.zero
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): location = point
                case .ended: location = nil
                }
            }
            .anchorPreference(key: ButtonCaptionKey.self, value: .bounds) { anchor in
                guard let location else { return nil }
                for (angle, title, placement) in [(-90.0, "Up", ButtonCaptionPlacement.above),
                                                  (0.0, "Right", .trailing), (90.0, "Down", .below), (180.0, "Left", .leading)] {
                    if ClickpadGeometry.contains(location, size: size, angle: angle) {
                        return ButtonCaptionValue(title: title, anchor: anchor,
                                                  point: ClickpadGeometry.anchor(angle: angle), placement: placement)
                    }
                }
                if hypot(location.x - size.width / 2, location.y - size.height / 2) <= 39 {
                    return ButtonCaptionValue(title: "Select", anchor: anchor, point: CGPoint(x: 0.5, y: 0.7), placement: .below)
                }
                return nil
            }
            .onDisappear { location = nil }
    }
}

extension View {
    func buttonCaption(_ title: String) -> some View { modifier(ButtonCaption(title: title)) }

    func clickpadCaption() -> some View { modifier(ClickpadCaption()) }

    /// Render above the entire panel so captions cannot be clipped by scroll views.
    func buttonCaptionOverlay() -> some View {
        overlayPreferenceValue(ButtonCaptionKey.self) { value in
            GeometryReader { geometry in
                if let value {
                    let fullBounds = geometry[value.anchor]
                    let bounds = value.point.map {
                        CGRect(x: fullBounds.minX + $0.x * fullBounds.width - 9,
                               y: fullBounds.minY + $0.y * fullBounds.height - 9, width: 18, height: 18)
                    } ?? fullBounds
                    CaptionBubble(title: value.title, bounds: bounds, panel: geometry.size, placement: value.placement)
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

private struct CaptionBubble: View {
    let title: String
    let bounds: CGRect
    let panel: CGSize
    let placement: ButtonCaptionPlacement
    @State private var size = CGSize(width: 100, height: 26)
    private var position: CGPoint {
        let proposed: CGPoint
        switch placement {
        case .above: proposed = CGPoint(x: bounds.midX, y: bounds.minY - size.height / 2 - 6)
        case .below:
            proposed = CGPoint(x: bounds.midX, y: bounds.maxY + size.height + 12 < panel.height
                               ? bounds.maxY + size.height / 2 + 6 : bounds.minY - size.height / 2 - 6)
        case .leading: proposed = CGPoint(x: bounds.minX - size.width / 2 - 6, y: bounds.midY)
        case .trailing: proposed = CGPoint(x: bounds.maxX + size.width / 2 + 6, y: bounds.midY)
        }
        return CGPoint(x: min(max(proposed.x, size.width / 2 + 8), panel.width - size.width / 2 - 8),
                       y: min(max(proposed.y, size.height / 2 + 8), panel.height - size.height / 2 - 8))
    }
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .fixedSize().padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .position(position)
    }
}
