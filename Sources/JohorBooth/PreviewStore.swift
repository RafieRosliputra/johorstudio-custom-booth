import Foundation
import CoreGraphics
import Combine
import ImageIO

/// The 2000px JPEG copies in `camera/preview/`.
///
/// Every livefolder photo is pre-resized to a max side of 2000px and written to a
/// `preview/` subfolder (the livefolder scan is non-recursive, so these copies are
/// never listed). The big preview, filmstrip thumbnails and Quick Look all read
/// these small copies — the 42MP original is only touched for printing/compositing.
@MainActor
final class PreviewStore: ObservableObject {
    weak var app: AppState?

    /// Basenames (lastPathComponent) whose 2000px preview file is on disk.
    @Published private(set) var ready: Set<String> = []
    /// How many photos are still waiting for a preview.
    @Published private(set) var queued = 0

    private var folder: URL?
    private var generating = Set<String>()
    private var queue: [URL] = []
    private var active = false
    private let worker = DispatchQueue(label: "johorbooth.previews", qos: .utility)

    // MARK: - Folder

    func setCameraFolder(_ camera: URL) {
        let f = camera.appendingPathComponent("preview", isDirectory: true)
        do {
            try FileManager.default.ensureDirectory(f)
        } catch {
            Log.error("Cannot create preview folder \(f.path): \(error.localizedDescription)")
            folder = nil
            ready = []
            return
        }
        folder = f
        refreshReady()
    }

    func previewURL(for original: URL) -> URL? {
        guard let folder else { return nil }
        return folder.appendingPathComponent(original.lastPathComponent)
    }

    func previewExists(for original: URL) -> Bool {
        guard let url = previewURL(for: original) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Quick Look list: the baked 2000px copy (with gamma/rotation) where it
    /// exists, else the plain preview, else the original.
    func quickLookURLs(for files: [URL]) -> [URL] {
        files.map { url in
            if let baked = bakedURL(for: url), FileManager.default.fileExists(atPath: baked.path) { return baked }
            if let p = previewURL(for: url), FileManager.default.fileExists(atPath: p.path) { return p }
            return url
        }
    }

    /// Regenerates a gamma/rotation-baked 2000px copy (for Quick Look) on commit.
    func bakeAdjustment(for original: URL, gamma: Double, rotation: Double) {
        guard let baked = bakedURL(for: original) else { return }
        worker.async {
            if let down = ImageDecode.downsampled(original, maxPixel: ImageDecode.previewPixel),
               let adjusted = ImageAdjust.render(down, gamma: gamma, rotation: rotation),
               let data = try? ImageExport.jpegData(adjusted, quality: 0.5) {
                try? ImageExport.writeAtomically(data, to: baked)
            }
        }
    }

    private func bakedURL(for original: URL) -> URL? {
        guard let folder else { return nil }
        let base = original.deletingPathExtension().lastPathComponent
        return folder.appendingPathComponent("\(base).ql.jpg")
    }

    func refreshReady() {
        guard let folder else { ready = []; return }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        ready = Set(items.map(\.lastPathComponent))
    }

    // MARK: - Background generation

    /// Queues a photo for a preview. No-op when it is already made or queued.
    func prepare(_ url: URL) {
        let name = url.lastPathComponent
        guard !ready.contains(name), !generating.contains(name) else { return }
        guard !queue.contains(url) else { return }
        queue.append(url)
        queued = queue.count
        pump()
    }

    func prepareAll(_ urls: [URL]) {
        for url in urls { prepare(url) }
    }

    /// Deletes every preview and regenerates the lot (LOG tab).
    func rebuildAll() {
        guard let folder, let app else { return }
        queue.removeAll()
        queued = 0
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        for item in items { try? FileManager.default.removeItem(at: item) }
        ready = []
        Log.info("Rebuilding all previews (\(app.library.files.count) photos)")
        prepareAll(app.library.files)
    }

    private func pump() {
        guard !active, !queue.isEmpty, let folder else { return }
        let url = queue.removeFirst()
        queued = queue.count
        let name = url.lastPathComponent
        generating.insert(name)
        active = true
        let target = folder.appendingPathComponent(name)
        worker.async { [weak self] in
            let ok = PreviewStore.generate(url, to: target)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.generating.remove(name)
                self.active = false
                if ok { self.ready.insert(name) }
                self.pump()
            }
        }
    }

    // MARK: - On-demand fetch (blocking generate when missing)

    /// The ≤2000px image to show. Reads the preview file when it exists; otherwise
    /// generates it now, and only falls back to the original when that fails.
    func previewImage(for original: URL) async -> CGImage? {
        let name = original.lastPathComponent
        if let target = previewURL(for: original), FileManager.default.fileExists(atPath: target.path) {
            return await Self.decode(target)
        }
        // Generate inline (the operator picked it before the background queue got here).
        if let folder, let target = previewURL(for: original) {
            if !generating.contains(name) {
                generating.insert(name)
                let made: Bool = await withCheckedContinuation { cont in
                    worker.async { [weak self] in
                        let ok = PreviewStore.generate(original, to: target)
                        cont.resume(returning: ok)
                    }
                }
                generating.remove(name)
                if made {
                    ready.insert(name)
                } else {
                    Log.error("Preview generation failed for \(name) — showing original")
                }
            }
            if FileManager.default.fileExists(atPath: target.path) {
                return await Self.decode(target)
            }
        }
        // Fallback: decode the original (still capped at 2000px, never the full 42MP).
        return await Self.decode(original)
    }

    // MARK: - Helpers

    /// Downsample → JPEG q50 → atomic write. Runs off the main thread.
    nonisolated static func generate(_ source: URL, to target: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: target.path) else {
            guard let down = ImageDecode.downsampled(source, maxPixel: ImageDecode.previewPixel),
                  let data = try? ImageExport.jpegData(down, quality: 0.5) else {
                Log.error("Preview generation failed for \(source.lastPathComponent)")
                return false
            }
            do {
                try ImageExport.writeAtomically(data, to: target)
                return true
            } catch {
                Log.error("Preview write failed for \(source.lastPathComponent): \(error.localizedDescription)")
                return false
            }
        }
        return true
    }

    nonisolated static func decode(_ url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            ImageDecode.downsampled(url, maxPixel: ImageDecode.previewPixel)
        }.value
    }
}
