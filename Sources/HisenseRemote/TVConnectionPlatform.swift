import Foundation

/// Connection protocol, distinct from TVPlatform's app artwork/branding.
enum TVConnectionPlatform: String, CaseIterable, Identifiable {
    case automatic, vidaa, androidtv
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Detect automatically"
        case .vidaa: return "Hisense VIDAA"
        case .androidtv: return "Google / Android TV"
        }
    }
    var port: UInt16 { self == .androidtv ? 6466 : 36669 }
    var supportsAbsoluteVolume: Bool { self == .vidaa }
    var hasInputCatalog: Bool { self == .vidaa }
    var hasInstalledAppCatalog: Bool { self == .vidaa }
    var keychainService: String {
        // Preserve the exact legacy VIDAA service/account so upgrades don't re-pair.
        self == .androidtv ? "com.rain.sofa.androidtv" : "com.rain.luma-remote.vidaa"
    }
    func certificateKey(host: String) -> String {
        self == .androidtv ? "certificate.androidtv.\(host)" : "certificate.\(host)"
    }
    func pairingCode(_ raw: String) -> String {
        if self != .androidtv { return ConnectionInput.pairingCode(raw) }
        return String(raw.uppercased().filter { $0.isASCII && $0.isHexDigit }.prefix(6))
    }
    func validPairingCode(_ raw: String) -> Bool {
        if self == .androidtv { return raw.count == 6 && raw.allSatisfy { $0.isASCII && $0.isHexDigit } }
        return (4...8).contains(raw.count) && raw.allSatisfy { $0.isASCII && $0.isNumber }
    }
    func supportsKey(_ key: String) -> Bool { self != .androidtv || key != "EXIT" }
}

struct DiscoveredTV: Identifiable {
    var id: String { "\(platform.rawValue):\(host)" }
    let host: String
    let name: String
    let model: String
    var platform: TVConnectionPlatform = .vidaa
}
