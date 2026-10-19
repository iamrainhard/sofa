import Foundation

enum ConnectionInput {
    static func privateIPv4(_ raw: String) -> String? {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let bytes = parts.compactMap { UInt8($0) }
        guard bytes.count == 4,
              bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) || (bytes[0] == 192 && bytes[1] == 168) else { return nil }
        return bytes.map(String.init).joined(separator: ".")
    }

    static func pairingCode(_ raw: String) -> String {
        String(raw.filter { $0.isASCII && $0.isNumber }.prefix(8))
    }
}
