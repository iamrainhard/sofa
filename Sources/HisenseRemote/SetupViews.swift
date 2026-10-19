import AppKit
import SwiftUI
import ServiceManagement

struct OnboardingView: View {
    @ObservedObject var model: RemoteModel
    @State private var started = false
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            if !started && (model.previewState == nil || model.previewState == "welcome") || model.ready {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 100, height: 100)
            }
            if !started && (model.previewState == nil || model.previewState == "welcome") && !model.ready {
                VStack(spacing: 8) {
                    Text("Meet Sofa.").font(.system(size: 32, weight: .semibold, design: .rounded))
                    Text("Your TV. Within reach.").font(.title3).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 22) {
                    benefit("menubar.rectangle", "A little remote, always nearby", "Lives quietly in your Mac’s menu bar.")
                    benefit("sparkles.tv", "Your favourites, one click away", "Apps, inputs and volume in one place.")
                    benefit("lock.shield", "At home on your network", "Pair directly. No Sofa account needed.")
                }.padding(.vertical, 12)
                Button("Set up my TV") { started = true }.buttonStyle(.sofaCapsule(prominent: true)).controlSize(.large)
                Text("Hisense VIDAA · Google / Android TV · Samsung Tizen\nGoogle / Android TV and Samsung support are experimental.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            } else if model.ready {
                VStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(.green)
                    Text("Make yourself at home.").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("Your Mac is paired with your TV.").foregroundStyle(.secondary)
                }
                TextField("Give your TV a name (optional)", text: $model.nickname).textFieldStyle(.roundedBorder)
                Text("You’ll find Sofa under the couch icon in your menu bar. You can change startup preferences in Settings.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let warning = model.credentialWarning { Text(warning).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Button("Open Sofa") { model.completeSetup() }.buttonStyle(.sofaCapsule(prominent: true)).controlSize(.large)
            } else {
                ConnectionSetupView(model: model)
            }
            Spacer(minLength: 12)
            HStack {
                Text("SOFA  ·  BETA").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28)
    }
    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 21)).frame(width: 30).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct ConnectionSetupView: View {
    @ObservedObject var model: RemoteModel
    @State private var certificateDetails = false
    var body: some View {
        VStack(spacing: 12) {
            if model.status == "trust" {
                Text(model.certificateChanged ? "TV identity changed" : "Is this your TV?").font(.title2.bold())
                Text(model.certificateChanged ? "The certificate differs from your saved TV. Verify the IP address on your TV before trusting it again." : "Check this address matches Settings → Network on your TV before pairing.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(model.host).font(.title3.monospaced())
                DisclosureGroup("Certificate fingerprint", isExpanded: $certificateDetails) {
                    Text(model.fingerprint).font(.system(size: 9, design: .monospaced)).textSelection(.enabled)
                }.font(.caption)
                Button("Trust this TV") { model.trustTV() }.buttonStyle(.sofaCapsule(prominent: true))
                Button("Choose another TV") { model.disconnect() }.buttonStyle(.plain)
            } else if model.status == "pairing" && model.activePlatform.usesTVApproval {
                Image(systemName: "tv.badge.wifi").font(.system(size: 38, weight: .light)).foregroundStyle(.tint)
                Text("Allow Sofa on your TV").font(.title2.bold())
                Text(model.pairingPrompt).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if model.waitingForTVApproval {
                    ProgressView().controlSize(.small)
                    Text("Waiting for your TV’s approval…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Try again") { model.repair() }.buttonStyle(.sofaCapsule(prominent: true))
                }
                Text("If no prompt appears, check your TV’s External Device Manager → Device Connection Manager. Menu names vary by model.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("Experimental · Tizen TVs with secure network remote control.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Choose another TV") { model.disconnect() }.buttonStyle(.plain)
            } else if model.status == "pairing" {
                Text(model.platformTitle).font(.caption).foregroundStyle(.secondary)
                Text("Pair your Mac").font(.title2.bold())
                Text(model.pairingPrompt).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(model.pendingPair ? "Show a new code" : "Show code on TV") { model.pair() }.buttonStyle(.sofaCapsule()).disabled(model.isBusy)
                TextField(model.activePlatform == .androidtv ? "Six-character code" : "Pairing code", text: $model.pin).textFieldStyle(.roundedBorder)
                    .font(.title2.monospaced()).multilineTextAlignment(.center)
                    .onChange(of: model.pin) { _, value in model.pin = model.activePlatform.pairingCode(value) }
                    .onSubmit { if model.validPIN && !model.isBusy { model.submitPIN() } }
                Button(model.isBusy ? "Checking code…" : "Pair Mac") { model.submitPIN() }.buttonStyle(.sofaCapsule(prominent: true)).disabled(!model.validPIN || model.isBusy)
                Button("Back") { model.disconnect() }.buttonStyle(.plain)
            } else {
                Text("Find your TV").font(.title2.bold())
                Text("Turn on your TV and use the same Wi-Fi. If macOS asks, allow Local Network access so Sofa can find and control it.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button { model.discover() } label: {
                    HStack { if model.discovering { ProgressView().controlSize(.small) }; Text(model.discovering ? "Looking for TVs…" : "Find nearby TVs") }
                }.buttonStyle(.sofaCapsule()).disabled(model.discovering || model.isBusy)
                if !model.discoveryMessage.isEmpty { Text(model.discoveryMessage).font(.caption).foregroundStyle(.secondary) }
                if !model.discoveredTVs.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(model.discoveredTVs) { tv in
                                Button { model.choose(tv) } label: {
                                    HStack { Image(systemName: "tv"); VStack(alignment: .leading) { Text(tv.name).lineLimit(1); Text(tv.platform.title).font(.caption2).foregroundStyle(.secondary); Text(tv.host).font(.caption2).foregroundStyle(.tertiary) }; Spacer(); Image(systemName: "chevron.right") }.padding(5).frame(width: 210)
                                }.buttonStyle(.sofaRounded()).disabled(model.isBusy)
                            }
                        }.padding(4)
                    }.scrollIndicators(.hidden).frame(height: 72)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or enter the TV’s IP address").font(.caption).foregroundStyle(.secondary)
                    TextField("192.168.1.100", text: $model.host).textFieldStyle(.roundedBorder).disabled(model.isBusy).onSubmit { if !model.isBusy { model.connect() } }
                    Picker("TV platform", selection: $model.selectedPlatform) {
                        ForEach(TVConnectionPlatform.allCases) { platform in Text(platform.title).tag(platform) }
                    }.disabled(model.isBusy)
                    Text(model.selectedPlatform == .samsung ? "Experimental · Approve Sofa on the TV. Secure Tizen remote service required; older Samsung models are not supported." : model.selectedPlatform == .androidtv ? "Experimental · Uses Android TV Remote Service. No developer mode needed." : "Find the address in your TV’s Settings → Network.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button { model.connect() } label: {
                    HStack { if model.isBusy { ProgressView().controlSize(.small) }; Text(model.isBusy ? "Connecting…" : "Connect") }
                }.buttonStyle(.sofaCapsule(prominent: true)).disabled(model.host.isEmpty || model.isBusy)
                if model.isBusy { Button("Cancel", action: model.disconnect).buttonStyle(.plain) }
                if model.pairingNeedsAttention {
                    Button(model.activePlatform.usesTVApproval ? "Pair again on TV" : "Pair again with a new TV code") { model.repair() }.buttonStyle(.sofaCapsule())
                }
                Button("Open Privacy & Security settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") { NSWorkspace.shared.open(url) }
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.tint)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct SofaSettingsView: View {
    @ObservedObject var model: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var forget = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    var body: some View {
        VStack(spacing: 22) {
            HStack { Text("Sofa settings").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            Picker("Settings section", selection: $tab) { Text("TV").tag(0); Text("General").tag(1); Text("About").tag(2) }.pickerStyle(.segmented).labelsHidden()
            if tab == 0 {
                if model.ready {
                    Image(systemName: "tv").font(.system(size: 42)).foregroundStyle(.secondary)
                    VStack(spacing: 5) { Text(model.displayName).font(.title3.bold()); Text(model.modelName).foregroundStyle(.secondary); Label("Connected", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                    LabeledContent("TV name") { TextField("Optional name", text: $model.nickname).textFieldStyle(.roundedBorder).frame(width: 190) }
                    LabeledContent("IP address", value: model.host).font(.callout)
                    HStack { Button("Refresh TV") { model.refresh() }; Button("Pair again") { model.repair() } }.buttonStyle(.sofaCapsule())
                    Button("Forget this TV…", role: .destructive) { forget = true }.buttonStyle(.plain)
                } else { ConnectionSetupView(model: model) }
            } else if tab == 1 {
                VStack(alignment: .leading, spacing: 22) {
                    Toggle("Open Sofa at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                        guard model.previewState == nil else { return }
                        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                        catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                    }
                    Toggle("Connect to my TV when Sofa opens", isOn: $model.reconnectOnLaunch)
                    if model.activePlatform == .androidtv {
                        Toggle("Keyboard and current app updates", isOn: $model.androidIME)
                        Text("Turn off if your TV hides its on-screen keyboard. Reconnect to apply.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Sofa stays in your menu bar. Closing its panel keeps the connection available; choose Quit from the menu to stop it.").font(.callout).foregroundStyle(.secondary)
                    if SMAppService.mainApp.status == .requiresApproval { Button("Allow in Login Items settings") { SMAppService.openSystemSettingsLoginItems() } }
                    if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                    Divider()
                    Label("Pairing is stored in your Mac’s Keychain.", systemImage: "lock.shield").font(.callout)
                    Text("No analytics or Sofa account. App artwork is fetched from VIDAA’s image service and cached on this Mac.").font(.caption).foregroundStyle(.secondary)
                }.toggleStyle(.switch)
            } else {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
                VStack(spacing: 5) { Text("Sofa").font(.largeTitle.bold()); Text("Your TV. Within reach.").foregroundStyle(.secondary); Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0") · Beta").font(.caption).foregroundStyle(.secondary) }
                HStack { Link("GitHub", destination: URL(string: "https://github.com/iamrainhard/sofa")!); Link("Check for updates", destination: URL(string: "https://github.com/iamrainhard/sofa/releases")!) }
                HStack { Link("Privacy", destination: URL(string: "https://github.com/iamrainhard/sofa/blob/main/docs/PRIVACY.md")!); Link("Help", destination: URL(string: "https://github.com/iamrainhard/sofa/blob/main/docs/TROUBLESHOOTING.md")!) }
                Text("Free and open source. Made by Rainhard Ngambiye.\nIndependent software, not affiliated with TV manufacturers or platform owners.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(26).frame(width: 410, height: model.ready ? 520 : 600)
        .confirmationDialog("Forget this TV?", isPresented: $forget, titleVisibility: .visible) {
            Button("Forget TV", role: .destructive) { model.forgetTV() }
        } message: { Text("Removes this Mac’s saved pairing and TV settings. You’ll need to approve pairing on the TV again.") }
    }
}
