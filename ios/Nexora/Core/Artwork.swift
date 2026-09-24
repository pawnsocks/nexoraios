import ImageIO
import SwiftUI
import UIKit

actor ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession
    init() {
        cache.totalCostLimit = 24 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 40 * 1024 * 1024, directory: nil)
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }
    func image(_ url: URL) async throws -> UIImage {
        if let image = cache.object(forKey: url as NSURL) { return image }
        let (data, response) = try await session.data(from: url)
        guard data.count <= 10_000_000, (response as? HTTPURLResponse)?.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw APIError.message("Artwork unavailable") }
        let result = UIImage(cgImage: image)
        cache.setObject(result, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        return result
    }
    func clear() { cache.removeAllObjects(); session.configuration.urlCache?.removeAllCachedResponses() }
}
struct Artwork: View {
    let url: String?
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color.white.opacity(0.05)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "film").foregroundStyle(.white.opacity(0.15)) }
        }
        .clipped()
        .task(id: url) {
            image = nil
            guard let url, let parsed = URL(string: url), parsed.scheme == "https" else { return }
            let loaded = try? await ArtworkCache.shared.image(parsed)
            if !Task.isCancelled { image = loaded }
        }
    }
}
