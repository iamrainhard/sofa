import Foundation

/// Power is reported by the TV, never inferred from a network connection.
enum TVPowerState: String {
    case unknown, on, standby

    var title: String {
        switch self {
        case .on: return "On"
        case .standby: return "Off"
        case .unknown: return "?"
        }
    }

    static func reported(by state: [String: Any]) -> TVPowerState {
        let kind = (state["statetype"] as? String ?? "").lowercased()
        if kind == "android_state" || kind == "samsung_state" { return (state["power"] as? Bool).map { $0 ? .on : .standby } ?? .unknown }
        if kind == "fake_sleep_0" { return .standby }
        // Only recognized active-screen states are evidence that the panel is on.
        if ["remote_launcher", "app", "source", "livetv", "tv", "sourceswitch", "remote_setting"].contains(kind) { return .on }
        if !kind.hasPrefix("fake_sleep"), !kind.hasPrefix("authentication"),
           let app = state["appname"] as? String, !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .on }
        return .unknown
    }
}
