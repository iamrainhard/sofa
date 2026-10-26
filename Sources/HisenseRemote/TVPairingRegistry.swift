import Foundation

/// No secrets here. credentialAccount points at the original Keychain item, so
/// upgrading does not copy, delete, or expose existing pairing credentials.
struct TVPairingRecord: Codable, Equatable {
    var id: String
    var platform: String
    var credentialAccount: String
    var lastHost: String
    var identities: [String]
    var fingerprint: String
}

struct TVPairingRegistry: Codable {
    var records: [TVPairingRecord] = []
    func record(id: String?) -> TVPairingRecord? { records.first { $0.id == id } }
    func matches(_ candidate: DiscoveredTV, record: TVPairingRecord) -> Bool {
        candidate.platform.rawValue == record.platform && !candidate.identity.isEmpty &&
        record.identities.contains(candidate.identity) && Self.validFingerprint(candidate.fingerprint) &&
        candidate.fingerprint.lowercased() == record.fingerprint.lowercased()
    }
    func uniqueMatch(_ candidate: DiscoveredTV) -> TVPairingRecord? {
        let found = records.filter { matches(candidate, record: $0) }
        return found.count == 1 ? found.first : nil
    }
    func recoveryCandidate(for id: String, candidates: [DiscoveredTV]) -> DiscoveredTV? {
        guard let record = record(id: id) else { return nil }
        let found = candidates.filter { matches($0, record: record) }
        // Multiple addresses for the same device are OK only if one is its
        // last verified address; otherwise require explicit selection.
        let hosts = Set(found.map(\.host))
        if hosts.count == 1 { return found.first }
        return found.first { $0.host == record.lastHost }
    }
    static func validFingerprint(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
    mutating func remember(host: String, platform: TVConnectionPlatform, fingerprint: String, credentialAccount: String, id: String?) -> String? {
        guard platform != .automatic, Self.validFingerprint(fingerprint) else { return nil }
        if let index = records.firstIndex(where: { $0.id == id && $0.platform == platform.rawValue }) {
            // A newly approved certificate must not retain old discovery bindings.
            if records[index].fingerprint.lowercased() != fingerprint.lowercased() { records[index].identities = [] }
            records[index].fingerprint = fingerprint.lowercased(); records[index].lastHost = host
            return records[index].id
        }
        let newID = UUID().uuidString
        records.append(TVPairingRecord(id: newID, platform: platform.rawValue, credentialAccount: credentialAccount,
                                      lastHost: host, identities: [], fingerprint: fingerprint.lowercased()))
        return newID
    }
    mutating func bind(_ candidate: DiscoveredTV, to id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }),
              records[index].lastHost == candidate.host, records[index].platform == candidate.platform.rawValue,
              Self.validFingerprint(candidate.fingerprint), records[index].fingerprint == candidate.fingerprint.lowercased(),
              !candidate.identity.isEmpty, candidate.identity.count <= 512 else { return }
        if !records[index].identities.contains(candidate.identity), records[index].identities.count < 8 {
            records[index].identities.append(candidate.identity)
        }
    }
}
