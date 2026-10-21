import CoreGraphics
import Foundation

/// Where the photo sits on the 2500×1667 canvas, in canvas pixels with a
/// top-left origin — the same space as the overlay's photo area.
///
/// Zoom and drag both edit this rect, so the preview and the printed JPG always
/// agree. `nil` on `AppState` means "fill the overlay's photo area" (the old
/// behaviour), which is what the Reset button goes back to.
struct PhotoFrame: Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    /// Never let the photo shrink to nothing or grow past 3 canvases.
    static let minSide: Double = 64

    func clamped() -> PhotoFrame {
        let maxW = Compositor.canvas.width * 3
        let maxH = Compositor.canvas.height * 3
        var f = self
        f.w = min(max(f.w, Self.minSide), maxW)
        f.h = min(max(f.h, Self.minSide), maxH)
        f.x = min(max(f.x, -maxW), maxW)
        f.y = min(max(f.y, -maxH), maxH)
        return f
    }

    /// Zoom about a point in canvas pixels (scroll over the preview).
    func scaled(by factor: Double, around point: CGPoint) -> PhotoFrame {
        var f = self
        f.w = w * factor
        f.h = h * factor
        f.x = point.x + (x - point.x) * factor
        f.y = point.y + (y - point.y) * factor
        return f.clamped()
    }
}
