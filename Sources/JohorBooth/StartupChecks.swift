import Foundation
import AppKit
import AVFoundation
import Metal

/// Runs once at launch; every missing piece is written to the log.
enum StartupChecks {
    @MainActor
    static func run(_ app: AppState) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.info("===== JohorStudio Booth \(version) starting =====")
        Log.info("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        #if arch(arm64)
        Log.ok("Running native on Apple Silicon (arm64)")
        #else
        Log.warn("Running as x86_64 — build with scripts/build_app.sh for Apple Silicon")
        #endif

        if let gpu = MTLCreateSystemDefaultDevice() {
            Log.ok("GPU: \(gpu.name) — Core Image renders on Metal")
        } else {
            Log.warn("No Metal GPU found — image rendering will be slow")
        }

        Log.ok("libwebp \(ImageExport.webpVersion) (bundled) — WebP export available")

        // Working folder
        if app.paths.isTranslocated {
            Log.error("App is running from a temporary macOS location (App Translocation). Move it into the event folder and run: xattr -dr com.apple.quarantine \"JohorStudio Booth.app\"")
        }
        Log.info("Working folder: \(app.paths.root.path)")
        if let err = FileManager.default.probeWrite(in: app.paths.root) {
            Log.error("Working folder is not writable: \(err)")
        }
        if let err = FileManager.default.probeWrite(in: app.paths.hotfolder) {
            Log.error("hotfolder is not writable: \(err)")
        } else {
            Log.ok("hotfolder ready: \(app.paths.hotfolder.path)")
        }

        // Directory & overlay
        let camera = app.cameraFolderURL
        if FileManager.default.isDirectory(camera) {
            Log.ok("Directory ready: \(camera.path)")
        } else {
            Log.error("Directory missing: \(camera.path) — choose it with the DIRECTORY button")
        }
        if app.settings.overlayPath == nil {
            Log.warn("No overlay selected — preview shows \"details not loaded\" until you SELECT OVERLAY")
        } else if app.overlayCG == nil {
            Log.error("Overlay could not be loaded: \(app.settings.overlayPath ?? "")")
        }

        // Live feed
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            Log.ok("Camera/capture permission granted")
        case .notDetermined:
            Log.info("Camera/capture permission will be asked when the live feed starts")
        default:
            Log.error("Camera/capture permission denied — System Settings › Privacy & Security › Camera")
        }
        app.capture.refreshDevices()
        if app.capture.devices.isEmpty {
            Log.warn("No capture device found (HDMI capture card not plugged in?)")
        } else {
            Log.ok("Capture devices: \(app.capture.devices.map(\.name).joined(separator: ", "))")
        }

        // Displays
        let screens = NSScreen.screens
        if screens.count > 1 {
            Log.ok("\(screens.count) displays: \(screens.map(\.localizedName).joined(separator: ", "))")
        } else {
            Log.warn("Only 1 display connected — connect the 2nd monitor for the guest screen")
        }
    }
}
