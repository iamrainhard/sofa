import Foundation

/// VIDAA YouTube's dedicated media keys are inconsistent on the tested TV;
/// directional seeking works in both directions while its player has focus.
enum TVPlaybackControl {
    static func seekKey(forward: Bool, appName: String, platform: TVConnectionPlatform) -> String {
        let app = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if platform == .vidaa && app == "youtube" {
            return forward ? "RIGHT" : "LEFT"
        }
        return forward ? "FORWARDS" : "BACK"
    }
}
