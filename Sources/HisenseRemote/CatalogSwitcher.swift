import SwiftUI

/// The original Dashboard/Remote lens, reused for Apps/Inputs. One glass identity
/// survives the whole animation; position drives lift and stretch, including reversals.
struct CatalogSwitcher: View {
    @Binding var selection: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isPressing = false
    var body: some View {
        ZStack(alignment: .leading) {
            SelectionLens(position: selection == 0 ? 0 : 1,
                          engagement: isPressing ? 1 : 0,
                          reduceMotion: reduceMotion,
                          reduceTransparency: reduceTransparency,
                          increasedContrast: contrast == .increased)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88), value: selection)
                .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.9), value: isPressing)
                .allowsHitTesting(false).accessibilityHidden(true)
            HStack(spacing: 2) {
                segment("Apps", symbol: "square.grid.2x2", index: 0)
                segment("Inputs", symbol: "cable.connector", index: 1)
            }.padding(4).zIndex(1)
        }
        .frame(width: 276, height: 40)
        .background(Color.primary.opacity(reduceTransparency ? 0.1 : 0.055), in: .capsule)
        .overlay(Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.06), lineWidth: 1))
        .accessibilityElement(children: .contain).accessibilityLabel("TV destinations")
        .onDisappear { isPressing = false }
    }
    private func segment(_ title: String, symbol: String, index: Int) -> some View {
        Button { selection = index } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selection == index ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity).frame(height: 32).contentShape(Capsule())
        }
        .buttonStyle(LensPressStyle { isPressing = $0 })
        .accessibilityLabel(title).accessibilityAddTraits(selection == index ? .isSelected : [])
        .help("Show \(title.lowercased())")
    }
}
private struct LensPressStyle: ButtonStyle {
    var pressingChanged: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, pressed in pressingChanged(pressed) }
    }
}
private struct SelectionLens: View, Animatable {
    var position: CGFloat
    var engagement: CGFloat
    var reduceMotion: Bool
    var reduceTransparency: Bool
    var increasedContrast: Bool
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(position, engagement) }
        set { position = newValue.first; engagement = newValue.second }
    }
    var body: some View {
        let progress = min(1, max(0, position))
        let travel = sin(.pi * progress)
        let lift = reduceMotion ? 0 : max(travel, min(1, max(0, engagement)))
        let stretch = reduceMotion ? 0 : travel
        let extraWidth = 22 * stretch + 6 * lift
        let height = 32 + 8 * lift
        Capsule()
            .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : .clear)
            .frame(width: 133 + extraWidth, height: height)
            .glassEffect(reduceTransparency ? .identity : .regular, in: .capsule)
            .overlay {
                if !reduceTransparency {
                    Capsule().fill(Color(nsColor: .controlColor)).opacity(0.14 * (1 - lift))
                }
            }
            .overlay {
                Capsule().strokeBorder(increasedContrast ? Color.primary.opacity(0.5) : Color.white.opacity(0.04 + 0.16 * lift), lineWidth: increasedContrast ? 1.5 : 0.65)
            }
            .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.03 + 0.1 * lift), radius: 1 + 5 * lift, y: 1 + 3 * lift)
            .offset(x: 4 + 135 * position - extraWidth / 2, y: -lift)
    }
}
