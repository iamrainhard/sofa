import SwiftUI

private struct ButtonCaptionValue {
    let title: String
    let anchor: Anchor<CGRect>
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
            .help(title)
            .onContinuousHover { phase in
                switch phase {
                case .active: hovering = true
                case .ended: hovering = false
                }
            }
            .anchorPreference(key: ButtonCaptionKey.self, value: .bounds) { anchor in
                hovering ? ButtonCaptionValue(title: title, anchor: anchor) : nil
            }
            .onDisappear { hovering = false }
    }
}

extension View {
    func buttonCaption(_ title: String) -> some View { modifier(ButtonCaption(title: title)) }

    /// Render above the entire panel so captions cannot be clipped by scroll views.
    func buttonCaptionOverlay() -> some View {
        overlayPreferenceValue(ButtonCaptionKey.self) { value in
            GeometryReader { geometry in
                if let value {
                    let bounds = geometry[value.anchor]
                    CaptionBubble(title: value.title, bounds: bounds, panel: geometry.size)
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
    @State private var size = CGSize(width: 100, height: 26)
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .fixedSize().padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .position(x: min(max(bounds.midX, size.width / 2 + 8), panel.width - size.width / 2 - 8),
                      y: bounds.maxY + size.height + 12 < panel.height ? bounds.maxY + size.height / 2 + 6 : bounds.minY - size.height / 2 - 6)
    }
}
