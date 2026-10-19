import Foundation
import CoreGraphics

/// A rectangle in top-left pixel coordinates.
struct AreaRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    /// greenLayer in mainoverlay.psd (2500×1667).
    static let printDefault = AreaRect(x: 157, y: 104, w: 2186, h: 1459)
    /// greenLayer in 2ndscreen.psd (1920×1080).
    static let liveDefault = AreaRect(x: 252, y: 67, w: 1416, h: 946)
}

/// Saved as settings.json in the working folder.
struct AppSettings: Codable, Equatable {
    var cameraFolder: String?
    var hotfolderPath: String?
    var overlayPath: String?
    var printArea = AreaRect.printDefault
    var truenasPath: String?
    var uploadEnabled = false
    var captureDeviceID: String?
    var screenDisplayID: UInt32?
    var liveArea = AreaRect.liveDefault
    var mirrorLive = true
    var mirrorOverlay = false
    var showTabPreview = true
    var countdownSeconds = 5

    init() {}

    // Missing keys fall back to defaults so older settings files keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        cameraFolder = try c.decodeIfPresent(String.self, forKey: .cameraFolder)
        hotfolderPath = try c.decodeIfPresent(String.self, forKey: .hotfolderPath)
        overlayPath = try c.decodeIfPresent(String.self, forKey: .overlayPath)
        printArea = try c.decodeIfPresent(AreaRect.self, forKey: .printArea) ?? d.printArea
        truenasPath = try c.decodeIfPresent(String.self, forKey: .truenasPath)
        uploadEnabled = try c.decodeIfPresent(Bool.self, forKey: .uploadEnabled) ?? d.uploadEnabled
        captureDeviceID = try c.decodeIfPresent(String.self, forKey: .captureDeviceID)
        screenDisplayID = try c.decodeIfPresent(UInt32.self, forKey: .screenDisplayID)
        liveArea = try c.decodeIfPresent(AreaRect.self, forKey: .liveArea) ?? d.liveArea
        mirrorLive = try c.decodeIfPresent(Bool.self, forKey: .mirrorLive) ?? d.mirrorLive
        mirrorOverlay = try c.decodeIfPresent(Bool.self, forKey: .mirrorOverlay) ?? d.mirrorOverlay
        showTabPreview = try c.decodeIfPresent(Bool.self, forKey: .showTabPreview) ?? d.showTabPreview
        countdownSeconds = try c.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? d.countdownSeconds
    }

    static func load(from url: URL) -> AppSettings {
        guard let data = try? Data(contentsOf: url) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Log.warn("settings.json unreadable (\(error.localizedDescription)) — using defaults")
            return AppSettings()
        }
    }

    func save(to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            Log.error("Cannot save settings.json: \(error.localizedDescription)")
        }
    }
}
