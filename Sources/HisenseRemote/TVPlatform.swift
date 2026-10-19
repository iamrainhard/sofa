import SwiftUI

struct TVPlatform {
    let name: String
    let artwork: String?
    let background: Color
    let accent: Color
    let symbol: String
    let logoWidth: CGFloat

    init(reportedName: String, connected: Bool) {
        let raw = reportedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        var name = raw.isEmpty || raw == "Your favourite screen." ? "Connected TV" : raw
        var artwork: String?
        var background = Color(red: 0.055, green: 0.06, blue: 0.07)
        var accent = Color.white
        var symbol = "app"
        var width: CGFloat = 140

        if !connected {
            name = "Your TV, within reach"
            symbol = "tv"
        } else {
            switch key {
            case "youtube", "comgoogleandroidyoutubetv":
                name = "YouTube"; artwork = "youtube.png"; width = 184
                background = Color(white: 0.059); accent = Color(red: 1, green: 0, blue: 0.2)
            case "netflix", "netflixtv":
                name = "Netflix"; artwork = "netflix.png"; width = 116
                background = .black; accent = Color(red: 0.9, green: 0.035, blue: 0.08)
            case "primevideo", "amazon", "amazonvideo", "amazonprime", "amazonprimevideo":
                name = "Prime Video"; artwork = "prime-video.png"; width = 133
                background = Color(red: 0, green: 0.075, blue: 0.15)
                accent = Color(red: 0.1, green: 0.65, blue: 1)
            case "appletv", "appletvplus":
                name = "Apple TV"; artwork = "apple-tv.jpg"; width = 224
                background = .black
            case "vidaa", "vidaahome", "remotelauncher", "launcher":
                name = "VIDAA Home"; artwork = "vidaa.png"; width = 126
                background = Color(white: 0.035)
                accent = Color(red: 1, green: 0.886, blue: 0)
            case "googletvhome", "androidtvhome":
                name = raw; symbol = "house"
            case "tv", "livetv", "dtv", "atv":
                name = "Live TV"; symbol = "antenna.radiowaves.left.and.right"
            case "tvchannels":
                name = "TV Channels"; symbol = "play.tv"
            default:
                if key.hasPrefix("hdmi"), let number = Int(key.dropFirst(4)) {
                    name = "HDMI \(number)"; symbol = "cable.connector"
                } else if key == "av" {
                    name = "AV"; symbol = "cable.connector"
                }
            }
        }
        self.name = name; self.artwork = artwork; self.background = background
        self.accent = accent; self.symbol = symbol; self.logoWidth = width
    }

    static func reportedName(from state: [String: Any]) -> String? {
        // A launcher state can carry the old app name. Home takes precedence.
        if state["statetype"] as? String == "remote_launcher" { return "VIDAA Home" }
        return ["appname", "sourcename", "name"].compactMap { state[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
