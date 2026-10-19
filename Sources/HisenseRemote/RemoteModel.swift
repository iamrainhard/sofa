import AppKit
import Combine
import Foundation
import Security
import Network

@MainActor
final class RemoteModel: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
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
    let previewState = Bundle.main.object(forInfoDictionaryKey: "SofaPreviewState") as? String
    func completeSetup() { onboardingComplete = true; defaults.set(true, forKey: "onboardingComplete") }
    func discover() {
        guard previewState == nil, !discovering else { return }
        startBridge()
        guard process != nil else { return }
        discovering = true; discoveredTVs = []; discoveryMessage = "Looking on your local network…"
        send(["action": "discover"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.discovering else { return }
            self.discovering = false; self.discoveryMessage = "No TV found. You can enter its IP address below."
        }
    }
    func forgetTV() {
        guard clearCredentials(host) else { error = "Sofa couldn’t remove the pairing from Keychain. Unlock your login Keychain and try again."; return }
        disconnect(); defaults.removeObject(forKey: "certificate.\(host)")
        host = ""; nickname = ""; deviceName = "Your TV"; defaults.removeObject(forKey: "tvHost")
        onboardingComplete = false; defaults.set(false, forKey: "onboardingComplete"); settingsVisible = false
    }
    @Published var modelName = "Hisense · VIDAA"
    @Published var status = "offline" {
        didSet {
            if status != "ready" {
                hasVolume = false
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
    private let keychainService = "com.rain.luma-remote.vidaa"
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
    init() {
        onboardingComplete = defaults.bool(forKey: "onboardingComplete") || (!host.isEmpty && defaults.bool(forKey: "autoConnect"))
        if let previewState {
            host = "192.168.1.100"; deviceName = "Living Room TV"
            onboardingComplete = previewState == "remote" || previewState == "offline" || previewState == "connecting"
            if previewState == "remote" || previewState == "success" {
                status = "ready"; hasVolume = true; sourceName = "Home"; volumeInteraction.report(24)
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
    func shutdown() { destinationTimeout?.cancel(); destinationRefresh?.cancel(); volumeWork?.cancel(); volumeTimeout?.cancel(); volumeReadback?.cancel(); powerTimeout?.cancel(); powerRefresh?.cancel(); networkCheck?.cancel(); input?.closeFile(); process?.terminate(); reader?.cancel() }
    func send(_ value: [String: Any]) {
        guard let input, let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        do { try input.write(contentsOf: data + Data([10])) }
        catch { self.error = "The local connection stopped. Reconnect to try again."; status = "offline" }
    }
    func connect() {
        guard previewState == nil else { status = "pairing"; return }
        guard let candidate = ConnectionInput.privateIPv4(host) else {
            error = "Enter your TV’s private IPv4 address, such as 192.168.1.100."; return
        }
        networkCheck?.cancel(); networkCheck = nil
        startBridge()
        guard process != nil else { isBusy = false; status = "offline"; return }
        send(["action": "disconnect"])
        host = candidate; localNetworkNeedsAttention = false; pairingNeedsAttention = false; credentialWarning = nil
        error = nil; status = "connecting"; isBusy = true
        let check = NWConnection(host: NWEndpoint.Host(candidate), port: 36669, using: .tcp)
        networkCheck = check
        check.stateUpdateHandler = { [weak self, weak check] state in
            DispatchQueue.main.async {
                guard let self, let check, self.networkCheck === check else { return }
                switch state {
                case .ready:
                    check.cancel(); self.networkCheck = nil
                    guard self.host == candidate else {
                        self.isBusy = false; self.status = "offline"
                        self.error = "The address changed. Choose Connect to use the new address."
                        return
                    }
                    self.connectBridge()
                case .preparing:
                    self.error = nil; self.status = "connecting"; self.isBusy = true
                case .waiting:
                    self.isBusy = false; self.status = "offline"
                    if check.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        self.localNetworkNeedsAttention = true
                        self.error = "Allow Sofa in System Settings → Privacy & Security → Local Network, then Connect again."
                    } else { self.error = "TV not reachable. Make sure it is awake and on the same Wi-Fi." }
                case .failed(let error):
                    self.isBusy = false; self.status = "offline"; self.error = error.localizedDescription
                    check.cancel(); self.networkCheck = nil
                default: break
                }
            }
        }
        check.start(queue: .global(qos: .userInitiated))
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak check] in
            guard let self, let check, self.networkCheck === check else { return }
            if !self.localNetworkNeedsAttention { self.error = "The TV did not respond. Check its IP address and Local Network permission." }
            self.isBusy = false; self.status = "offline"; check.cancel(); self.networkCheck = nil
        }
    }
    private func connectBridge() {
        reconnectWork?.cancel()
        startBridge()
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter your TV’s IP address."; return }
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil; fingerprint = ""; isBusy = true; status = "connecting"
        hasVolume = false; apps = []; sources = []; connectedHost = host
        defaults.set(host, forKey: "tvHost")
        var request: [String: Any] = ["action": "connect", "host": host, "device": deviceID,
                                     "fingerprint": defaults.string(forKey: "certificate.\(host)") ?? ""]
        do {
            if let saved = try loadCredentials(host) { request["saved"] = saved }
        } catch {
            pairingNeedsAttention = true
            self.error = "Sofa couldn’t read its saved pairing. Unlock your login Keychain and allow Sofa when macOS asks, then connect again. If the saved pairing is damaged, use Pair again."
            isBusy = false; status = "offline"; return
        }
        send(["action": "probe", "host": host])
        send(request)
    }
    func trustTV() {
        guard !fingerprint.isEmpty else { return }
        defaults.set(fingerprint, forKey: "certificate.\(host)")
        connect()
    }
    func pair() {
        error = nil; pendingPair = true; pin = ""
        send(["action": "pair"])
    }
    func submitPIN() {
        error = nil
        send(["action": "pin", "pin": pin])
        activity = "Checking pairing code…"
    }
    func repair() {
        guard clearCredentials(host) else { error = "Sofa couldn’t reset the saved pairing. Unlock your login Keychain and try again."; return }
        connect()
    }
    func disconnect() {
        networkCheck?.cancel(); networkCheck = nil
        reconnectWork?.cancel()
        send(["action": "disconnect"]); status = "offline"; hasVolume = false; isBusy = false
        pendingPair = false; pin = ""
        apps = []; sources = []; sourceName = "Your favourite screen."
    }
    func refresh() { error = nil; send(["action": "refresh"]) }
    func key(_ key: String, label: String) {
        guard ready else { settingsVisible = true; return }
        if previewState != nil { activity = "Preview · \(label)"; return }
        send(["action": "key", "key": key, "label": label])
    }
    func beginVolumeEdit() { volumeInteraction.begin() }
    func endVolumeEdit() { volumeInteraction.end(); drainVolume() }
    func setVolume(_ value: Double) {
        guard hasVolume && ready else { return }
        volumeInteraction.propose(value)
        if volumeWork == nil { drainVolume() }
    }
    private func drainVolume() {
        guard ready, let request = volumeInteraction.nextRequest() else { return }
        send(["action": "volume", "value": Int(request.value), "request": request.id])
        volumeTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.volumeInteraction.inFlight?.id == request.id else { return }
            self.volumeInteraction.cancel()
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
    func stepVolume(_ amount: Int) { setVolume(volume + Double(amount)) }
    func toggleMute() { guard hasVolume && ready else { return }; send(["action": "mute", "value": !muted]) }
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
            self.destinationFeedback = "Couldn’t confirm \(item.name). Try again."
        }
        destinationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }
    func receive(_ object: [String: Any]) {
        switch object["event"] as? String {
        case "discovery":
            discovering = false
            discoveredTVs = (object["devices"] as? [[String: String]] ?? []).compactMap { value in
                guard let host = value["host"] else { return nil }
                return DiscoveredTV(host: host, name: value["name"] ?? "VIDAA TV", model: value["model"] ?? "")
            }
            discoveryMessage = discoveredTVs.isEmpty ? "No TV found. Enter its IP address below." : "Choose your TV to connect."
        case "device":
            if let name = object["name"] as? String, !name.isEmpty { deviceName = name }
            if let name = object["model"] as? String, !name.isEmpty { modelName = "Hisense · \(name)" }
        case "volume":
            if let value = object["value"] as? Int {
                if object["source"] as? String == "readback" || Date() >= ignoreVolumeBroadcastsUntil {
                    volumeInteraction.report(Double(value))
                }
                hasVolume = true
            }
            if let value = object["muted"] as? Bool { muted = value }
        case "volume_result": volumeCompleted(object)
        case "mute": muted = object["value"] as? Bool ?? false
        case "status":
            // The disconnect acknowledgement belongs to the previous session, not the native permission/reachability check.
            if networkCheck != nil, object["value"] as? String == "offline" { return }
            status = object["value"] as? String ?? "offline"
            isBusy = status == "connecting"
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
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: host]
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

struct DiscoveredTV: Identifiable { var id: String { host }; let host: String; let name: String; let model: String }
