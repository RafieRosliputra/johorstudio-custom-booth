import CoreGraphics
import Foundation
import ImageIO

/// Decodes images at the size we actually show them.
///
/// The camera writes 42 MP JPEGs; decoding one at full size takes a moment and
/// needs ~130 MB. Nothing on screen needs more than 1500 pixels, so ImageIO is
/// asked for a downsampled thumbnail instead — same picture, a fraction of the
/// work.
enum ImageDecode {
    /// Big preview and 2nd screen.
    static let previewPixel = 1500
    /// Filmstrip cells.
    static let thumbnailPixel = 320

    static func downsampled(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
