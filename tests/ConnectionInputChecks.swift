import Foundation

@main struct ConnectionInputChecks {
    static func main() {
        for valid in ["10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.1.100"] {
            precondition(ConnectionInput.privateIPv4(valid) == valid)
        }
        precondition(ConnectionInput.privateIPv4(" 192.168.001.100\n") == "192.168.1.100")
        for invalid in ["192.168.1.1.foo", "foo.192.168.1.1", "192.168..1.1", "192.168.1.256", "192.168.1.-1", "192.168.1.+1", "172.15.1.1", "172.32.1.1", "8.8.8.8", "127.0.0.1", "", "http://192.168.1.1"] {
            precondition(ConnectionInput.privateIPv4(invalid) == nil, "Reject malformed/public address: \(invalid)")
        }
        precondition(ConnectionInput.pairingCode("12 34-56") == "123456")
        precondition(ConnectionInput.pairingCode("１２٣٤56") == "56")
        precondition(ConnectionInput.pairingCode("123456789") == "12345678")
        let android = TVConnectionPlatform.androidtv
        precondition(android.pairingCode("aB 12-cD") == "AB12CD")
        precondition(android.validPairingCode("AB12CD"))
        for invalid in ["1234", "ABCDEF0", "GH1234", "１２３４５６"] {
            precondition(!android.validPairingCode(invalid))
        }
        precondition(TVConnectionPlatform.vidaa.validPairingCode("12345678"))
        precondition(!TVConnectionPlatform.vidaa.validPairingCode("AB1234"))
        precondition(TVConnectionPlatform.vidaa.keychainService == "com.rain.luma-remote.vidaa")
        precondition(TVConnectionPlatform.vidaa.certificateKey(host: "192.168.1.9") == "certificate.192.168.1.9")
        precondition(android.keychainService != TVConnectionPlatform.vidaa.keychainService)
        precondition(!android.supportsAbsoluteVolume && TVConnectionPlatform.vidaa.supportsAbsoluteVolume)
        print("Connection input checks passed")
    }
}
