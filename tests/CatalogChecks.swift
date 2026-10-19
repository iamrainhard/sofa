import Foundation

@main struct CatalogChecks {
    static func main() {
        let rows: [[String: Any]] = [["appId": "yt", "name": "YouTube"], ["appid": 42, "name": "Prime Video"], ["name": "Unknown App"]]
        let apps = TVItem.parse(rows, keys: ["name"], kind: .app)
        precondition(apps.map(\.id) == [0, 1, 2], "Original bridge indices must survive display mapping")
        let reordered = TVItem.parse(Array(rows.reversed()), keys: ["name"], kind: .app)
        precondition(apps[0].stableID == reordered[2].stableID, "Refresh must preserve identity when catalog order changes")
        precondition(reordered[2].id == 2, "Command index must follow current catalog")
        let duplicate = TVItem.parse([["name": "Duplicate"], ["name": "Duplicate"]], keys: ["name"], kind: .app)
        precondition(Set(duplicate.map(\.stableID)).count == 2)
        let input = TVItem.parse([["sourceid": 3, "sourcename": "HDMI1"]], keys: ["sourcename"], kind: .input)[0]
        precondition(TVDestination.reported(by: ["statetype": "sourceswitch", "sourcename": "HDMI 1", "appname": "YouTube"])?.matches(input) == true)
        precondition(TVDestination.reported(by: ["statetype": "app", "appname": "YouTube"])?.matches(apps[0]) == true)
        precondition(TVDestination.reported(by: ["statetype": "app", "appname": "Amazon"])?.matches(apps[1]) == true)
        precondition(TVDestination.reported(by: ["statetype": "remote_launcher", "appname": "YouTube"]) == nil)
        precondition(TVDestination.reported(by: ["statetype": "fake_sleep_0", "appname": "YouTube"]) == nil)
        precondition(TVDestination.reported(by: ["statetype": "fake_sleep_1", "appname": "YouTube"]) == nil)
        precondition(TVDestination(kind: .input, name: "YouTube").matches(apps[0]) == false)
        precondition(TVDestination(kind: .input, name: "TV").matches(TVItem(id: 0, name: "TV Channels▶")) == false, "TV Channels is an app, not automatically a tuner alias")
        precondition(TVItem.parse(nil, keys: ["name"], kind: .app).isEmpty)
        precondition(TVDestination.reported(by: ["statetype": "app", "name": "YouTube"])?.matches(apps[0]) == true)
        precondition(TVDestination.reported(by: ["statetype": "source", "name": "HDMI 1"])?.matches(input) == true)
        precondition(TVDestination.reported(by: ["statetype": "source"]) == nil)
        precondition(ArtworkURL.parse("data:image/png;base64,iconDownloadhttps://img.vidaahub.com/icon.png")?.host == "img.vidaahub.com")
        for value in ["http://img.vidaahub.com/a", "https://192.168.1.1/a", "https://img.vidaahub.com.evil.test/a", "https://user:pass@img.vidaahub.com/a", "https://img.vidaahub.com:8080/a", "file:///etc/passwd"] { precondition(ArtworkURL.parse(value) == nil) }
        print("23 catalog identity and destination checks passed")
    }
}
