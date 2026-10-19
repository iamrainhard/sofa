import Foundation

@main struct PlaybackControlChecks {
    static func main() {
        precondition(TVPlaybackControl.seekKey(forward: false, appName: "YouTube", platform: .vidaa) == "LEFT")
        precondition(TVPlaybackControl.seekKey(forward: true, appName: " YOUTUBE ", platform: .vidaa) == "RIGHT")
        for app in ["Netflix", "Prime Video", "YouTube TV", "Live TV", ""] {
            precondition(TVPlaybackControl.seekKey(forward: false, appName: app, platform: .vidaa) == "BACK")
            precondition(TVPlaybackControl.seekKey(forward: true, appName: app, platform: .vidaa) == "FORWARDS")
        }
        precondition(TVPlaybackControl.seekKey(forward: false, appName: "YouTube", platform: .androidtv) == "BACK")
        precondition(TVPlaybackControl.seekKey(forward: true, appName: "YouTube", platform: .androidtv) == "FORWARDS")
        print("Playback routing checks passed: VIDAA YouTube and unchanged other apps/platforms")
    }
}
