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
        print("Connection input checks passed")
    }
}
