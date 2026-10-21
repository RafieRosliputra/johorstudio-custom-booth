import Foundation

/// Per-photo specific adjustments that override the global gamma/rotation/frame.
/// Stored in logs/photo-settings.json, keyed by camera folder then filename.
struct PhotoAdjustment: Codable, Equatable {
    var gamma: Double
    var rotation: Double
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var frame: PhotoFrame { PhotoFrame(x: x, y: y, w: w, h: h) }

    static func snapshot(gamma: Double, rotation: Double, frame: PhotoFrame) -> PhotoAdjustment {
        PhotoAdjustment(gamma: gamma, rotation: rotation, x: frame.x, y: frame.y, w: frame.w, h: frame.h)
    }
}
