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
        for platform in [TVConnectionPlatform.vidaa, .androidtv] {
            for app in ["YouTube", "Netflix", "Prime Video", "Apple TV", "An unknown app"] {
                precondition(TVPlaybackControl.seekKey(forward: false, appName: app, platform: platform, mode: .directionalKeys) == "LEFT")
                precondition(TVPlaybackControl.seekKey(forward: true, appName: app, platform: platform, mode: .directionalKeys) == "RIGHT")
                precondition(TVPlaybackControl.seekKey(forward: false, appName: app, platform: platform, mode: .mediaKeys) == "BACK")
                precondition(TVPlaybackControl.seekKey(forward: true, appName: app, platform: platform, mode: .mediaKeys) == "FORWARDS")
            }
        }
        let key = TVPlaybackControl.preferenceKey(platform: .vidaa, host: "192.168.1.2", destination: "app:netflix")
        precondition(key != TVPlaybackControl.preferenceKey(platform: .androidtv, host: "192.168.1.2", destination: "app:netflix"))
        precondition(key != TVPlaybackControl.preferenceKey(platform: .vidaa, host: "192.168.1.3", destination: "app:netflix"))
        precondition(key != TVPlaybackControl.preferenceKey(platform: .vidaa, host: "192.168.1.2", destination: "app:youtube"))
        print("Playback routing checks passed: VIDAA YouTube and unchanged other apps/platforms")
    }
}
