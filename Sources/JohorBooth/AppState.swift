import SwiftUI
import AppKit
import Combine
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum MainTab: String, CaseIterable {
    case print = "PRINT"
    case upload = "UPLOAD"
    case log = "LOG"
    case screen = "SCREEN"
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppState: ObservableObject {
    let paths: WorkPaths
    @Published var settings: AppSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    @Published var tab: MainTab = .print
    @Published var alert: AlertItem?
    @Published var logDetached = false

    @Published private(set) var overlayCI: CIImage?
    @Published private(set) var overlayCG: CGImage?
    /// The livefolder photo, downsampled to 1500 px. The overlay is drawn on top
    /// of it in the view, so zoom/pan only ever touch the photo.
    @Published private(set) var previewPhoto: CGImage?
    @Published private(set) var previewMessage: String? = "details not loaded"

    /// Where the photo sits on the canvas. `nil` = fill the overlay's photo area.
    /// Deliberately not part of `AppSettings`: this changes on every scroll tick
    /// and must not hit the disk.
    @Published var photoFrame: PhotoFrame?

    /// Session-only photo adjustments (reset on launch, not in settings.json).
    /// `gamma` = brightness curve (1.0 = none), `rotation` = degrees clockwise.
    @Published var gamma: Double = 1.0
    @Published var rotation: Double = 0.0

    /// Per-photo specific settings (override global), keyed by filename.
    @Published private(set) var photoAdjustments: [String: PhotoAdjustment] = [:]
    /// Per-photo OK'd-but-not-committed drafts (yellow ring), keyed by filename.
    @Published private(set) var pendingDrafts: [String: PhotoAdjustment] = [:]
    /// Tentative per-photo edit (edit dialog open) — preview-only until OK/commit.
    @Published var draft: PhotoAdjustment?
    /// Copied via CMD+C for CMD+V paste.
    private var clipboardAdjustment: PhotoAdjustment?

    /// Transient toast (auto-dismisses). `toastLarge` = the 400% "sent to printer" one.
    @Published var toast: String?
    @Published var toastLarge = false
    private var toastTimer: Timer?

    var currentSpecific: PhotoAdjustment? {
        guard let url = library.current else { return nil }
        return photoAdjustments[url.lastPathComponent]
    }

    var currentPending: PhotoAdjustment? {
        guard let url = library.current else { return nil }
        return pendingDrafts[url.lastPathComponent]
    }

    var hasSpecific: Bool { currentSpecific != nil }

    /// Yellow ring: an uncommitted edit is pending for the current photo.
    var hasPending: Bool { draft != nil || currentPending != nil }

    /// Per-photo ring: none / yellow (pending) / red (committed specific).
    enum Ring: Int { case none = 0, yellow = 1, red = 2 }
    func ring(for url: URL) -> Ring {
        let name = url.lastPathComponent
        if pendingDrafts[name] != nil { return .yellow }
        if photoAdjustments[name] != nil { return .red }
        return .none
    }

    /// Effective gamma/rotation for a specific URL (pending > specific > global).
    func effectiveAdjustment(for url: URL) -> (gamma: Double, rotation: Double)? {
        let name = url.lastPathComponent
        let g = pendingDrafts[name]?.gamma ?? photoAdjustments[name]?.gamma ?? gamma
        let r = pendingDrafts[name]?.rotation ?? photoAdjustments[name]?.rotation ?? rotation
        if abs(g - 1.0) < 0.0005, abs(r) < 0.0005 { return nil }
        return (g, r)
    }

    var effectiveGamma: Double { draft?.gamma ?? currentPending?.gamma ?? currentSpecific?.gamma ?? gamma }
    var effectiveRotation: Double { draft?.rotation ?? currentPending?.rotation ?? currentSpecific?.rotation ?? rotation }

    /// Begin editing this photo: detach from global into a preview-only draft.
    func beginEdit() {
        draft = currentPending ?? currentSpecific ?? PhotoAdjustment.snapshot(gamma: gamma, rotation: rotation, frame: effectiveFrame)
    }

    func updateDraft(_ transform: (inout PhotoAdjustment) -> Void) {
        guard var d = draft else { return }
        transform(&d)
        draft = d
        renderPreviewPhoto()
    }

    let library = ImageLibrary()
    let thumbs = ThumbnailStore()
    let preview = PreviewStore()
    let compositor = Compositor()
    let capture = CaptureManager()
    let printer: PrintService
    let upload: UploadManager
    let screen: SecondScreenController

    private var activity: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var previewGeneration = 0
    private var started = false
    private var basePreviewPhoto: CGImage?
    private var deselectMonitor: Any?

    init() {
        let paths = WorkPaths.detect()
        LogStore.shared.configure(folder: paths.logs)
        self.paths = paths
        settings = AppSettings.load(from: paths.settingsFile)
        printer = PrintService()
        upload = UploadManager()
        screen = SecondScreenController()

        printer.app = self
        upload.app = self
        screen.app = self
        preview.app = self
        thumbs.preview = preview
        thumbs.app = self
        printer.loadHistory(paths.historyFile)

        // Keep the Mac (and displays) awake for the whole event.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "Photo booth event running"
        )

        library.$current
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshPreview() }
            }
            .store(in: &cancellables)
        library.$files
            .map(\.isEmpty)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPreview()
                    self?.printer.refreshUnsynced()
                }
            }
            .store(in: &cancellables)
        // Backfill + keep up: every livefolder photo gets a 2000px preview copy.
        library.$files
            .removeDuplicates()
            .sink { [weak self] files in
                self?.preview.prepareAll(files)
            }
            .store(in: &cancellables)
        library.newImageReady
            .sink { [weak self] url in
                Task { @MainActor in
                    self?.screen.showNewImage(url)
                    // Every photo that lands in the livefolder is composited and
                    // queued for TrueNAS straight away — no operator action needed.
                    self?.printer.prepareUpload(for: url)
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !started else { return }
        started = true
        ensureFolders()
        loadOverlay()
        preview.setCameraFolder(cameraFolderURL)
        library.setFolder(cameraFolderURL)
        loadPhotoSettings()
        StartupChecks.run(self)
        upload.startup()
        installDeselectMonitor()
        Log.info("Startup checks finished")
    }

    /// Clicking outside a text field clears its focus, so scroll / arrow keys
    /// (filmstrip + preview) work again instead of being eaten by the field.
    private func installDeselectMonitor() {
        guard deselectMonitor == nil else { return }
        deselectMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let window = event.window, window.firstResponder is NSText else { return event }
                let point = window.contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
                if let hit = window.contentView?.hitTest(point), !Self.isTextControl(hit) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
    }

    private static func isTextControl(_ view: NSView) -> Bool {
        view is NSTextField || view is NSTextView
    }

    // MARK: - Folders

    var cameraFolderURL: URL {
        settings.cameraFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? paths.defaultCamera
    }

    var hotfolderURL: URL? {
        settings.hotfolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var hotfolderDisplay: String {
        guard let url = hotfolderURL else { return "No hotfolder selected" }
        return "\(url.deletingLastPathComponent().lastPathComponent) / \(url.lastPathComponent)"
    }

    var cameraFolderDisplay: String {
        let url = cameraFolderURL
        return "\(url.deletingLastPathComponent().lastPathComponent) / \(url.lastPathComponent)"
    }

    var overlayName: String {
        settings.overlayPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No overlay selected"
    }

    var detailsLoaded: Bool {
        overlayCI != nil
            && FileManager.default.isDirectory(cameraFolderURL)
            && hotfolderURL.map { FileManager.default.isDirectory($0) } == true
    }

    func ensureFolders() {
        let fm = FileManager.default
        var folders: [(String, URL)] = [("logs", paths.logs)]
        if settings.cameraFolder == nil { folders.append(("directory", paths.defaultCamera)) }
        if fm.isDirectory(cameraFolderURL) || settings.cameraFolder == nil {
            folders.append(("WEBP", WorkPaths.upload(in: cameraFolderURL)))
            folders.append(("WEBP/ORIGINAL", WorkPaths.original(in: cameraFolderURL)))
        }
        for (label, url) in folders where !fm.isDirectory(url) {
            do {
                try fm.ensureDirectory(url)
                Log.info("Created \(label) folder: \(url.path)")
            } catch {
                Log.error("Cannot create \(label) folder \(url.path): \(error.localizedDescription)")
            }
        }
    }

    func chooseCameraFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder where camera images arrive"
        panel.directoryURL = cameraFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Log.info("Directory set: \(url.path)")
        if url.path == settings.cameraFolder {
            library.setFolder(url)
        } else {
            settings.cameraFolder = url.path
        }
    }

    func chooseHotfolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose the printer hotfolder (JPG copies are saved here)"
        panel.directoryURL = hotfolderURL ?? paths.root
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let err = FileManager.default.probeWrite(in: url) {
            Log.error("Hotfolder is not writable: \(url.path) — \(err)")
            showAlert(title: "Hotfolder not writable", message: "\(url.path)\n\(err)")
            return
        }
        Log.ok("Hotfolder set: \(url.path)")
        if url.path == settings.hotfolderPath {
            refreshPreview()
        } else {
            settings.hotfolderPath = url.path
        }
    }

    func chooseOverlay() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .webP]
        panel.prompt = "Use Overlay"
        panel.message = "Choose the overlay (PNG or WebP, 2500×1667 with a transparent photo area)"
        if let path = settings.overlayPath {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        } else {
            panel.directoryURL = paths.root
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.path == settings.overlayPath {
            loadOverlay()
        } else {
            settings.overlayPath = url.path
        }
    }

    func loadOverlay() {
        guard let path = settings.overlayPath else {
            overlayCI = nil
            overlayCG = nil
            refreshPreview()
            return
        }
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            overlayCI = nil
            overlayCG = nil
            Log.error("Cannot load overlay: \(path)")
            showAlert(title: "Overlay not loaded", message: "Cannot read \(url.lastPathComponent).")
            refreshPreview()
            return
        }
        overlayCG = cg
        overlayCI = CIImage(cgImage: cg)
        if cg.width != Int(Compositor.canvas.width) || cg.height != Int(Compositor.canvas.height) {
            Log.warn("Overlay is \(cg.width)×\(cg.height), expected 2500×1667 — it will be stretched to fit")
        }
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            Log.warn("Overlay has no transparency — the photo underneath will be hidden")
        default:
            break
        }
        Log.ok("Overlay loaded: \(url.lastPathComponent)")
        refreshPreview()
    }

    // MARK: - Preview

    /// The photo rect actually in use: the edit draft, else the per-photo specific
    /// frame, else the user's global frame, else the overlay's area.
    var effectiveFrame: PhotoFrame {
        draft?.frame ?? currentPending?.frame ?? currentSpecific?.frame ?? photoFrame ?? PhotoFrame(settings.printArea.cgRect)
    }

    /// 100% = photo exactly fills the overlay's photo area.
    var photoZoom: Double {
        let area = settings.printArea.cgRect
        guard area.width > 0 else { return 1 }
        return effectiveFrame.w / area.width
    }

    /// Updates the frame the preview/print uses — the edit draft when open, else
    /// the (pending) specific photo's frame, else the global frame.
    func updateEffectiveFrame(_ frame: PhotoFrame) {
        let clamped = frame.clamped()
        if draft != nil {
            updateDraft { $0.x = clamped.x; $0.y = clamped.y; $0.w = clamped.w; $0.h = clamped.h }
        } else if let url = library.current, currentSpecific != nil || currentPending != nil {
            var adj = currentPending ?? currentSpecific!
            adj.x = clamped.x; adj.y = clamped.y; adj.w = clamped.w; adj.h = clamped.h
            pendingDrafts[url.lastPathComponent] = adj
            renderPreviewPhoto()
        } else {
            photoFrame = clamped
        }
    }

    /// Keep the current size but put the photo back in the middle of the area.
    func centrePhoto() {
        let area = settings.printArea.cgRect
        var frame = effectiveFrame
        frame.x = area.midX - frame.w / 2
        frame.y = area.midY - frame.h / 2
        updateEffectiveFrame(frame)
    }

    /// Zoom badge double-click: back to 100% (fill the photo area).
    func resetZoom() {
        let area = settings.printArea.cgRect
        if draft != nil {
            updateDraft { $0.x = area.minX; $0.y = area.minY; $0.w = area.width; $0.h = area.height }
        } else if let url = library.current, currentSpecific != nil || currentPending != nil {
            var adj = currentPending ?? currentSpecific!
            adj.x = area.minX; adj.y = area.minY; adj.w = area.width; adj.h = area.height
            pendingDrafts[url.lastPathComponent] = adj
            renderPreviewPhoto()
        } else {
            photoFrame = nil
        }
    }

    func refreshPreview() {
        previewGeneration += 1
        let generation = previewGeneration
        guard detailsLoaded, overlayCI != nil else {
            previewPhoto = nil
            previewMessage = "details not loaded"
            return
        }
        guard let url = library.current else {
            previewPhoto = nil
            previewMessage = library.files.isEmpty ? "No images in directory yet" : "Press LATEST IMAGE NAME to load"
            return
        }
        Task {
            _ = await FileReady.wait(url, timeout: 10)
            let image = await preview.previewImage(for: url)
            guard generation == previewGeneration else { return }
            if let image {
                basePreviewPhoto = image
                renderPreviewPhoto()
            } else {
                basePreviewPhoto = nil
                previewPhoto = nil
                previewMessage = "Cannot load \(url.lastPathComponent)"
                Log.error("Preview failed for \(url.lastPathComponent)")
            }
        }
    }

    /// Re-draws `previewPhoto` from the base photo with the current gamma/rotation.
    private func renderPreviewPhoto() {
        guard let base = basePreviewPhoto else {
            previewPhoto = nil
            return
        }
        let g = effectiveGamma
        let r = effectiveRotation
        if abs(g - 1.0) < 0.0005, abs(r) < 0.0005 {
            previewPhoto = base
        } else {
            previewPhoto = ImageAdjust.render(base, gamma: g, rotation: r) ?? base
        }
        previewMessage = nil
    }

    // MARK: - Adjustments (gamma / rotation, session-only)

    func setGamma(_ value: Double) {
        let v = min(3.0, max(0.1, value))
        guard abs(v - gamma) > 0.0005 else { return }
        gamma = v
        Log.info("gamma → \(Self.number(v))")
        renderPreviewPhoto()
    }

    func rotate(by degrees: Double) {
        var v = (rotation + degrees).truncatingRemainder(dividingBy: 360)
        if v > 180 { v -= 360 }
        if v < -180 { v += 360 }
        guard abs(v - rotation) > 0.0005 else { return }
        rotation = v
        Log.info("rotation → \(Self.number(v))°")
        renderPreviewPhoto()
    }

    private static func number(_ v: Double) -> String {
        var out = String(format: "%.2f", v)
        while out.contains("."), out.hasSuffix("0") { out.removeLast() }
        if out.hasSuffix(".") { out.removeLast() }
        return out
    }

    // MARK: - Toast

    func showToast(_ text: String, large: Bool = false, duration: TimeInterval = 3) {
        toast = text
        toastLarge = large
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.toast = nil }
        }
    }

    // MARK: - Per-photo specific settings

    /// Snapshots the current GLOBAL settings as this photo's pending specific (yellow).
    func applyCurrentAsSpecific() {
        guard let url = library.current else { return }
        let adj = PhotoAdjustment.snapshot(gamma: gamma, rotation: rotation, frame: effectiveFrame)
        pendingDrafts[url.lastPathComponent] = adj
        draft = nil
        renderPreviewPhoto()
    }

    func resetPhotoSettings() {
        guard let url = library.current else { return }
        photoAdjustments.removeValue(forKey: url.lastPathComponent)
        pendingDrafts.removeValue(forKey: url.lastPathComponent)
        draft = nil
        savePhotoSettings()
        Log.info("photo \(url.lastPathComponent): reset to global")
        renderPreviewPhoto()
    }

    func copySettings() {
        guard library.current != nil else { return }
        clipboardAdjustment = PhotoAdjustment.snapshot(gamma: effectiveGamma, rotation: effectiveRotation, frame: effectiveFrame)
        Log.info("Settings copied to clipboard")
        showToast("Settings copied to clipboard")
    }

    func pasteSettings() {
        guard let url = library.current, let adj = clipboardAdjustment else { return }
        pendingDrafts[url.lastPathComponent] = adj
        draft = nil
        renderPreviewPhoto()
    }

    /// Edit dialog OK: keep the draft as a pending change (yellow ring, pulse).
    func saveDraft() {
        guard let d = draft, let url = library.current else { return }
        pendingDrafts[url.lastPathComponent] = d
        draft = nil
        renderPreviewPhoto()
    }

    /// Edit dialog Cancel / dismiss: discard the draft, back to the pre-edit state.
    func cancelDraft() {
        draft = nil
        renderPreviewPhoto()
    }

    /// Commit icon: apply the pending draft (or active draft) as specific, then
    /// regenerate the WebP (local + TrueNAS + backup) and the 2000px preview.
    func commitPhoto() {
        guard let url = library.current else { return }
        if let d = draft { pendingDrafts[url.lastPathComponent] = d; draft = nil }
        guard let adj = pendingDrafts[url.lastPathComponent] else { return }
        photoAdjustments[url.lastPathComponent] = adj
        pendingDrafts[url.lastPathComponent] = nil
        draft = nil
        savePhotoSettings()
        Log.info("photo \(url.lastPathComponent): committed γ\(Self.number(adj.gamma)) r\(Self.number(adj.rotation)) pan \(Int(adj.x)),\(Int(adj.y)) zoom \(Int(adj.w)),\(Int(adj.h))")
        renderPreviewPhoto()
        printer.reprepareUpload(for: url)
        preview.bakeAdjustment(for: url, gamma: adj.gamma, rotation: adj.rotation)
    }

    // MARK: - Per-photo persistence (logs/photo-settings.json)

    private var photoSettingsFile: URL { paths.logs.appendingPathComponent("photo-settings.json") }

    func loadPhotoSettings() {
        guard let data = try? Data(contentsOf: photoSettingsFile),
              let root = try? JSONDecoder().decode([String: [String: PhotoAdjustment]].self, from: data) else {
            photoAdjustments = [:]
            return
        }
        photoAdjustments = root[cameraFolderURL.path] ?? [:]
        if !photoAdjustments.isEmpty { Log.info("Loaded \(photoAdjustments.count) per-photo adjustment(s)") }
    }

    private func savePhotoSettings() {
        var root: [String: [String: PhotoAdjustment]] = [:]
        if let data = try? Data(contentsOf: photoSettingsFile),
           let existing = try? JSONDecoder().decode([String: [String: PhotoAdjustment]].self, from: data) {
            root = existing
        }
        root[cameraFolderURL.path] = photoAdjustments
        do {
            try JSONEncoder().encode(root).write(to: photoSettingsFile, options: .atomic)
        } catch {
            Log.error("Cannot save photo-settings.json: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings

    private func settingsChanged(from old: AppSettings) {
        guard settings != old else { return }
        if settings.countdownSeconds < 1 || settings.countdownSeconds > 60 {
            settings.countdownSeconds = min(60, max(1, settings.countdownSeconds))
            return
        }
        settings.save(to: paths.settingsFile)
        if settings.cameraFolder != old.cameraFolder {
            ensureFolders()
            preview.setCameraFolder(cameraFolderURL)
            library.setFolder(cameraFolderURL)
            loadPhotoSettings()
            upload.refreshCounts()
            refreshPreview()
        }
        if settings.overlayPath != old.overlayPath { loadOverlay() }
        if settings.hotfolderPath != old.hotfolderPath { refreshPreview() }
        if settings.printArea != old.printArea { refreshPreview() }
        if settings.captureDeviceID != old.captureDeviceID { capture.setDevice(settings.captureDeviceID) }
        if settings.screenDisplayID != old.screenDisplayID, screen.isOpen { screen.open() }
    }

    /// Removes every job from the default macOS printer's queue (CUPS).
    func purgePrintQueue() {
        Log.warn("PURGE print queue requested")
        Task {
            let result = await Task.detached(priority: .userInitiated) { PrinterQueue.purgeDefault() }.value
            switch result {
            case .success(let message):
                Log.ok(message)
                showAlert(title: "Print queue purged", message: message)
            case .failure(let error):
                Log.error("Purge failed: \(error.localizedDescription)")
                showAlert(title: "Purge failed", message: error.localizedDescription)
            }
        }
    }

    func sendCurrentToScreen() {
        guard let url = library.current else { return }
        Log.info("2nd screen: showing \(url.lastPathComponent) from PRINT tab")
        screen.showNewImage(url)
    }

    func showAlert(title: String, message: String) {
        alert = AlertItem(title: title, message: message)
    }
}
