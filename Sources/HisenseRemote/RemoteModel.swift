import AppKit
import Combine
import Foundation
import Security
import Network

@MainActor
final class RemoteModel: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
    @Published var selectedPlatform = TVConnectionPlatform(rawValue: UserDefaults.standard.string(forKey: "tvConnectionPlatform") ?? "") ?? (UserDefaults.standard.string(forKey: "tvHost")?.isEmpty == false ? .vidaa : .automatic)
    @Published private(set) var activePlatform = TVConnectionPlatform(rawValue: UserDefaults.standard.string(forKey: "tvConnectionPlatform") ?? "vidaa") ?? .vidaa
    @Published var androidIME = UserDefaults.standard.object(forKey: "androidIME") as? Bool ?? true {
        didSet { defaults.set(androidIME, forKey: "androidIME") }
    }
    var platformTitle: String { activePlatform.title }
    var canStepVolume: Bool { ready && (hasVolume || activePlatform == .androidtv) }
    @Published private var androidSliderAvailable = true
    var canSetVolume: Bool { ready && hasVolume && (activePlatform.supportsAbsoluteVolume || (activePlatform == .androidtv && androidSliderAvailable)) }
    var pairingPrompt: String { activePlatform == .androidtv ? "Enter the six-character code shown on your TV. Letters A–F are normal." : "Show a pairing code on your TV, then enter it here." }
    var validPIN: Bool { activePlatform.validPairingCode(pin) }
    private var sessionID = UUID().uuidString
    private var discoveryID = UUID().uuidString
    private let androidDiscovery = TVDiscovery()
    @Published var deviceName = "Your TV"
    @Published var nickname = UserDefaults.standard.string(forKey: "tvNickname") ?? "" {
        didSet { defaults.set(nickname, forKey: "tvNickname") }
    }
    var displayName: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? deviceName : nickname }
    @Published var onboardingComplete = false
    @Published var discoveredTVs: [DiscoveredTV] = []
    @Published var discovering = false
    @Published var discoveryMessage = ""
    @Published var localNetworkNeedsAttention = false
    @Published var pairingNeedsAttention = false
    @Published private(set) var credentialWarning: String?
    @Published var reconnectOnLaunch = UserDefaults.standard.object(forKey: "autoConnect") as? Bool ?? true {
        didSet { defaults.set(reconnectOnLaunch, forKey: "autoConnect") }
    }
    let previewState: String?
    func completeSetup() { onboardingComplete = true; defaults.set(true, forKey: "onboardingComplete") }
    func discover() {
        guard previewState == nil, !discovering else { return }
        startBridge()
        guard process != nil else { return }
        let token = UUID().uuidString
        discoveryID = token
        discovering = true; discoveredTVs = []; discoveryMessage = "Looking on your local network…"
        androidDiscovery.start { [weak self] tv in
            guard let self, self.discoveryID == token, self.discovering else { return }
            self.addDiscovered(tv)
        } failed: { [weak self] in
            guard let self, self.discoveryID == token else { return }
            self.discoveryMessage = "Discovery needs Local Network access. You can also enter an IP address."
        }
        send(["action": "discover", "discovery": token])
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.discoveryID == token else { return }
            self.androidDiscovery.stop(); self.discovering = false
            self.discoveryMessage = self.discoveredTVs.isEmpty ? "No TV found. Check Local Network access or enter its address." : "Choose your TV to connect."
        }
    }
    private func addDiscovered(_ tv: DiscoveredTV) {
        guard !discoveredTVs.contains(where: { $0.id == tv.id }) else { return }
        discoveredTVs.append(tv)
        discoveryMessage = "Choose your TV to connect."
    }
    func choose(_ tv: DiscoveredTV) {
        host = tv.host; selectedPlatform = tv.platform; deviceName = tv.name
        connect()
    }
    func forgetTV() {
        guard clearCredentials(host) else { error = "Sofa couldn’t remove the pairing from Keychain. Unlock your login Keychain and try again."; return }
        disconnect(); defaults.removeObject(forKey: activePlatform.certificateKey(host: host))
        host = ""; nickname = ""; deviceName = "Your TV"; defaults.removeObject(forKey: "tvHost")
        onboardingComplete = false; defaults.set(false, forKey: "onboardingComplete"); settingsVisible = false
        defaults.removeObject(forKey: "tvConnectionPlatform"); selectedPlatform = .automatic
    }
    @Published var modelName = "Hisense · VIDAA"
    @Published var status = "offline" {
        didSet {
            if status != "ready" {
                hasVolume = false
                androidSliderAvailable = true
                powerState = .unknown; powerChanging = false
                activeDestination = nil; pendingDestination = nil; destinationFeedback = nil
                destinationTimeout?.cancel(); destinationRefresh?.cancel()
                powerTimeout?.cancel(); powerRefresh?.cancel()
                volumeWork?.cancel(); volumeWork = nil; volumeTimeout?.cancel(); volumeReadback?.cancel(); volumeInteraction.cancel()
            }
        }
    }
    @Published private(set) var powerState: TVPowerState = .unknown
    @Published private(set) var powerChanging = false
    @Published private var volumeInteraction = VolumeInteraction()
    var volume: Double { volumeInteraction.displayed }
    var editingVolume: Bool { volumeInteraction.editing }
    @Published var hasVolume = false
    @Published var muted = false
    @Published var activity = "Ready when you are"
    @Published private(set) var activeDestination: TVDestination?
    @Published private(set) var pendingDestination: TVDestination?
    @Published private(set) var destinationFeedback: String?
    private var destinationTimeout: DispatchWorkItem?
    private var destinationRefresh: DispatchWorkItem?
    @Published var sourceName = "Your favourite screen."
    @Published var error: String?
    @Published var fingerprint = ""
    @Published var certificateChanged = false
    @Published var apps: [TVItem] = []
    @Published var sources: [TVItem] = []
    @Published var settingsVisible = false
    @Published var pin = ""
    @Published var isBusy = false
    @Published var pendingPair = false
    @Published var viewMode = UserDefaults.standard.integer(forKey: "remoteViewMode") {
        didSet { UserDefaults.standard.set(viewMode, forKey: "remoteViewMode") }
    }
    private var powerTimeout: DispatchWorkItem?
    private var powerRefresh: DispatchWorkItem?
    private var requestedPower: TVPowerState = .unknown
    var powerActionTitle: String {
        if powerChanging { return "Waiting for TV…" }
        if !ready { return "Power unavailable · not connected" }
        switch powerState {
        case .on: return "Turn TV off"
        case .standby: return "Turn TV on"
        case .unknown: return "Toggle power · status unknown"
        }
    }
    func togglePower() {
        guard ready, !powerChanging else { return }
        requestedPower = powerState == .on ? .standby : powerState == .standby ? .on : .unknown
        powerChanging = true
        key("POWER", label: "Power command sent · awaiting TV")
        powerTimeout?.cancel(); powerRefresh?.cancel()
        let refresh = DispatchWorkItem { [weak self] in self?.refresh() }
        powerRefresh = refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: refresh)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.powerChanging else { return }
            self.powerChanging = false; self.powerState = .unknown
            self.activity = "Power change not confirmed"
        }
        powerTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }
    private func updatePower(_ state: [String: Any]) {
        let reported = TVPowerState.reported(by: state)
        guard reported != .unknown else { return }
        powerState = reported
        if powerChanging, requestedPower == .unknown || requestedPower == reported {
            powerChanging = false; powerTimeout?.cancel()
        }
        // VIDAA publishes changes and retains its last state. Quiet is not a power change.
        // Invalidate it when the monitored MQTT connection is lost.
    }
    private var networkCheck: NWConnection?
    private var process: Process?
    private var bridgeGeneration = UUID()
    private var input: FileHandle?
    private var reader: Task<Void, Never>?
    private var volumeWork: DispatchWorkItem?
    private var volumeTimeout: DispatchWorkItem?
    private var volumeReadback: DispatchWorkItem?
    private var ignoreVolumeBroadcastsUntil = Date.distantPast
    private var feedbackWork: DispatchWorkItem?
    private var reconnectWork: DispatchWorkItem?
    private var connectedHost = ""
    private let defaults = UserDefaults.standard
    var ready: Bool { status == "ready" }
    var statusLabel: String {
        switch status {
        case "ready": return "Connected"
        case "connecting": return "Connecting"
        case "pairing": return "Pair your Mac"
        case "trust": return "Verify TV"
        default: return hasVolume ? "TV reachable" : "Not connected"
        }
    }
    var deviceID: String {
        if let value = defaults.string(forKey: "clientDeviceID") { return value }
        var bytes = [UInt8](repeating: 0, count: 5)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = "02:" + bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        defaults.set(value, forKey: "clientDeviceID")
        return value
    }
    init(previewState: String? = nil) {
        self.previewState = previewState ?? Bundle.main.object(forInfoDictionaryKey: "SofaPreviewState") as? String
        onboardingComplete = defaults.bool(forKey: "onboardingComplete") || (!host.isEmpty && defaults.bool(forKey: "autoConnect"))
        if let previewState = self.previewState {
            host = "192.168.1.100"; deviceName = "Living Room TV"
            onboardingComplete = previewState == "remote" || previewState == "offline" || previewState == "connecting"
            if previewState == "remote" || previewState == "success" {
                status = "ready"; hasVolume = true; sourceName = "Home"; volumeInteraction.report(24)
            }
            if previewState.hasPrefix("android") {
                activePlatform = .androidtv; selectedPlatform = .androidtv
                if previewState == "android-pair" { status = "pairing"; pendingPair = true }
                if previewState == "android-home" || previewState == "android-remote" {
                    onboardingComplete = true; status = "ready"; sourceName = "Google TV Home"; hasVolume = true; volumeInteraction.report(36)
                    apps = [TVItem(id: 0, name: "YouTube"), TVItem(id: 1, name: "Netflix"), TVItem(id: 2, name: "Prime Video"), TVItem(id: 3, name: "Disney+")]
                    viewMode = previewState == "android-remote" ? 1 : 0
                }
            }
            if previewState == "remote" { viewMode = 1 }
            if previewState == "pair" { status = "pairing" }
            if previewState == "offline" { error = "The TV did not respond. Check its IP address and Local Network permission." }
            if previewState == "connecting" { status = "connecting"; isBusy = true }
            if previewState == "network" {
                localNetworkNeedsAttention = true
                error = "Allow Sofa in System Settings → Privacy & Security → Local Network, then Connect again."
            }
            if previewState == "trust" { status = "trust"; fingerprint = Array(repeating: "AB:12", count: 10).joined(separator: ":") }
            if previewState == "discovery" {
                discoveredTVs = (1...5).map { DiscoveredTV(host: "192.168.1.\(100 + $0)", name: "Living Room TV \($0)", model: "VIDAA") }
                discoveryMessage = "Choose your TV to connect."
            }
            return
        }
        startBridge()
        if onboardingComplete && reconnectOnLaunch { connect() }
    }
    func startBridge() {
        guard process == nil else { return }
        guard previewState == nil else { return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/SofaBridge.app/Contents/MacOS/SofaBridge")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            error = "Sofa’s connection helper is missing. Reinstall Sofa from the official release."; return
        }
        let task = Process()
        task.executableURL = helper
        task.arguments = []
        task.environment = ["PATH": "/usr/bin:/bin", "PYTHONUNBUFFERED": "1", "PYTHONDONTWRITEBYTECODE": "1"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        task.standardInput = stdin; task.standardOutput = stdout; task.standardError = stderr
        // Never copy bridge output to logs: credential events contain private pairing tokens.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        do {
            try task.run()
            let generation = UUID(); bridgeGeneration = generation
            process = task; input = stdin.fileHandleForWriting
            let handle = stdout.fileHandleForReading
            reader = Task.detached { [weak self] in
                var buffer = Data()
                while !Task.isCancelled {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = buffer[..<newline]
                        buffer.removeSubrange(...newline)
                        if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                            await self?.receive(object, generation: generation)
                        }
                    }
                }
                await self?.bridgeEnded(generation: generation)
            }
        } catch { self.error = "Could not start the local TV bridge: \(error.localizedDescription)" }
    }
    private func receive(_ object: [String: Any], generation: UUID) {
        guard generation == bridgeGeneration else { return }
        receive(object)
    }
    func bridgeEnded(generation: UUID) {
        guard generation == bridgeGeneration else { return }
        process = nil; input = nil; status = "offline"; isBusy = false
    }
    func shutdown() { destinationTimeout?.cancel(); destinationRefresh?.cancel(); volumeWork?.cancel(); volumeTimeout?.cancel(); volumeReadback?.cancel(); powerTimeout?.cancel(); powerRefresh?.cancel(); androidDiscovery.stop(); networkCheck?.cancel(); input?.closeFile(); process?.terminate(); reader?.cancel() }
    func send(_ value: [String: Any]) {
        var message = value
        message["session"] = sessionID
        guard let input, let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do { try input.write(contentsOf: data + Data([10])) }
        catch { self.error = "The local connection stopped. Reconnect to try again."; status = "offline" }
    }
    func connect() {
        guard previewState == nil else { status = "pairing"; return }
        guard let candidate = ConnectionInput.privateIPv4(host) else {
            error = "Enter your TV’s private IPv4 address, such as 192.168.1.100."; return
        }
        networkCheck?.cancel(); networkCheck = nil
        androidDiscovery.stop(); discovering = false; discoveryID = UUID().uuidString
        reconnectWork?.cancel()
        sessionID = UUID().uuidString
        startBridge()
        guard process != nil else { return }
        send(["action": "disconnect"])
        host = candidate; localNetworkNeedsAttention = false; pairingNeedsAttention = false; credentialWarning = nil
        pendingPair = false; pin = ""; apps = []; sources = []; sourceName = "Connected TV"
        error = nil; status = "connecting"; isBusy = true
        let candidates: [TVConnectionPlatform] = selectedPlatform == .automatic ? [.androidtv, .vidaa] : [selectedPlatform]
        checkNetwork(candidate, candidates: candidates, session: sessionID)
    }
    private func checkNetwork(_ host: String, candidates: [TVConnectionPlatform], session: String) {
        guard session == sessionID, let platform = candidates.first else { return }
        let check = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: platform.port)!, using: .tcp)
        networkCheck = check
        let failed: () -> Void = { [weak self, weak check] in
            guard let self, let check, self.networkCheck === check, self.sessionID == session else { return }
            check.cancel(); self.networkCheck = nil
            if candidates.count > 1 { self.checkNetwork(host, candidates: Array(candidates.dropFirst()), session: session) }
            else {
                self.status = "offline"; self.isBusy = false
                self.error = "No compatible remote service responded. Keep the TV awake, check its address, or select its platform below."
            }
        }
        check.stateUpdateHandler = { [weak self, weak check] state in
            DispatchQueue.main.async {
                guard let self, let check, self.networkCheck === check, self.sessionID == session else { return }
                switch state {
                case .ready:
                    check.cancel(); self.networkCheck = nil
                    self.activePlatform = platform
                    self.connectBridge()
                case .waiting:
                    if check.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        check.cancel(); self.networkCheck = nil
                        self.localNetworkNeedsAttention = true; self.isBusy = false; self.status = "offline"
                        self.error = "Allow Sofa in System Settings → Privacy & Security → Local Network, then Connect again."
                    }
                case .failed: failed()
                default: break
                }
            }
        }
        check.start(queue: .global(qos: .userInitiated))
        DispatchQueue.main.asyncAfter(deadline: .now() + (selectedPlatform == .automatic ? 4 : 12)) { failed() }
    }
    private func connectBridge() {
        reconnectWork?.cancel()
        startBridge()
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter your TV’s IP address."; return }
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil; fingerprint = ""; isBusy = true; status = "connecting"
        hasVolume = false; apps = []; sources = []; connectedHost = host
        defaults.set(host, forKey: "tvHost")
        defaults.set(activePlatform.rawValue, forKey: "tvConnectionPlatform")
        selectedPlatform = activePlatform
        var request: [String: Any] = ["action": "connect", "host": host, "device": deviceID,
                                     "platform": activePlatform.rawValue, "enable_ime": androidIME,
                                     "fingerprint": defaults.string(forKey: activePlatform.certificateKey(host: host)) ?? ""]
        do {
            if let saved = try loadCredentials(host) { request["saved"] = saved }
        } catch {
            pairingNeedsAttention = true
            self.error = "Sofa couldn’t read its saved pairing. Unlock your login Keychain and allow Sofa when macOS asks, then connect again. If the saved pairing is damaged, use Pair again."
            isBusy = false; status = "offline"; return
        }
        send(request)
    }
    func trustTV() {
        guard !fingerprint.isEmpty else { return }
        defaults.set(fingerprint, forKey: activePlatform.certificateKey(host: host))
        connect()
    }
    func pair() {
        error = nil; pendingPair = true; pin = ""; isBusy = true
        send(["action": "pair"])
    }
    func submitPIN() {
        guard validPIN, !isBusy else { return }
        error = nil; isBusy = true
        send(["action": "pin", "pin": pin])
        activity = "Checking pairing code…"
    }
    func repair() {
        guard clearCredentials(host) else { error = "Sofa couldn’t reset the saved pairing. Unlock your login Keychain and try again."; return }
        connect()
    }
    func disconnect() {
        sessionID = UUID().uuidString
        networkCheck?.cancel(); networkCheck = nil
        reconnectWork?.cancel()
        send(["action": "disconnect"]); status = "offline"; hasVolume = false; isBusy = false
        pendingPair = false; pin = ""
        apps = []; sources = []; sourceName = "Your favourite screen."
    }
    func refresh() { error = nil; send(["action": "refresh"]) }
    func key(_ key: String, label: String) {
        guard ready else { settingsVisible = true; return }
        guard activePlatform.supportsKey(key) else { return }
        if previewState != nil { activity = "Preview · \(label)"; return }
        send(["action": "key", "key": key, "label": label])
    }
    func seek(forward: Bool) {
        key(TVPlaybackControl.seekKey(forward: forward, appName: sourceName, platform: activePlatform),
            label: forward ? "Fast-forward" : "Rewind")
    }
    func beginVolumeEdit() { volumeInteraction.begin() }
    func endVolumeEdit() {
        volumeInteraction.end()
        if activePlatform == .androidtv { volumeInteraction.finishRelativeEdit() } else { drainVolume() }
    }
    func setVolume(_ value: Double) {
        guard canSetVolume else { return }
        volumeInteraction.propose(value)
        if activePlatform == .androidtv {
            if let request = volumeInteraction.supersedeRequest() { sendVolume(request) }
        } else if volumeWork == nil { drainVolume() }
    }
    private func drainVolume() {
        guard ready, let request = volumeInteraction.nextRequest() else { return }
        sendVolume(request)
    }
    private func sendVolume(_ request: VolumeInteraction.Request) {
        send(["action": "volume", "value": Int(request.value), "request": request.id])
        volumeTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.volumeInteraction.inFlight?.id == request.id else { return }
            self.volumeInteraction.cancel()
            if self.activePlatform == .androidtv { self.send(["action": "cancel_volume"]); self.androidSliderAvailable = false }
            self.error = "Volume update wasn’t confirmed. Refresh to read the TV."
        }
        volumeTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }
    private func volumeCompleted(_ object: [String: Any]) {
        guard let id = object["request"] as? Int, volumeInteraction.inFlight?.id == id else { return }
        volumeTimeout?.cancel()
        guard let actual = object["value"] as? Int else {
            volumeInteraction.cancel()
            error = "The TV couldn’t confirm the volume. Refresh and try again."
            return
        }
        volumeInteraction.complete(id: id, actual: Double(actual))
        if activePlatform == .androidtv { return }
        ignoreVolumeBroadcastsUntil = Date().addingTimeInterval(0.6)
        volumeReadback?.cancel()
        let readback = DispatchWorkItem { [weak self] in
            guard let self, self.ready, self.volumeInteraction.inFlight == nil, self.volumeInteraction.target == nil else { return }
            self.send(["action": "read_volume"])
        }
        volumeReadback = readback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: readback)
        // Coalesce a fast drag; never queue every intermediate position behind a slow TV.
        let work = DispatchWorkItem { [weak self] in
            self?.volumeWork = nil; self?.drainVolume()
        }
        volumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
    func stepVolume(_ amount: Int) {
        guard canStepVolume else { return }
        if activePlatform.supportsAbsoluteVolume { setVolume(volume + Double(amount)) }
        else {
            volumeInteraction.cancel(); volumeTimeout?.cancel()
            key(amount > 0 ? "VOLUMEUP" : "VOLUMEDOWN", label: amount > 0 ? "Volume up" : "Volume down")
        }
    }
    func toggleMute() {
        guard canStepVolume else { return }
        if activePlatform == .androidtv { volumeInteraction.cancel(); volumeTimeout?.cancel() }
        send(["action": "mute", "value": !muted])
    }
    func showInputPicker() { key("INPUT", label: "Input menu") }
    func launch(_ item: TVItem) { openDestination(item, action: "app") }
    func selectSource(_ item: TVItem) { openDestination(item, action: "source") }
    private func openDestination(_ item: TVItem, action: String) {
        guard ready, pendingDestination?.key != item.destination.key else { return }
        let catalog = action == "app" ? apps : sources
        guard catalog.contains(where: { $0.id == item.id && $0.stableID == item.stableID }) else { refresh(); return }
        pendingDestination = item.destination; destinationFeedback = nil
        destinationTimeout?.cancel(); destinationRefresh?.cancel()
        send(["action": action, "index": item.id, "label": "Opening \(item.name)…"])
        let refresh = DispatchWorkItem { [weak self] in self?.send(["action": "refresh"]) }
        destinationRefresh = refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: refresh)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingDestination?.key == item.destination.key else { return }
            self.pendingDestination = nil
            self.destinationFeedback = self.activePlatform == .androidtv ? "Not confirmed. Install this app on your TV first." : "Couldn’t confirm \(item.name). Try again."
        }
        destinationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }
    func receive(_ object: [String: Any]) {
        if object["event"] as? String != "discovery", previewState == nil || object["session"] != nil {
            guard object["session"] as? String == sessionID else { return }
        }
        switch object["event"] as? String {
        case "discovery":
            guard object["discovery"] as? String == discoveryID, discovering else { return }
            for value in object["devices"] as? [[String: String]] ?? [] {
                guard let host = value["host"] else { continue }
                addDiscovered(DiscoveredTV(host: host, name: value["name"] ?? "VIDAA TV", model: value["model"] ?? "", platform: .vidaa))
            }
        case "device":
            if let name = object["name"] as? String, !name.isEmpty { deviceName = name }
            if let name = object["model"] as? String, !name.isEmpty { modelName = activePlatform == .vidaa ? "Hisense · \(name)" : name }
        case "volume":
            if let value = object["value"] as? Int {
                if object["source"] as? String == "readback" || Date() >= ignoreVolumeBroadcastsUntil {
                    volumeInteraction.report(Double(value))
                }
                hasVolume = true
            }
            if let value = object["muted"] as? Bool { muted = value }
        case "volume_result": volumeCompleted(object)
        case "volume_control_unavailable":
            if activePlatform == .androidtv {
                androidSliderAvailable = false; volumeInteraction.cancel(); volumeTimeout?.cancel()
                error = "This TV isn’t confirming volume changes. Use − / +, or reconnect to try the slider again."
            }
        case "mute": muted = object["value"] as? Bool ?? false
        case "status":
            // The disconnect acknowledgement belongs to the previous session, not the native permission/reachability check.
            if networkCheck != nil, object["value"] as? String == "offline" { return }
            status = object["value"] as? String ?? "offline"
            isBusy = status == "connecting"
            if status == "pairing" { settingsVisible = onboardingComplete; pendingPair = activePlatform == .androidtv }
            if ready {
                pendingPair = false; pin = ""; error = credentialWarning; activity = "You’re in control"

            }
        case "trust":
            fingerprint = object["fingerprint"] as? String ?? ""
            certificateChanged = object["changed"] as? Bool ?? false
            status = "trust"; settingsVisible = onboardingComplete; isBusy = false
        case "credentials":
            if let value = object["value"] as? [String: Any] { saveCredentials(value, host: connectedHost) }
        case "apps": apps = TVItem.parse(object["value"], keys: ["name", "appName", "appname", "title"], kind: .app)
        case "sources": sources = TVItem.parse(object["value"], keys: ["sourcename", "sourceName", "name", "displayname"], kind: .input)
        case "state":
            if let value = object["value"] as? [String: Any] {
                updatePower(value)
                activeDestination = TVDestination.reported(by: value)
                if powerState == .standby { activeDestination = nil; pendingDestination = nil; destinationTimeout?.cancel() }
                if let pendingDestination, activeDestination?.key == pendingDestination.key {
                    self.pendingDestination = nil; destinationFeedback = nil
                    destinationTimeout?.cancel(); destinationRefresh?.cancel()
                }
                if powerState == .standby { sourceName = "TV is off" }
                else if let name = TVPlatform.reportedName(from: value) { sourceName = name }
            }
        case "sent":
            activity = object["label"] as? String ?? "Command sent"
            feedbackWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.activity = "You’re in control" }
            feedbackWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        case "error":
            if object["disconnected"] as? Bool == true { status = "offline" }
            error = object["message"] as? String ?? "The TV didn’t respond."
            isBusy = false
            if status == "connecting" { status = "offline" }
        default: break
        }
    }
    private func keychainQuery(_ host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: activePlatform.keychainService, kSecAttrAccount as String: host]
    }
    private func loadCredentials(_ host: String) throws -> [String: Any]? {
        var query = keychainQuery(host)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status == errSecSuccess ? errSecDecode : status))
        }
        return value
    }
    private func saveCredentials(_ value: [String: Any], host: String) {
        credentialWarning = nil
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        let query = keychainQuery(host)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            if SecItemAdd(add as CFDictionary, nil) != errSecSuccess { credentialWarning = "Paired, but the token could not be saved to Keychain. You may need to pair again next time." }
        } else if status != errSecSuccess { credentialWarning = "Could not update the pairing token in Keychain. You may need to pair again next time." }
        if let credentialWarning { error = credentialWarning }
    }
    private func clearCredentials(_ host: String) -> Bool {
        let result = SecItemDelete(keychainQuery(host) as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }
}
