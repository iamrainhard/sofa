import Foundation

@main
struct PowerStateChecks {
    static func main() {
        let cases: [([String: Any], TVPowerState)] = [
            (["statetype":"fake_sleep_0", "appname":"YouTube"], .standby),
            (["statetype":"fake_sleep_1", "appname":"YouTube"], .unknown),
            (["statetype":"remote_launcher"], .on),
            (["statetype":"sourceswitch", "sourcename":"HDMI1"], .on),
            (["statetype":"livetv"], .on),
            (["statetype":"remote_setting"], .on),
            (["statetype":"app", "appname":"YouTube"], .on),
            (["appname":"YouTube"], .on),
            (["statetype":"authentication", "appname":"YouTube"], .unknown),
            (["statetype":"unrecognized"], .unknown),
            ([:], .unknown)
        ]
        for (input, expected) in cases { precondition(TVPowerState.reported(by: input) == expected) }
        print("11 power-state cases passed")
    }
}
