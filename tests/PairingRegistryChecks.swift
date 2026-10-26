import Foundation

@main struct PairingRegistryChecks {
    static func main() throws {
        let pin = String(repeating: "a", count: 64)
        for platform in [TVConnectionPlatform.vidaa, .androidtv, .samsung] {
            var registry = TVPairingRegistry()
            let id = registry.remember(host: "192.168.1.33", platform: platform, fingerprint: pin,
                                       credentialAccount: "192.168.1.33", id: nil)!
            var old = DiscoveredTV(host: "192.168.1.33", name: "TV", model: "Same model", platform: platform,
                                   identity: "device:one", fingerprint: pin)
            registry.bind(old, to: id)
            var moved = old; moved = DiscoveredTV(host: "192.168.1.2", name: "Renamed TV", model: old.model,
                platform: platform, identity: old.identity, fingerprint: pin.uppercased())
            let match = registry.uniqueMatch(moved)!
            precondition(match.id == id && match.credentialAccount == "192.168.1.33", "DHCP must preserve the original Keychain account")
            precondition(registry.recoveryCandidate(for: id, candidates: [moved])?.host == "192.168.1.2")
            var wrong = moved; wrong.identity = "device:other"
            precondition(registry.uniqueMatch(wrong) == nil, "A shared certificate cannot identify a different TV")
            wrong = moved; wrong.fingerprint = String(repeating: "b", count: 64)
            precondition(registry.uniqueMatch(wrong) == nil, "An advertised identity cannot bypass a changed certificate")
            wrong = moved; wrong.platform = .automatic
            precondition(registry.uniqueMatch(wrong) == nil, "Never cross platform credential namespaces")
            wrong = moved; wrong.identity = ""
            precondition(registry.uniqueMatch(wrong) == nil, "No name or IP-only auto-pairing")
            wrong = moved; wrong.fingerprint = ""
            precondition(registry.uniqueMatch(wrong) == nil)
            var duplicate = moved; duplicate = DiscoveredTV(host: "192.168.1.5", name: "TV", model: "", platform: platform, identity: moved.identity, fingerprint: pin)
            precondition(registry.recoveryCandidate(for: id, candidates: [moved, duplicate]) == nil, "Ambiguous rediscovery must not choose arbitrarily")
            registry.bind(duplicate, to: id)
            precondition(registry.records[0].lastHost == "192.168.1.33", "Unauthenticated discovery cannot change a saved endpoint")
            _ = registry.remember(host: moved.host, platform: platform, fingerprint: pin, credentialAccount: match.credentialAccount, id: id)
            precondition(registry.records.count == 1 && registry.records[0].lastHost == moved.host)
            let saved = try JSONEncoder().encode(registry)
            registry = try JSONDecoder().decode(TVPairingRegistry.self, from: saved)
            precondition(registry.uniqueMatch(moved)?.credentialAccount == "192.168.1.33")
            _ = registry.remember(host: moved.host, platform: platform, fingerprint: String(repeating: "c", count: 64), credentialAccount: match.credentialAccount, id: id)
            precondition(registry.records[0].identities.isEmpty, "Certificate replacement requires identity relearning")
            old.fingerprint = "bad"
            registry.bind(old, to: id)
            precondition(registry.records[0].identities.isEmpty)
        }
        print("Pairing identity migration, DHCP recovery, persistence and trust-boundary checks passed for all three platforms")
    }
}
