import AppKit
import SwiftUI
import ServiceManagement

struct OnboardingView: View {
    @ObservedObject var model: RemoteModel
    @State private var started = false
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 100, height: 100)
            if !started && model.previewState != "pair" && !model.ready {
                VStack(spacing: 8) {
                    Text("Meet Sofa.").font(.system(size: 32, weight: .semibold, design: .rounded))
                    Text("Your TV. Within reach.").font(.title3).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 22) {
                    benefit("menubar.rectangle", "A little remote, always nearby", "Lives quietly in your Mac’s menu bar.")
                    benefit("sparkles.tv", "Your favourites, one click away", "Apps, inputs and volume in one place.")
                    benefit("lock.shield", "At home on your network", "Pair directly. No Sofa account needed.")
                }.padding(.vertical, 12)
                Button("Set up my TV") { started = true }.buttonStyle(.glassProminent).controlSize(.large)
                Text("For compatible Hisense VIDAA TVs.\nKeep your Mac and TV on the same network.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            } else if model.ready {
                VStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(.green)
                    Text("Make yourself at home.").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("Your Mac is paired with your TV.").foregroundStyle(.secondary)
                }
                TextField("Give your TV a name (optional)", text: $model.nickname).textFieldStyle(.roundedBorder)
                Text("You’ll find Sofa under the TV icon in your menu bar. You can change startup preferences in Settings.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open Sofa") { model.completeSetup() }.buttonStyle(.glassProminent).controlSize(.large)
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
        VStack(spacing: 16) {
            if model.status == "trust" {
                Text(model.certificateChanged ? "TV identity changed" : "Is this your TV?").font(.title2.bold())
                Text(model.certificateChanged ? "The certificate differs from your saved TV. Verify the IP address on your TV before trusting it again." : "Check this address matches Settings → Network on your TV before pairing.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(model.host).font(.title3.monospaced())
                DisclosureGroup("Certificate fingerprint", isExpanded: $certificateDetails) {
                    Text(model.fingerprint).font(.system(size: 9, design: .monospaced)).textSelection(.enabled)
                }.font(.caption)
                Button("Trust this TV") { model.trustTV() }.buttonStyle(.glassProminent)
                Button("Choose another TV") { model.disconnect() }.buttonStyle(.plain)
            } else if model.status == "pairing" {
                Text("Pair your Mac").font(.title2.bold())
                Text("Show a pairing code on your TV, then enter it here.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(model.pendingPair ? "Show a new code" : "Show code on TV") { model.pair() }.buttonStyle(.glass)
                TextField("Pairing code", text: $model.pin).textFieldStyle(.roundedBorder)
                    .font(.title2.monospaced()).multilineTextAlignment(.center)
                    .onChange(of: model.pin) { _, value in model.pin = String(value.filter(\.isNumber).prefix(8)) }
                    .onSubmit { if validPIN { model.submitPIN() } }
                Button("Pair Mac") { model.submitPIN() }.buttonStyle(.glassProminent).disabled(!validPIN)
                Button("Back") { model.disconnect() }.buttonStyle(.plain)
            } else {
                Text("Find your TV").font(.title2.bold())
                Text("Turn on your TV and connect it to the same network as this Mac.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { model.discover() } label: {
                    HStack { if model.discovering { ProgressView().controlSize(.small) }; Text(model.discovering ? "Looking for TVs…" : "Find nearby TVs") }
                }.buttonStyle(.glass).disabled(model.discovering || model.isBusy)
                if !model.discoveryMessage.isEmpty { Text(model.discoveryMessage).font(.caption).foregroundStyle(.secondary) }
                ForEach(model.discoveredTVs.prefix(3)) { tv in
                    Button { model.host = tv.host; model.connect() } label: {
                        HStack { Image(systemName: "tv"); VStack(alignment: .leading) { Text(tv.name).lineLimit(1); Text(tv.host).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }.padding(5)
                    }.buttonStyle(.glass).disabled(model.isBusy)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or enter the TV’s IP address").font(.caption).foregroundStyle(.secondary)
                    TextField("192.168.1.100", text: $model.host).textFieldStyle(.roundedBorder).onSubmit { model.connect() }
                    Text("Find it in your TV’s Settings → Network.").font(.caption2).foregroundStyle(.secondary)
                }
                Button { model.connect() } label: {
                    HStack { if model.isBusy { ProgressView().controlSize(.small) }; Text(model.isBusy ? "Connecting…" : "Connect") }
                }.buttonStyle(.glassProminent).disabled(model.host.isEmpty || model.isBusy)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private var validPIN: Bool { (4...8).contains(model.pin.count) && model.pin.allSatisfy { $0.isASCII && $0.isNumber } }
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
                    HStack { Button("Refresh TV") { model.refresh() }; Button("Pair again") { model.repair() } }.buttonStyle(.glass)
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
                Text("Free and open source. Made by Rainhard Ngambiye.\nIndependent software, not affiliated with Hisense or VIDAA.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(26).frame(width: 410, height: 520)
        .confirmationDialog("Forget this TV?", isPresented: $forget, titleVisibility: .visible) {
            Button("Forget TV", role: .destructive) { model.forgetTV() }
        } message: { Text("Removes this Mac’s saved pairing and TV settings. You’ll need a new code from the TV to reconnect.") }
    }
}
