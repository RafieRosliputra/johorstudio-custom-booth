import Combine
import CoreGraphics
import Foundation

/// Filmstrip thumbnails: decoded off the main thread, cached by path.
@MainActor
final class ThumbnailStore: ObservableObject {
    /// Paths that finished decoding — the published bit that redraws the strip.
    @Published private(set) var loaded: Set<String> = []

    private let cache = NSCache<NSString, CGImage>()
    private var loading = Set<String>()
    private let queue = DispatchQueue(
        label: "johorbooth.thumbnails",
        qos: .userInitiated,
        attributes: .concurrent
    )

    init() {
        cache.countLimit = 500
    }

    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url.path as NSString)
    }

    func load(_ url: URL) {
        let key = url.path
        guard cache.object(forKey: key as NSString) == nil, !loading.contains(key) else { return }
        loading.insert(key)
        queue.async {
            let image = ImageDecode.downsampled(url, maxPixel: ImageDecode.thumbnailPixel)
            Task { @MainActor in
                self.loading.remove(key)
                guard let image else { return }
                self.cache.setObject(image, forKey: key as NSString)
                self.loaded.insert(key)
            }
        }
    }
}
