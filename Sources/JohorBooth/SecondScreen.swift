import AppKit
import SwiftUI
import ImageIO

/// The guest-facing window (2ndscreen.psd, 1920×1080): live feed under the overlay;
/// when a new photo arrives it is shown for N seconds with a red countdown, then back to live.
@MainActor
final class SecondScreenController: ObservableObject {
    weak var app: AppState?

    @Published private(set) var isOpen = false
    @Published private(set) var photo: CGImage?
    @Published private(set) var countdown = 0

    private var window: KioskWindow?
    private var host: CursorHidingHostingView<SecondScreenContent>?
    private var targetID: UInt32?
    private var tick: Timer?
    private var screenObserver: NSObjectProtocol?
    private var loadGeneration = 0

    // MARK: - New photos

    func showNewImage(_ url: URL) {
        loadGeneration += 1
        let generation = loadGeneration
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                SecondScreenController.loadDisplayImage(url)
            }.value
            guard generation == loadGeneration else { return }
            guard let image else {
                Log.warn("2nd screen: cannot read \(url.lastPathComponent)")
                return
            }
            photo = image
            countdown = max(1, app?.settings.countdownSeconds ?? 5)
            startTick()
            Log.info("2nd screen: showing \(url.lastPathComponent) for \(countdown)s")
        }
    }

    func testWithLatest() {
        guard let last = app?.library.files.last else {
            Log.warn("2nd screen test: no images in directory")
            return
        }
        showNewImage(last)
    }

    nonisolated static func loadDisplayImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    private func startTick() {
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
    }

    private func step() {
        countdown -= 1
        if countdown <= 0 {
            countdown = 0
            photo = nil
            tick?.invalidate()
            tick = nil
        }
    }

    // MARK: - Window

    func open() {
        guard let app else { return }
        if window != nil { close() }
        let window = KioskWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.title = "JohorStudio Booth — 2nd screen"
        window.onEscape = { [weak self] in self?.close() }
        let host = CursorHidingHostingView(rootView: SecondScreenContent(app: app, controller: self))
        window.contentView = host

        let target = Self.screen(for: app.settings.screenDisplayID) ?? Self.defaultTarget()
        targetID = target.map(Self.displayID)
        place(window, on: target)
        window.orderFrontRegardless()

        self.window = window
        self.host = host
        isOpen = true
        app.capture.addClient("screen")
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        }
        if let target {
            Log.ok("2nd screen started on \(target.localizedName)")
        } else {
            Log.warn("Only one display connected — 2nd screen opened as a window on the main screen")
        }
    }

    func close() {
        guard let window else { return }
        host?.restoreCursor()
        window.orderOut(nil)
        window.close()
        self.window = nil
        host = nil
        isOpen = false
        app?.capture.removeClient("screen")
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        Log.info("2nd screen stopped")
    }

    private func screensChanged() {
        guard let window else { return }
        if let target = Self.screen(for: targetID) {
            place(window, on: target)
        } else {
            place(window, on: nil)
            Log.warn("2nd monitor disconnected — 2nd screen moved to the main screen")
        }
    }

    private func place(_ window: KioskWindow, on target: NSScreen?) {
        if let target {
            // Above the menu bar of that display, borderless and full size.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isMovableByWindowBackground = false
            window.setFrame(target.frame, display: true)
        } else {
            let main = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let width = main.width / 2
            let size = NSSize(width: width, height: width * 9 / 16)
            window.level = .normal
            window.collectionBehavior = []
            window.isMovableByWindowBackground = true
            window.setFrame(
                NSRect(x: main.midX - size.width / 2, y: main.midY - size.height / 2, width: size.width, height: size.height),
                display: true
            )
        }
    }

    // MARK: - Displays

    nonisolated static func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(for id: UInt32?) -> NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first { displayID($0) == id }
    }

    /// The first display that is not the main (menu bar) display.
    static func defaultTarget() -> NSScreen? {
        NSScreen.screens.count > 1 ? NSScreen.screens[1] : nil
    }
}

final class KioskWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

/// Hides the mouse pointer while it is over the 2nd screen.
final class CursorHidingHostingView<Content: View>: NSHostingView<Content> {
    private var hidden = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if !hidden {
            NSCursor.hide()
            hidden = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        restoreCursor()
    }

    func restoreCursor() {
        if hidden {
            NSCursor.unhide()
            hidden = false
        }
    }
}

/// 2nd screen layout in 1920×1080 design pixels, scaled to fit any view size.
struct SecondScreenContent: View {
    @ObservedObject var app: AppState
    @ObservedObject var controller: SecondScreenController

    static let design = CGSize(width: 1920, height: 1080)
    static let overlayRect = CGRect(x: 150, y: 0, width: 1620, height: 1080)   // overlayTop
    static let padRect = CGRect(x: 1755, y: 889, width: 165, height: 191)      // padding

    /// The print photo area mapped from the 2500×1667 overlay onto overlayRect.
    var photoRect: CGRect {
        let a = app.settings.printArea
        let sx = Self.overlayRect.width / Compositor.canvas.width
        let sy = Self.overlayRect.height / Compositor.canvas.height
        return CGRect(x: Self.overlayRect.minX + a.x * sx, y: Self.overlayRect.minY + a.y * sy, width: a.w * sx, height: a.h * sy)
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / Self.design.width, geo.size.height / Self.design.height)
            let origin = CGPoint(
                x: (geo.size.width - Self.design.width * s) / 2,
                y: (geo.size.height - Self.design.height * s) / 2
            )
            ZStack(alignment: .topLeading) {
                Color.black
                if let photo = controller.photo {
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .placed(photoRect, scale: s, origin: origin)
                } else {
                    LiveVideoView(capture: app.capture, mirrored: app.settings.mirrorLive)
                        .placed(app.settings.liveArea.cgRect, scale: s, origin: origin)
                }
                if let overlay = app.overlayCG {
                    Image(decorative: overlay, scale: 1)
                        .resizable()
                        .placed(Self.overlayRect, scale: s, origin: origin)
                        .allowsHitTesting(false)
                }
                if controller.countdown > 0 {
                    ZStack {
                        Color.white
                        Text("\(controller.countdown)")
                            .font(.system(size: 150 * s, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.red)
                            .minimumScaleFactor(0.3)
                    }
                    .placed(Self.padRect, scale: s, origin: origin)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .background(Color.black)
    }
}

extension View {
    /// Positions a view at a design-pixel rectangle (top-left based) using layout,
    /// so hosted AppKit views (the live feed) move with it.
    func placed(_ rect: CGRect, scale s: CGFloat, origin: CGPoint) -> some View {
        frame(width: rect.width * s, height: rect.height * s)
            .clipped()
            .padding(.leading, origin.x + rect.minX * s)
            .padding(.top, origin.y + rect.minY * s)
    }
}
