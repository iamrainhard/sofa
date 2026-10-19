import Foundation

enum TVDestinationKind: String { case app, input }

struct TVItem: Identifiable {
    // VIDAA commands take the original array index. Never substitute a display order.
    let id: Int
    let name: String
    var kind: TVDestinationKind = .app
    var catalogID: String? = nil
    var artworkURL: URL? = nil
    var stableID: String { "\(kind.rawValue):\(catalogID ?? name)" }
    var destination: TVDestination { TVDestination(kind: kind, name: name) }

    static func parse(_ value: Any?, keys: [String], kind: TVDestinationKind) -> [TVItem] {
        guard let list = value as? [[String: Any]] else { return [] }
        var occurrences: [String: Int] = [:]
        return list.enumerated().map { index, item in
            let name = keys.compactMap { item[$0] as? String }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "Item \(index + 1)"
            let idKeys = kind == .app ? ["appId", "appid", "app_id", "id"] : ["sourceid", "sourceId", "id"]
            let identifier = idKeys.compactMap { key -> String? in
                if let string = item[key] as? String { return string }
                if let number = item[key] as? NSNumber { return number.stringValue }
                return nil
            }.first
            let base = identifier ?? name
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return TVItem(id: index, name: name, kind: kind, catalogID: occurrence == 0 ? base : "\(base)#\(occurrence)", artworkURL: ArtworkURL.parse(item["httpIcon"] as? String))
        }
    }
}

struct TVDestination: Equatable {
    let kind: TVDestinationKind
    let name: String
    var key: String { "\(kind.rawValue):\(Self.canonical(name))" }
    func matches(_ item: TVItem) -> Bool { key == item.destination.key }

    static func canonical(_ name: String) -> String {
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "amazon", "amazonvideo", "amazonprime", "amazonprimevideo", "primevideo": return "primevideo"
        case "netflixtv": return "netflix"
        case "comgoogleandroidyoutubetv": return "youtube"
        case "appletvplus": return "appletv"
        case "tv", "livetv", "dtv", "atv": return "livetv"
        default: return key
        }
    }
    static func reported(by state: [String: Any]) -> TVDestination? {
        let type = state["statetype"] as? String ?? ""
        if ["remote_launcher", "remote_setting", "fake_sleep_0", "fake_sleep_1", "authentication"].contains(type) { return nil }
        if ["source", "sourceswitch", "livetv", "tv"].contains(type) {
            let name = state["sourcename"] as? String ?? state["name"] as? String ?? (["livetv", "tv"].contains(type) ? "TV" : "")
            return name.isEmpty ? nil : TVDestination(kind: .input, name: name)
        }
        if let name = state["appname"] as? String, !name.isEmpty { return TVDestination(kind: .app, name: name) }
        if type == "app", let name = state["name"] as? String, !name.isEmpty { return TVDestination(kind: .app, name: name) }
        if let name = state["sourcename"] as? String, !name.isEmpty { return TVDestination(kind: .input, name: name) }
        return nil
    }
}

enum ArtworkURL {
    static func parse(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let candidate = raw.components(separatedBy: "iconDownload").last ?? raw
        guard let url = URL(string: candidate), url.scheme == "https", url.host?.lowercased() == "img.vidaahub.com",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        return url
    }
}
