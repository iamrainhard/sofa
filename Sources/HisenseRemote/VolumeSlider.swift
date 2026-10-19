import SwiftUI

/// Let the system own the thumb, its Liquid Glass material and tracking animation.
/// Omitting `step` removes tick marks; the model rounds only the TV command.
struct VolumeSlider: View {
    let value: Double
    let enabled: Bool
    let changed: (Double) -> Void
    let editingChanged: (Bool) -> Void
    let focusChanged: (Bool) -> Void
    @State private var tracking = false
    @State private var dragValue = 0.0
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spectrum = LinearGradient(
        colors: [.blue, .cyan, .orange, .red],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        Slider(value: Binding(
            get: { tracking ? dragValue : value },
            set: { newValue in dragValue = newValue; changed(newValue) }
        ), in: 0...100, onEditingChanged: { editing in
            if editing { dragValue = value; focused = true; focusChanged(true) }
            tracking = editing
            editingChanged(editing)
        })
        .tint(levelColour)
        .overlay { gradientTrack.allowsHitTesting(false).accessibilityHidden(true) }
        .disabled(!enabled)
        .focusable().focusEffectDisabled().focused($focused)
        .accessibilityLabel("TV volume")
        .onChange(of: focused) { _, active in focusChanged(active) }
        .onDisappear { focusChanged(false) }
        .simultaneousGesture(TapGesture().onEnded { focused = true; focusChanged(true) })
        .onKeyPress { press in
            guard focused, enabled else { return .ignored }
            switch press.key {
            case .leftArrow, .downArrow: changed(max(0, value - 1)); return .handled
            case .rightArrow, .upArrow: changed(min(100, value + 1)); return .handled
            default: return .ignored
            }
        }
    }

    private var displayedValue: Double { min(100, max(0, tracking ? dragValue : value)) }

    // The native slider resolves ShapeStyle tint to one colour on this macOS version.
    // Colour only its track, with a cutout that leaves the real glass thumb untouched.
    private var gradientTrack: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thumbX = 10 + max(0, width - 20) * displayedValue / 100
            Capsule().fill(spectrum.opacity(enabled ? 1 : 0.3))
                .mask(alignment: .leading) {
                    Rectangle().frame(width: thumbX)
                }
            .frame(height: 6)
            .mask {
                Rectangle()
                    .overlay(alignment: .leading) {
                        Rectangle().frame(width: tracking ? 34 : 22)
                            .offset(x: thumbX - (tracking ? 17 : 11))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .position(x: width / 2, y: geometry.size.height / 2)
            .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: tracking)
        }
    }

    private var levelColour: Color {
        let colours: [NSColor] = [.systemBlue, .systemCyan, .systemOrange, .systemRed]
        let position = displayedValue / 100 * 3
        let index = min(2, Int(position))
        return Color(nsColor: colours[index].blended(withFraction: position - Double(index), of: colours[index + 1]) ?? colours[index])
    }

}

struct RollingVolume: View {
    let value: Double
    let available: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Text(available ? String(Int(value)) : "—")
            .font(.system(size: 54, weight: .light, design: .rounded))
            .monospacedDigit().tracking(-2)
            .contentTransition(reduceMotion ? .identity : .numericText(value: value))
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: Int(value))
            .accessibilityLabel(available ? "Volume \(Int(value)) percent" : "Volume unavailable")
    }
}
