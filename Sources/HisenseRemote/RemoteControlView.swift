import SwiftUI

struct RemoteControlView: View {
    @ObservedObject var model: RemoteModel
    var showInputs: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keypadVisible = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "tv").font(.system(size: 11))
                Text(model.ready ? model.sourceName : "Connect your TV to get started")
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer()
                Text("REMOTE").font(.system(size: 8, weight: .semibold)).tracking(1.4)
            }.foregroundStyle(.secondary).padding(.horizontal, 5)

            directionalPad

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 14) {
                    control("chevron.backward", title: "Back", key: "RETURNS")
                    control("house", title: "Home", key: "HOME")
                    control("line.3.horizontal", title: "TV menu", key: "MENU")
                }
            }

            HStack(spacing: 10) {
                control("backward.fill", title: "Rewind", key: "BACK", size: 36)
                control("play.fill", title: "Play", key: "PLAY", size: 36)
                control("pause.fill", title: "Pause", key: "PAUSE", size: 36)
                control("forward.fill", title: "Fast-forward", key: "FORWARDS", size: 36)
            }

            HStack(spacing: 26) {
                rocker(title: "VOLUME", upTitle: "Volume up", downTitle: "Volume down", top: "plus", bottom: "minus", enabled: model.ready && model.hasVolume,
                       up: { model.stepVolume(1) }, down: { model.stepVolume(-1) })
                VStack(spacing: 8) {
                    Button { model.toggleMute() } label: {
                        Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2")
                            .font(.system(size: 17, weight: .medium)).contentTransition(.symbolEffect(.replace))
                            .frame(width: 38, height: 38)
                    }.buttonStyle(.glass).buttonBorderShape(.circle)
                        .tint(model.muted ? .accentColor : nil)
                        .disabled(!model.ready || !model.hasVolume)
                        .buttonCaption(model.muted ? "Unmute" : "Mute")
                        .accessibilityLabel(model.muted ? "Unmute TV" : "Mute TV")
                    Text(model.hasVolume ? "\(Int(model.volume))" : "—")
                        .font(.system(size: 22, weight: .light, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(value: model.volume))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.volume)
                        .accessibilityLabel(model.hasVolume ? "Volume \(Int(model.volume)) percent" : "Volume unavailable")
                }.frame(width: 66)
                rocker(title: "CHANNEL", upTitle: "Next channel", downTitle: "Previous channel", top: "chevron.up", bottom: "chevron.down", enabled: model.ready,
                       up: { model.key("CHANNELUP", label: "Next channel") }, down: { model.key("CHANNELDOWN", label: "Previous channel") })
            }

            HStack(spacing: 10) {
                Button(action: showInputs) { Label("Inputs", systemImage: "cable.connector") }
                    .buttonStyle(.glass).buttonBorderShape(.capsule).help("Choose a TV input")
                Button { keypadVisible.toggle() } label: { Label("Keypad", systemImage: "number") }
                    .buttonStyle(.glass).buttonBorderShape(.capsule).disabled(!model.ready)
                    .popover(isPresented: $keypadVisible, arrowEdge: .bottom) { keypad }
                Menu {
                    Button("Subtitles", systemImage: "captions.bubble") { model.key("SUBTITLE", label: "Subtitles") }
                    Button("Stop playback", systemImage: "stop.fill") { model.key("STOP", label: "Stop") }
                    Button("Exit app", systemImage: "rectangle.portrait.and.arrow.right") { model.key("EXIT", label: "Exit") }
                    Divider()
                    ForEach(["RED", "GREEN", "YELLOW", "BLUE"], id: \.self) { key in
                        Button("\(key.capitalized) function button") { model.key(key, label: key.capitalized) }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 20) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(!model.ready)
                .help("More TV controls").accessibilityLabel("More TV controls")
            }.font(.system(size: 11, weight: .medium))
            Text("Arrow keys to move · Return to select")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 26).padding(.top, 5)
    }

    private var directionalPad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                .glassEffect(reduceTransparency ? .identity : .regular, in: .rect(cornerRadius: 32))
                .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.06), lineWidth: 1))
            padDirection("chevron.up", title: "Up", key: "UP", width: 100, height: 42).offset(y: -63)
            padDirection("chevron.down", title: "Down", key: "DOWN", width: 100, height: 42).offset(y: 63)
            padDirection("chevron.left", title: "Left", key: "LEFT", width: 52, height: 82).offset(x: -86)
            padDirection("chevron.right", title: "Right", key: "RIGHT", width: 52, height: 82).offset(x: 86)
            Button { model.key("OK", label: "Select") } label: {
                Text("OK").font(.system(size: 14, weight: .semibold)).frame(width: 64, height: 64)
            }.buttonStyle(.glass).buttonBorderShape(.circle)
                .buttonCaption("Select").accessibilityLabel("Select")
        }.frame(width: 248, height: 182).disabled(!model.ready).opacity(model.ready ? 1 : 0.5)
    }
    private func padDirection(_ symbol: String, title: String, key: String, width: CGFloat, height: CGFloat) -> some View {
        Button { model.key(key, label: title) } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: width, height: height).contentShape(.rect(cornerRadius: 15))
        }.buttonStyle(RemotePressStyle()).buttonCaption(title).accessibilityLabel(title)
    }
    private func control(_ symbol: String, title: String, key: String, size: CGFloat = 44) -> some View {
        Button { model.key(key, label: title) } label: {
            Image(systemName: symbol).font(.system(size: size == 44 ? 18 : 14, weight: .medium)).frame(width: size, height: size)
        }.buttonStyle(.glass).buttonBorderShape(.circle).disabled(!model.ready)
            .buttonCaption(title).accessibilityLabel(title)
    }
    private func rocker(title: String, upTitle: String, downTitle: String, top: String, bottom: String, enabled: Bool, up: @escaping () -> Void, down: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: up) { Image(systemName: top).font(.system(size: 18, weight: .medium)).frame(width: 66, height: 38).contentShape(.rect) }
                .buttonStyle(RemotePressStyle()).buttonCaption(upTitle).accessibilityLabel(upTitle)
            Text(title).font(.system(size: 7, weight: .semibold)).tracking(1).foregroundStyle(.secondary).frame(height: 20)
            Button(action: down) { Image(systemName: bottom).font(.system(size: 18, weight: .medium)).frame(width: 66, height: 38).contentShape(.rect) }
                .buttonStyle(RemotePressStyle()).buttonCaption(downTitle).accessibilityLabel(downTitle)
        }.glassEffect(.regular, in: .capsule).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }
    private var keypad: some View {
        VStack(spacing: 14) {
            HStack { Text("Channel keypad").font(.headline); Spacer(); Button { keypadVisible = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close keypad") }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(52)), count: 3), spacing: 10) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "—", "0", "OK"], id: \.self) { value in
                    if value == "—" { Color.clear.frame(width: 52, height: 42) }
                    else {
                        Button { model.key(value, label: value == "OK" ? "Select channel" : "Digit \(value)") } label: {
                            Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).frame(width: 44, height: 36)
                        }.buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 12))
                    }
                }
            }
        }.padding(20).frame(width: 220)
    }
}
private struct RemotePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.09 : 0), in: .rect(cornerRadius: 15))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}
