import CoreImage
import CoreGraphics

/// Places a photo into the overlay's photo area (fill + centre crop) underneath
/// the overlay, on the 2500×1667 canvas of mainoverlay.psd. Runs on the GPU (Metal).
final class Compositor {
    static let canvas = CGSize(width: 2500, height: 1667)
    static let printSize = CGSize(width: 1800, height: 1200)   // 4R
    static let previewSize = CGSize(width: 1500, height: 1000)

    let srgb: CGColorSpace
    private let context: CIContext

    init() {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        self.srgb = srgb
        context = CIContext(options: [
            .workingColorSpace: srgb,
            .outputColorSpace: srgb,
            .cacheIntermediates: false,
        ])
    }

    /// `area` is the overlay's photo window; `frame` (top-left canvas pixels) overrides it
    /// when the operator zoomed or dragged the photo. `gamma` is the brightness curve
    /// (1.0 = none), `rotation` is degrees (clockwise, 0 = none) — both applied to the
    /// photo only, before it is scaled to cover the frame.
    func composite(photo url: URL, overlay: CIImage?, area: CGRect, frame: CGRect? = nil, gamma: Double = 1.0, rotation: Double = 0) throws -> CIImage {
        guard var photo = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw BoothError.cannotRead(url.lastPathComponent)
        }
        let canvasRect = CGRect(origin: .zero, size: Self.canvas)
        let source = frame ?? area
        // Core Image is bottom-left based.
        let target = CGRect(x: source.minX, y: Self.canvas.height - source.maxY, width: source.width, height: source.height)

        if abs(gamma - 1) > 0.0005 {
            photo = photo.applyingFilter("CIGammaAdjust", parameters: ["inputPower": gamma])
        }
        // Rotation pivot is irrelevant: we translate to origin + cover-crop below.
        if abs(rotation) > 0.0005 {
            photo = photo.transformed(by: CGAffineTransform(rotationAngle: rotation * .pi / 180))
        }

        photo = photo.transformed(by: CGAffineTransform(translationX: -photo.extent.minX, y: -photo.extent.minY))
        let scale = max(target.width / photo.extent.width, target.height / photo.extent.height)
        photo = Self.lanczos(photo, scaleX: scale, scaleY: scale)
        let e = photo.extent
        photo = photo
            .transformed(by: CGAffineTransform(translationX: target.midX - e.midX, y: target.midY - e.midY))
            .cropped(to: target)

        var out = photo.composited(over: CIImage(color: .black).cropped(to: canvasRect))
        if let overlay {
            out = Self.stretch(overlay, to: Self.canvas).composited(over: out)
        }
        return out.cropped(to: canvasRect)
    }

    func render(_ image: CIImage, size: CGSize) throws -> CGImage {
        var img = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if img.extent.size != size {
            img = Self.lanczos(img, scaleX: size.width / img.extent.width, scaleY: size.height / img.extent.height)
        }
        let rect = CGRect(origin: .zero, size: size)
        guard let cg = context.createCGImage(img, from: rect, format: .RGBA8, colorSpace: srgb) else {
            throw BoothError.renderFailed
        }
        return cg
    }

    /// High quality resample of an image whose extent starts at the origin.
    static func lanczos(_ image: CIImage, scaleX: CGFloat, scaleY: CGFloat) -> CIImage {
        let w = image.extent.width * scaleX
        let h = image.extent.height * scaleY
        return image.clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scaleY,
                kCIInputAspectRatioKey: scaleX / scaleY,
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    static func stretch(_ image: CIImage, to size: CGSize) -> CIImage {
        let e = image.extent
        return image
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: size.width / e.width, y: size.height / e.height))
    }
}
