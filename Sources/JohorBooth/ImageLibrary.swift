import Foundation
import Combine

/// The JPGs in DIRECTORY, oldest → newest by the time they arrived in the folder.
///
/// The preview never changes by itself: new files only turn the LATEST button
/// green (and extend the list so NEXT can reach them). LATEST loads the newest.
@MainActor
final class ImageLibrary: ObservableObject {
    @Published private(set) var files: [URL] = []
    @Published private(set) var current: URL?
    @Published private(set) var latestSeen: URL?

    /// Fires once per new file after it has finished writing (used by the 2nd screen).
    let newImageReady = PassthroughSubject<URL, Never>()

    private(set) var folder: URL?
    private let monitor = FolderMonitor()
    private var pollTimer: Timer?
    private var known = Set<String>()
    private var primed = false
    private var scanning = false
    private var scanAgain = false
    private var waitingFor = Set<String>()

    var currentIndex: Int? { current.flatMap { files.firstIndex(of: $0) } }
    var hasNewer: Bool { files.last != nil && files.last != latestSeen }
    var canNext: Bool {
        guard let i = currentIndex else { return false }
        return i < files.count - 1
    }
    var canPrev: Bool {
        guard let i = currentIndex else { return false }
        return i > 0
    }

    func setFolder(_ url: URL) {
        folder = url
        files = []
        current = nil
        latestSeen = nil
        known = []
        primed = false
        monitor.stop()
        pollTimer?.invalidate()
        guard FileManager.default.isDirectory(url) else {
            Log.error("Directory not found: \(url.path)")
            return
        }
        monitor.start(url) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        // Safety net in case a filesystem event is missed.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
        Log.info("Watching directory: \(url.path)")
        rescan()
    }

    func rescan() {
        guard let folder else { return }
        if scanning {
            scanAgain = true
            return
        }
        scanning = true
        Task {
            let list = await Task.detached(priority: .utility) { ImageLibrary.scan(folder) }.value
            apply(list, folder: folder)
            scanning = false
            if scanAgain {
                scanAgain = false
                rescan()
            }
        }
    }

    func loadLatest() {
        guard let folder else { return }
        Task {
            let list = await Task.detached(priority: .userInitiated) { ImageLibrary.scan(folder) }.value
            apply(list, folder: folder)
            guard let last = files.last else {
                Log.warn("LATEST: no JPG images in \(folder.lastPathComponent)")
                return
            }
            current = last
            latestSeen = last
            Log.info("Loaded latest: \(last.lastPathComponent)")
        }
    }

    func next() {
        guard let i = currentIndex, i + 1 < files.count else { return }
        current = files[i + 1]
        if current == files.last { latestSeen = current }
    }

    func prev() {
        guard let i = currentIndex, i > 0 else { return }
        current = files[i - 1]
    }

    private func apply(_ list: [URL], folder: URL) {
        guard folder == self.folder else { return }
        if list != files { files = list }
        if let c = current, !list.contains(c) {
            Log.warn("\(c.lastPathComponent) was removed from the directory")
            current = list.last
        }
        if primed {
            for url in list where !known.contains(url.lastPathComponent) {
                announceWhenReady(url)
            }
        }
        known = Set(list.map(\.lastPathComponent))
        primed = true
    }

    private func announceWhenReady(_ url: URL) {
        let name = url.lastPathComponent
        guard !waitingFor.contains(name) else { return }
        waitingFor.insert(name)
        Log.info("New image detected: \(name)")
        Task {
            let ready = await FileReady.wait(url, timeout: 30)
            waitingFor.remove(name)
            if ready {
                newImageReady.send(url)
            } else {
                Log.warn("\(name) did not finish writing within 30s — skipped on 2nd screen")
            }
        }
    }

    nonisolated static func scan(_ folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .addedToDirectoryDateKey, .creationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        let jpgs: [(URL, Date)] = items.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard ext == "jpg" || ext == "jpeg" else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return nil }
            return (url, values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast)
        }
        return jpgs.sorted { a, b in
            a.1 == b.1 ? a.0.lastPathComponent < b.0.lastPathComponent : a.1 < b.1
        }.map(\.0)
    }
}
