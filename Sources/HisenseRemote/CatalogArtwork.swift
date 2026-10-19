import AppKit
import CryptoKit
import SwiftUI

/// Only the public VIDAA artwork service is fetched; TV-supplied URLs cannot target the LAN.
private final class ArtworkRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(ArtworkURL.parse(request.url?.absoluteString) == nil ? nil : request)
    }
}
@MainActor final class ArtworkCache: ObservableObject {
    static let shared = ArtworkCache()
    @Published private var images: [URL: NSImage] = [:]
    private var pending = Set<URL>()
    private let policy = ArtworkRedirectPolicy()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpMaximumConnectionsPerHost = 4; config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config, delegate: policy, delegateQueue: nil)
    }()
    func image(for url: URL?) -> NSImage? { url.flatMap { images[$0] } }
    func load(_ url: URL?) async {
        guard let url, ArtworkURL.parse(url.absoluteString) != nil, images[url] == nil, !pending.contains(url) else { return }
        pending.insert(url); defer { pending.remove(url) }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.rain.sofa/artwork")
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = root.appendingPathComponent(name)
        if let data = try? Data(contentsOf: file), let image = decode(data) { images[url] = image; return }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.expectedContentLength <= 2_000_000 else { return }
            var data = Data()
            for try await byte in bytes { guard data.count < 2_000_000 else { return }; data.append(byte) }
            guard let image = decode(data) else { return }
            images[url] = image
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        } catch { /* Artwork is optional; the app name remains available offline. */ }
    }
    private func decode(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 2048, height <= 2048 else { return nil }
        return NSImage(data: data)
    }
}
struct CatalogArtwork: View {
    let url: URL?
    var symbol = "app.dashed"
    @ObservedObject private var cache = ArtworkCache.shared
    var body: some View {
        Group {
            if let image = cache.image(for: url) { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: symbol).font(.system(size: 29, weight: .light)).foregroundStyle(.white.opacity(0.8)) }
        }.task(id: url) { await cache.load(url) }
    }
}
