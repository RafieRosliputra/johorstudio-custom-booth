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
        StartupChecks.run(self)
        upload.startup()
        Log.info("Startup checks finished")
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
            folders.append(("upload", WorkPaths.upload(in: cameraFolderURL)))
            folders.append(("upload/DONE", WorkPaths.done(in: cameraFolderURL)))
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

    /// The photo rect actually in use: the user's frame, or the overlay's area.
    var effectiveFrame: PhotoFrame {
        photoFrame ?? PhotoFrame(settings.printArea.cgRect)
    }

    /// 100% = photo exactly fills the overlay's photo area.
    var photoZoom: Double {
        let area = settings.printArea.cgRect
        guard area.width > 0 else { return 1 }
        return effectiveFrame.w / area.width
    }

    /// Keep the current size but put the photo back in the middle of the area.
    func centrePhoto() {
        let area = settings.printArea.cgRect
        var frame = effectiveFrame
        frame.x = area.midX - frame.w / 2
        frame.y = area.midY - frame.h / 2
        photoFrame = frame.clamped()
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
                previewPhoto = image
                previewMessage = nil
            } else {
                previewPhoto = nil
                previewMessage = "Cannot load \(url.lastPathComponent)"
                Log.error("Preview failed for \(url.lastPathComponent)")
            }
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
