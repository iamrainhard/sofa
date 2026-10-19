import Foundation

@main struct AdapterModelChecks {
    @MainActor static func main() {
        let android = RemoteModel(previewState: "android-home")
        precondition(android.ready && android.canStepVolume && android.canSetVolume)
        android.receive(["event": "status", "value": "offline", "session": "old-tv-session"])
        precondition(android.ready, "Stale adapter callbacks cannot change the current connection")
        precondition(android.platformTitle == "Google / Android TV")
        precondition(!android.activePlatform.hasInstalledAppCatalog)
        android.receive(["event": "state", "value": ["statetype": "android_state", "power": false, "appname": "Netflix"]])
        precondition(android.powerState == .standby && android.activeDestination == nil)
        android.receive(["event": "state", "value": ["statetype": "android_state", "power": true, "appname": "YouTube"]])
        precondition(android.powerState == .on && android.activeDestination?.name == "YouTube")
        precondition(TVPowerState.reported(by: ["statetype": "android_state", "appname": "Netflix"]) == .unknown)
        android.receive(["event": "volume_control_unavailable"])
        precondition(!android.canSetVolume && android.canStepVolume)
        android.receive(["event": "status", "value": "offline"])
        precondition(!android.hasVolume && !android.canStepVolume && android.powerState == .unknown)
        precondition(android.activeDestination == nil)
        android.receive(["event": "status", "value": "pairing"])
        precondition(android.settingsVisible && android.pendingPair && !android.isBusy)
        android.pin = "AB12CD"
        precondition(android.validPIN)
        let vidaa = RemoteModel(previewState: "remote")
        precondition(vidaa.ready && vidaa.canSetVolume && vidaa.canStepVolume)
        vidaa.pin = "1234"
        precondition(vidaa.validPIN)
        vidaa.receive(["event": "state", "value": ["statetype": "remote_launcher"]])
        precondition(vidaa.powerState == .on && vidaa.sourceName == "VIDAA Home")
        vidaa.receive(["event": "state", "value": ["statetype": "fake_sleep_0"]])
        precondition(vidaa.powerState == .standby)
        vidaa.disconnect()
        precondition(!vidaa.hasVolume && !vidaa.canSetVolume && vidaa.apps.isEmpty)
        print("Adapter UI state checks passed (VIDAA and Android)")
    }
}
