import Foundation

enum TVSeekingMode: String, CaseIterable, Identifiable {
    case automatic, mediaKeys, directionalKeys
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .mediaKeys: return "Media buttons"
        case .directionalKeys: return "Left / right arrows"
        }
    }
}

/// Choose one command path per press; never send both and risk a double seek.
/// VIDAA YouTube's directional fallback is verified on the connected TV. Other
/// apps keep native media keys unless the user selects their compatibility mode.
enum TVPlaybackControl {
    static func seekKey(forward: Bool, appName: String, platform: TVConnectionPlatform,
                        mode: TVSeekingMode = .automatic) -> String {
        let app = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let arrows = mode == .directionalKeys || (mode == .automatic && platform == .vidaa && app == "youtube")
        return arrows ? (forward ? "RIGHT" : "LEFT") : (forward ? "FORWARDS" : "BACK")
    }

    /// Length prefixes keep app names from colliding with another TV's keys.
    static func preferenceKey(platform: TVConnectionPlatform, host: String, destination: String) -> String {
        [platform.rawValue, host, destination].map { "\($0.utf8.count):\($0)" }.joined()
    }
}
