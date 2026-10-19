import AVFoundation
import AppKit
import QuartzCore
import SwiftUI

/// Live feed from the HDMI capture card. Frames are pushed as IOSurfaces straight
/// into CALayers (no CPU copy), so the tab preview and the 2nd screen can both show it.
final class CaptureManager: NSObject, ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var running = false
    @Published private(set) var activeDevice: String?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "booth.capture.session")
    private let videoQueue = DispatchQueue(label: "booth.capture.video", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var clients = Set<String>()
    private var wantedDeviceID: String?
    private let layers = NSHashTable<CALayer>.weakObjects()   // main thread only
    private let frameLock = NSLock()
    private var framePending = false

    override init() {
        super.init()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
    }

    static func discover() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    @MainActor func refreshDevices() {
        devices = Self.discover().map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    @MainActor func setDevice(_ id: String?) {
        wantedDeviceID = id
        if running { configureAndRun() }
    }

    /// The session runs while at least one view (tab preview / 2nd screen) needs it.
    @MainActor func addClient(_ name: String) {
        clients.insert(name)
        if !running { startSession() }
    }

    @MainActor func removeClient(_ name: String) {
        clients.remove(name)
        if clients.isEmpty, running { stopSession() }
    }

    @MainActor private func startSession() {
        running = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        Log.ok("Camera access granted")
                        self.configureAndRun()
                    } else {
                        self.running = false
                        Log.error("Camera access denied — enable johorstudio-custom-photobooth in System Settings › Privacy & Security › Camera")
                    }
                }
            }
        default:
            running = false
            Log.error("Camera access denied — enable johorstudio-custom-photobooth in System Settings › Privacy & Security › Camera")
        }
    }

    @MainActor private func configureAndRun() {
        guard !clients.isEmpty else {
            running = false
            return
        }
        let all = Self.discover()
        guard let device = all.first(where: { $0.uniqueID == wantedDeviceID })
            ?? all.first(where: { $0.deviceType == .external })
            ?? all.first
        else {
            running = false
            activeDevice = nil
            Log.error("No capture device found — plug in the HDMI capture card, then press Refresh in the SCREEN tab")
            return
        }
        activeDevice = device.localizedName
        running = true
        let session = self.session
        let output = self.output
        sessionQueue.async {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) { session.addInput(input) }
            } catch {
                Log.error("Cannot open \(device.localizedName): \(error.localizedDescription)")
            }
            if !session.outputs.contains(output), session.canAddOutput(output) {
                session.addOutput(output)
            }
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            } else {
                session.sessionPreset = .high
            }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
            Log.ok("Live feed started: \(device.localizedName)")
        }
    }

    @MainActor private func stopSession() {
        running = false
        activeDevice = nil
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
                Log.info("Live feed stopped")
            }
        }
    }

    func attach(_ layer: CALayer) { layers.add(layer) }
    func detach(_ layer: CALayer) { layers.remove(layer) }
}

extension CaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        frameLock.lock()
        if framePending {
            frameLock.unlock()
            return
        }
        framePending = true
        frameLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameLock.lock()
            self.framePending = false
            self.frameLock.unlock()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in self.layers.allObjects { layer.contents = surface }
            CATransaction.commit()
        }
    }
}

/// Shows the live feed, filling its frame (aspect fill), optionally mirrored.
struct LiveVideoView: NSViewRepresentable {
    let capture: CaptureManager
    var mirrored: Bool

    func makeNSView(context: Context) -> LiveVideoNSView {
        let view = LiveVideoNSView()
        view.mirrored = mirrored
        view.capture = capture
        return view
    }

    func updateNSView(_ view: LiveVideoNSView, context: Context) {
        view.mirrored = mirrored
    }

    static func dismantleNSView(_ view: LiveVideoNSView, coordinator: ()) {
        view.capture = nil
    }
}

final class LiveVideoNSView: NSView {
    let videoLayer = CALayer()

    var capture: CaptureManager? {
        didSet {
            oldValue?.detach(videoLayer)
            capture?.attach(videoLayer)
        }
    }

    var mirrored = true {
        didSet { updateTransform() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        videoLayer.contentsGravity = .resizeAspectFill
        videoLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "transform": NSNull()]
        layer?.addSublayer(videoLayer)
        updateTransform()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Clicks go to the SwiftUI view underneath (the PRINT tab preview is clickable).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.bounds = bounds
        videoLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    private func updateTransform() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        CATransaction.commit()
    }
}
