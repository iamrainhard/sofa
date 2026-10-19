import SwiftUI

/// One persistent glass surface. Press feedback affects only the label and a
/// translucent overlay, never the material, tint, or button's layout bounds.
struct StableGlassButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 5
    var tint: Color? = nil
    var prominent = false
    var adaptsToControlSize = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let color = tint ?? (prominent ? Color.accentColor : nil)
        let glass = color.map { Glass.regular.tint($0) } ?? .regular
        let large = adaptsToControlSize && (controlSize == .large || controlSize == .extraLarge)
        let pressed = isEnabled && configuration.isPressed
        return configuration.label
            .foregroundStyle(color == nil ? Color.primary : Color.white)
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: pressed)
            .padding(.horizontal, horizontalPadding + (large ? 4 : 0))
            .padding(.vertical, verticalPadding + (large ? 3 : 0))
            .background {
                // In particular, do not animate the material or scale its bounds.
                shape.fill(reduceTransparency ? (color ?? Color(nsColor: .controlBackgroundColor)) : Color.clear)
                    .glassEffect(reduceTransparency ? .identity : glass, in: shape)
                    .overlay {
                        shape.fill((color == nil ? Color.primary : Color.black).opacity(pressed ? 0.09 : 0))
                            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: pressed)
                    }
                    .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: 1))
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension ButtonStyle where Self == StableGlassButtonStyle<Circle> {
    static func sofaCircle(tint: Color? = nil, padding: CGFloat = 4) -> Self {
        Self(shape: Circle(), horizontalPadding: padding, verticalPadding: padding, tint: tint)
    }
}

extension ButtonStyle where Self == StableGlassButtonStyle<Capsule> {
    static func sofaCapsule(prominent: Bool = false) -> Self {
        Self(shape: Capsule(), prominent: prominent, adaptsToControlSize: true)
    }
}

extension ButtonStyle where Self == StableGlassButtonStyle<RoundedRectangle> {
    static func sofaRounded(radius: CGFloat = 12) -> Self {
        Self(shape: RoundedRectangle(cornerRadius: radius), horizontalPadding: 8, verticalPadding: 4)
    }
}
