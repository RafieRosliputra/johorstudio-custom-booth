import Foundation
import ImageIO

/// Watches a directory for added/removed/renamed entries.
final class FolderMonitor {
    private var source: DispatchSourceFileSystemObject?

    func start(_ url: URL, onChange: @escaping () -> Void) {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.warn("Cannot watch \(url.path) — using polling only")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        src.setEventHandler(handler: onChange)
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}

/// Tethering software writes files progressively; wait until a file is complete.
enum FileReady {
    static func wait(_ url: URL, timeout: TimeInterval = 20) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSize: Int64 = -1
        while Date() < deadline {
            let size = fileSize(url)
            if size > 0, size == lastSize, isComplete(url) { return true }
            lastSize = size
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return -1 }
        return size.int64Value
    }

    static func isComplete(_ url: URL) -> Bool {
        // A finished JPEG ends with the EOI marker FF D9.
        if ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            guard let end = try? handle.seekToEnd(), end >= 2 else { return false }
            try? handle.seek(toOffset: end - 2)
            guard let tail = try? handle.read(upToCount: 2), tail == Data([0xFF, 0xD9]) else { return false }
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetStatus(src) == .statusComplete && CGImageSourceGetCount(src) > 0
    }
}
