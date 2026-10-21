import Combine
import CoreGraphics
import Foundation

/// Filmstrip thumbnails: decoded off the main thread, cached by path.
@MainActor
final class ThumbnailStore: ObservableObject {
    /// Paths that finished decoding — the published bit that redraws the strip.
    @Published private(set) var loaded: Set<String> = []

    /// Prefer the 2000px preview copy over the 42MP original (set by AppState).
    weak var preview: PreviewStore?
    /// For per-photo specific adjustments (set by AppState).
    weak var app: AppState?

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
        let source = previewSource(for: url)
        let specific = app?.photoAdjustments[url.lastPathComponent]
        queue.async {
            var image = ImageDecode.downsampled(source, maxPixel: ImageDecode.thumbnailPixel)
            if let specific, let img = image {
                image = ImageAdjust.render(img, gamma: specific.gamma, rotation: specific.rotation)
            }
            Task { @MainActor in
                self.loading.remove(key)
                guard let image else { return }
                self.cache.setObject(image, forKey: key as NSString)
                self.loaded.insert(key)
            }
        }
    }

    /// Re-decode a thumbnail (specific settings changed).
    func reload(_ url: URL) {
        cache.removeObject(forKey: url.path as NSString)
        loaded.remove(url.path)
        load(url)
    }

    /// The small preview copy when it exists, else the original.
    private func previewSource(for url: URL) -> URL {
        if let p = preview?.previewURL(for: url), FileManager.default.fileExists(atPath: p.path) {
            return p
        }
        return url
    }
}
