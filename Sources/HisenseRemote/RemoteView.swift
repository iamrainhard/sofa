import SwiftUI

private let ice = Color.accentColor

struct RemoteView: View {
    @ObservedObject var model: RemoteModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("catalogCategory") private var selectedTab = Self.initialCatalogCategory
    private static var initialCatalogCategory: Int {
        guard let old = UserDefaults.standard.object(forKey: "selectedControlTab") as? Int else { return 0 }
        return old == 0 ? 1 : 0
    }
    @State private var appScrollID: String?
    @State private var inputScrollID: String?
    @State private var powerConfirmation = false
    @State private var volumeFocused = false
    @FocusState private var keyboardFocused: Bool
    var body: some View {
        Group {
        if !model.onboardingComplete { OnboardingView(model: model) } else {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)
            Group {
                if !model.ready { disconnectedState }
                else if model.viewMode == 0 { dashboard } else { fullRemote }
            }
            Spacer(minLength: 8)
            footer
        }
        }
        }
        .frame(width: AppIdentity.panelSize.width, height: AppIdentity.panelSize.height)
        .buttonCaptionOverlay()
        .foregroundStyle(.primary)
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { MacBackdrop().ignoresSafeArea() }
        }
        .focusable().focusEffectDisabled().focused($keyboardFocused)
        .onAppear { keyboardFocused = model.onboardingComplete }
        .onChange(of: model.viewMode) { _, _ in keyboardFocused = true }
        .onKeyPress { press in
            if model.onboardingComplete, volumeFocused, model.ready, !model.settingsVisible {
                switch press.key {
                case .leftArrow, .downArrow: model.stepVolume(-1); return .handled
                case .rightArrow, .upArrow: model.stepVolume(1); return .handled
                default: return .ignored
                }
            }
            guard model.onboardingComplete, model.viewMode == 1, !model.settingsVisible, model.ready, !model.editingVolume, !(NSApp.keyWindow?.firstResponder is NSSlider) else { return .ignored }
            let commands: [KeyEquivalent: String] = [.upArrow: "UP", .downArrow: "DOWN", .leftArrow: "LEFT", .rightArrow: "RIGHT", .return: "OK", .escape: "RETURNS"]
            if let key = commands[press.key] { model.key(key, label: key == "RETURNS" ? "Back" : key.capitalized); return .handled }
            return .ignored
        }
        .sheet(isPresented: $model.settingsVisible) { SofaSettingsView(model: model) }
        .confirmationDialog(model.powerState == .on ? "Turn off your TV?" : "Toggle your TV’s power?", isPresented: $powerConfirmation, titleVisibility: .visible) {
            Button(model.powerState == .on ? "Turn off TV" : "Toggle power") { model.togglePower() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This sends the TV’s power button. Waking it later depends on its network standby setting.") }
    }
    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName).font(.system(size: 18, weight: .semibold, design: .rounded)).tracking(-0.3).lineLimit(1)
                Label(model.ready ? model.platformTitle + " · " + (model.powerChanging ? "Changing…" : model.powerState == .unknown ? "Unknown" : model.powerState.title) : model.platformTitle, systemImage: "tv")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { model.viewMode = model.viewMode == 1 ? 0 : 1 } label: {
                Image(systemName: "appletvremote.gen4")
                    .font(.system(size: 18, weight: .medium)).frame(width: 36, height: 36)
            }
            .buttonStyle(.sofaCircle(tint: model.viewMode == 1 ? ice : nil))
            .buttonCaption(model.viewMode == 1 ? "Dashboard" : "Remote")
            .accessibilityLabel(model.viewMode == 1 ? "Show dashboard" : "Show remote")
            .accessibilityValue(model.viewMode == 1 ? "Remote open" : "Dashboard open")
            .accessibilityAddTraits(model.viewMode == 1 ? .isSelected : [])
            Button {
                if model.powerState == .standby { model.togglePower() }
                else { powerConfirmation = true }
            } label: {
                ZStack {
                    if model.powerChanging {
                        ProgressView().controlSize(.small).scaleEffect(0.75)
                    } else {
                        Image(systemName: "power").font(.system(size: 17, weight: .medium))
                            .foregroundStyle(model.powerState == .on ? Color.primary : Color.secondary)
                    }
                }.frame(width: 36, height: 36)
                .overlay(alignment: .bottomTrailing) {
                    if !model.powerChanging {
                        Circle().fill(model.powerState == .on ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 5, height: 5).padding(3)
                    }
                }
            }
            .buttonStyle(.sofaCircle())
            .disabled(!model.ready || model.powerChanging)
            .buttonCaption(model.powerActionTitle)
            .accessibilityLabel("TV power")
            .accessibilityValue(model.powerChanging ? "Changing" : model.powerState == .unknown ? "Unknown" : model.powerState == .standby ? "Off, standby" : "On")

        }
    }
    private var disconnectedState: some View {
        let busy = model.isBusy || model.status == "connecting"
        let needsSetup = model.status == "trust" || model.status == "pairing"
        let savedAddress = ConnectionInput.privateIPv4(model.host) != nil
        return VStack(spacing: 20) {
            Spacer(minLength: 12)
            ZStack {
                Circle().fill(Color.primary.opacity(0.04)).frame(width: 86, height: 86)
                if busy { ProgressView().controlSize(.large) }
                else { Image(systemName: needsSetup ? "link" : "tv.badge.wifi").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary) }
            }.accessibilityHidden(true)
            VStack(spacing: 9) {
                Text(busy ? "Connecting to your TV" : needsSetup ? "Finish connecting" : "Connect your TV")
                    .font(.system(size: 23, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                Text(needsSetup ? "Verify your TV and finish pairing to enable its controls." : "Turn on your TV and keep it on the same home network as this Mac.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.error, !busy {
                Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity).padding(12)
                    .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 14))
            }
            VStack(spacing: 12) {
                if busy {
                    Button("Cancel", action: model.disconnect).buttonStyle(.sofaCapsule())
                } else {
                    Button(needsSetup ? "Continue setup" : savedAddress ? "Reconnect" : "Set up my TV") {
                        if savedAddress && !needsSetup { model.connect() }
                        else { model.settingsVisible = true }
                    }.buttonStyle(.sofaCapsule(prominent: true)).controlSize(.large)
                    Button("Connection settings") { model.settingsVisible = true }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
        }.padding(.horizontal, 30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var dashboard: some View {
        VStack(spacing: 0) {
            TVIllustration(title: model.ready ? model.sourceName : "Make yourself at home.", connected: model.ready, artworkURL: model.apps.first { model.activeDestination?.matches($0) == true }?.artworkURL)
                .frame(height: 164).padding(.top, 8)
            volumePanel.padding(.horizontal, 26).padding(.top, 1)
            Group {
                if model.activePlatform.hasInputCatalog { CatalogSwitcher(selection: $selectedTab) }
                else {
                    HStack {
                        Text("App shortcuts").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Input menu", systemImage: "cable.connector", action: model.showInputPicker).buttonStyle(.sofaCapsule()).font(.caption)
                    }.padding(.horizontal, 26).frame(height: 40)
                }
            }.padding(.top, 22)
            tabContent.frame(height: 158).padding(.horizontal, 20).padding(.top, 12)
        }
    }
    private var volumePanel: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    RollingVolume(value: model.volume, available: model.hasVolume)
                    Text("Volume").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.toggleMute() } label: {
                    Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.sofaCircle(tint: model.muted ? .accentColor : nil))
                .disabled(!model.canStepVolume)
                .buttonCaption(model.muted ? "Unmute" : "Mute")
                .accessibilityLabel(model.muted ? "Unmute TV" : "Mute TV")
                .accessibilityValue(model.muted ? "Muted" : "Sound on")
            }
            HStack(spacing: 12) {
                circleButton("minus", label: "Volume down", enabled: model.canStepVolume, size: 28) { model.stepVolume(-1) }
                if model.activePlatform.supportsAbsoluteVolume || model.canSetVolume {
                    VolumeSlider(value: model.volume, enabled: model.canSetVolume,
                                 changed: model.setVolume, editingChanged: { editing in
                        if editing { model.beginVolumeEdit() } else { model.endVolumeEdit() }
                    }, focusChanged: { volumeFocused = $0 }).frame(height: 32)
                } else {
                    Text("Use − / + to adjust").font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).frame(height: 32)
                }
                circleButton("plus", label: "Volume up", enabled: model.canStepVolume, size: 28) { model.stepVolume(1) }
            }
        }
    }
    @ViewBuilder private var tabContent: some View {
        if !model.ready {
            VStack(spacing: 10) {
                Text("Your apps, one connection away.").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Button { model.settingsVisible = true } label: { Label("Connect your TV", systemImage: "link").font(.system(size: 12, weight: .semibold)).padding(5) }
                    .buttonStyle(.sofaCapsule(prominent: true)).tint(.blue)
            }
        } else if selectedTab == 1 && model.activePlatform.hasInputCatalog {
            if model.sources.isEmpty { emptyContent("No inputs received", subtitle: "Refresh to ask your TV again.") }
            else { CatalogShelf(items: model.sources, active: model.activeDestination, pending: model.pendingDestination, feedback: model.destinationFeedback, inputs: true, action: model.selectSource, scrollID: $inputScrollID) }
        } else {
            if model.apps.isEmpty { emptyContent("No apps received", subtitle: "Only apps reported by your TV appear here.") }
            else { CatalogShelf(items: model.apps, active: model.activeDestination, pending: model.pendingDestination, feedback: model.destinationFeedback, shortcuts: !model.activePlatform.hasInstalledAppCatalog, action: model.launch, scrollID: $appScrollID) }
        }
    }
    private var fullRemote: some View {
        RemoteControlView(model: model) { model.viewMode = 0; selectedTab = 1 }
    }
    private func circleButton(_ symbol: String, label: String, enabled: Bool? = nil, size: CGFloat = 42, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: size < 40 ? 12 : 16, weight: .medium)).frame(width: size, height: size) }
            .buttonStyle(.sofaCircle()).disabled(!(enabled ?? model.ready)).buttonCaption(label).accessibilityLabel(label)
    }
    private func emptyContent(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5))
            Button("Refresh", action: model.refresh).buttonStyle(.sofaCapsule()).font(.system(size: 11))
        }
    }
    private var footer: some View {
        VStack(spacing: 12) {
            if let error = model.error, model.ready {
                Button { model.settingsVisible = true } label: {
                    Label(error, systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
            Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
            HStack(spacing: 7) {
                Circle().fill(model.ready ? .green : model.hasVolume ? .orange : .gray).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.statusLabel).font(.system(size: 10, weight: .semibold))
                    Text(model.ready ? model.activity : model.host).font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.45)).lineLimit(1)
                }
                Spacer()
                Button { model.settingsVisible = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28) }.buttonStyle(.plain).buttonCaption("Connection settings").accessibilityLabel("Connection settings")
                Menu {
                    Menu("TV controls") {
                        Button("Menu", systemImage: "line.3.horizontal") { model.key("MENU", label: "Menu") }
                        if model.activePlatform.supportsKey("EXIT") { Button("Exit", systemImage: "rectangle.portrait.and.arrow.right") { model.key("EXIT", label: "Exit") } }
                        Button("Play", systemImage: "play.fill") { model.key("PLAY", label: "Play") }
                        Button("Pause", systemImage: "pause.fill") { model.key("PAUSE", label: "Pause") }
                    }.disabled(!model.ready)
                    Divider()
                    Button("Refresh TV", systemImage: "arrow.clockwise") { model.refresh() }
                    Divider()
                    Button("Quit Sofa", systemImage: "power") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().buttonCaption("More options")
            }
        }.padding(.horizontal, 20).padding(.bottom, 19)
    }
}

struct TVIllustration: View {
    let title: String
    let connected: Bool
    var artworkURL: URL? = nil
    private var platform: TVPlatform { TVPlatform(reportedName: title, connected: connected) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                platform.background
                CatalogArtwork(url: artworkURL, symbol: platform.symbol)
                    .frame(width: 90, height: 90).clipShape(.rect(cornerRadius: 16)).offset(y: -2)

                VStack(alignment: .leading, spacing: 0) {
                    Text(connected ? "ON YOUR TV" : "READY WHEN YOU ARE")
                        .font(.system(size: 7, weight: .medium)).tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(connected ? platform.accent : .gray).frame(width: 4, height: 4)
                        Text(platform.name).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: connected ? "tv" : "wifi.slash")
                            .font(.system(size: 10, weight: .regular)).foregroundStyle(.white.opacity(0.4))
                    }
                }.padding(13)
            }
            .frame(width: 248, height: 140)
            .clipShape(.rect(cornerRadius: 8))
            .padding(3)
            .background(Color(white: 0.04), in: .rect(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.26), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.22), radius: 9, y: 5)
            RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.28)).frame(width: 21, height: 6)
            Capsule().fill(Color(white: 0.48)).frame(width: 65, height: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(connected ? "Active on TV: \(platform.name)" : "TV awaiting connection")
        .help(connected ? "Active app or input reported by your TV" : "Connect to see your TV’s active app")
    }
}

/// Native behind-window vibrancy, so the actual desktop contributes to the panel.
struct MacBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
