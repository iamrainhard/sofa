import Foundation
import Darwin

/// Bonjour is native so macOS can present Local Network permission. Cast and
/// AirPlay only supply candidates; the helper verifies the remote service.
@MainActor
final class TVDiscovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private var found: ((DiscoveredTV) -> Void)?
    private var failed: (() -> Void)?
    static let serviceTypes = ["_androidtvremote2._tcp.", "_googlecast._tcp.", "_airplay._tcp.", "_samsungmsf._tcp."]

    static func interfaces() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var result: Set<String> = []
        var cursor = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_MULTICAST != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == AF_INET else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0,
               let ip = ConnectionInput.privateIPv4(String(cString: buffer)) { result.insert(ip) }
        }
        return result.sorted()
    }
    func start(found: @escaping (DiscoveredTV) -> Void, failed: @escaping () -> Void) {
        stop(); self.found = found; self.failed = failed
        for type in Self.serviceTypes {
            let browser = NetServiceBrowser(); browsers.append(browser)
            browser.delegate = self; browser.searchForServices(ofType: type, inDomain: "local.")
        }
    }
    func stop() {
        browsers.forEach { $0.stop(); $0.delegate = nil }; browsers = []
        services.forEach { $0.stop(); $0.delegate = nil }; services = []
        found = nil; failed = nil
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard browsers.contains(where: { $0 === browser }), services.count < 64,
              !services.contains(where: { $0.name == service.name && $0.type == service.type && $0.domain == service.domain }) else { return }
        services.append(service); service.delegate = self; service.resolve(withTimeout: 4)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browsers.contains(where: { $0 === browser }) else { return }
        failed?()
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard services.contains(where: { $0 === sender }) else { return }
        let type = sender.type
        if type == "_androidtvremote2._tcp.", sender.port != 6466 { return }
        let platform: TVConnectionPlatform = type == "_airplay._tcp." ? .vidaa : type == "_samsungmsf._tcp." ? .samsung : .androidtv
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let castID = txt["id"].flatMap { String(data: $0, encoding: .utf8) }
        let airplayID = txt["deviceid"].flatMap { String(data: $0, encoding: .utf8) }
        let identity = type == "_airplay._tcp." ? airplayID.map { "airplay:" + $0.lowercased() } ?? "" : type == "_googlecast._tcp." ? castID.map { "cast:" + $0 } ?? "" : "bonjour:\(sender.name).\(type)\(sender.domain)"
        for data in sender.addresses ?? [] {
            guard data.count >= MemoryLayout<sockaddr_in>.size else { continue }
            var address = sockaddr_in()
            _ = withUnsafeMutableBytes(of: &address) { data.copyBytes(to: $0) }
            guard address.sin_family == AF_INET else { continue }
            var ip = address.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &ip, &buffer, socklen_t(buffer.count)) != nil,
                  let host = ConnectionInput.privateIPv4(String(cString: buffer)) else { continue }
            found?(DiscoveredTV(host: host, name: sender.name, model: platform.title, platform: platform, identity: identity))
        }
    }
}
