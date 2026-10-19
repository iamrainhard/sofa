import Foundation
import Darwin

/// Bonjour discovery is native so macOS can present Local Network permission.
/// Resolve advertised Android TV services only; never sweep a network subnet.
@MainActor
final class TVDiscovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var found: ((DiscoveredTV) -> Void)?
    private var failed: (() -> Void)?

    func start(found: @escaping (DiscoveredTV) -> Void, failed: @escaping () -> Void) {
        stop()
        self.found = found; self.failed = failed
        let browser = NetServiceBrowser()
        self.browser = browser
        browser.delegate = self
        browser.searchForServices(ofType: "_androidtvremote2._tcp.", inDomain: "local.")
    }
    func stop() {
        browser?.stop(); browser?.delegate = nil; browser = nil
        services.forEach { $0.stop(); $0.delegate = nil }
        services = []; found = nil; failed = nil
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard browser === self.browser, services.count < 32 else { return }
        services.append(service); service.delegate = self; service.resolve(withTimeout: 3)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browser === self.browser else { return }
        failed?()
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard services.contains(where: { $0 === sender }), sender.port == 6466 else { return }
        for data in sender.addresses ?? [] {
            guard data.count >= MemoryLayout<sockaddr_in>.size else { continue }
            var address = sockaddr_in()
            _ = withUnsafeMutableBytes(of: &address) { data.copyBytes(to: $0) }
            guard address.sin_family == AF_INET else { continue }
            var ip = address.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &ip, &buffer, socklen_t(buffer.count)) != nil,
                  let host = ConnectionInput.privateIPv4(String(cString: buffer)) else { continue }
            found?(DiscoveredTV(host: host, name: sender.name, model: "Google / Android TV", platform: .androidtv))
            break
        }
    }
}
