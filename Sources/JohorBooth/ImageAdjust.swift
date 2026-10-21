import CoreImage
import CoreGraphics

/// Applies gamma (brightness curve) and rotation to a CGImage, for the live
/// preview — the print pipeline applies the same through `Compositor`.
enum ImageAdjust {
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .cacheIntermediates: false,
    ])

    /// Returns the adjusted image (rotated bounding box when `rotation != 0`),
    /// or the input unchanged when there is nothing to do / rendering fails.
    static func render(_ image: CGImage, gamma: Double, rotation: Double) -> CGImage? {
        var ci = CIImage(cgImage: image)
        if abs(gamma - 1.0) > 0.0005 {
            ci = ci.applyingFilter("CIGammaAdjust", parameters: ["inputPower": gamma])
        }
        if abs(rotation) > 0.0005 {
            ci = ci.transformed(by: CGAffineTransform(rotationAngle: rotation * .pi / 180))
        }
        let rect = ci.extent
        guard rect.width > 1, rect.height > 1 else { return image }
        return context.createCGImage(ci, from: rect) ?? image
    }
}
