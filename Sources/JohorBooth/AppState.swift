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
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var previewMessage: String? = "details not loaded"

    let library = ImageLibrary()
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
                Task { @MainActor in self?.refreshPreview() }
            }
            .store(in: &cancellables)
        library.newImageReady
            .sink { [weak self] url in
                Task { @MainActor in self?.screen.showNewImage(url) }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !started else { return }
        started = true
        ensureFolders()
        loadOverlay()
        library.setFolder(cameraFolderURL)
        StartupChecks.run(self)
        upload.startup()
        Log.info("Startup checks finished")
    }

    // MARK: - Folders

    var cameraFolderURL: URL {
        settings.cameraFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? paths.defaultCamera
    }

    var cameraFolderDisplay: String {
        let url = cameraFolderURL
        return "\(url.deletingLastPathComponent().lastPathComponent) / \(url.lastPathComponent)"
    }

    var overlayName: String {
        settings.overlayPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No overlay selected"
    }

    var detailsLoaded: Bool {
        overlayCI != nil && FileManager.default.isDirectory(cameraFolderURL)
    }

    func ensureFolders() {
        let fm = FileManager.default
        var folders: [(String, URL)] = [("hotfolder", paths.hotfolder), ("logs", paths.logs)]
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

    func refreshPreview() {
        previewGeneration += 1
        let generation = previewGeneration
        guard detailsLoaded, let overlay = overlayCI else {
            previewImage = nil
            previewMessage = "details not loaded"
            return
        }
        guard let url = library.current else {
            previewImage = nil
            previewMessage = library.files.isEmpty ? "No images in directory yet" : "Press LATEST IMAGE NAME to load"
            return
        }
        let area = settings.printArea.cgRect
        let compositor = self.compositor
        Task {
            _ = await FileReady.wait(url, timeout: 10)
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CGImage, Error> in
                Result { () throws -> CGImage in
                    try compositor.render(
                        compositor.composite(photo: url, overlay: overlay, area: area),
                        size: Compositor.previewSize
                    )
                }
            }.value
            guard generation == previewGeneration else { return }
            switch result {
            case .success(let image):
                previewImage = image
                previewMessage = nil
            case .failure(let error):
                previewImage = nil
                previewMessage = "Cannot load \(url.lastPathComponent)"
                Log.error("Preview failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Settings

    private func settingsChanged(from old: AppSettings) {
        guard settings != old else { return }
        settings.save(to: paths.settingsFile)
        if settings.cameraFolder != old.cameraFolder {
            ensureFolders()
            library.setFolder(cameraFolderURL)
            upload.refreshCounts()
            refreshPreview()
        }
        if settings.overlayPath != old.overlayPath { loadOverlay() }
        if settings.printArea != old.printArea { refreshPreview() }
        if settings.captureDeviceID != old.captureDeviceID { capture.setDevice(settings.captureDeviceID) }
        if settings.screenDisplayID != old.screenDisplayID, screen.isOpen { screen.open() }
    }

    func showAlert(title: String, message: String) {
        alert = AlertItem(title: title, message: message)
    }
}
