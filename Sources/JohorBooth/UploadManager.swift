import Foundation
import AppKit

/// Syncs DIRECTORY/upload/*.webp to the mounted TrueNAS folder.
/// Not on TrueNAS yet → copy, then move to upload/DONE. Already there → move to DONE.
/// Any connection problem turns UPLOAD off with a popup; printing is unaffected.
@MainActor
final class UploadManager: ObservableObject {
    weak var app: AppState?

    @Published private(set) var enabled = false
    @Published private(set) var checking = false
    @Published private(set) var status = "Off"
    @Published private(set) var pending = 0
    @Published private(set) var done = 0
    @Published private(set) var lastSync: Date?
    /// Set when TrueNAS comes back after a failure; the user re-ticks UPLOAD.
    @Published private(set) var recovered = false
    /// True as soon as a connection test succeeds, independent of autosync.
    @Published private(set) var connected = false
    /// Live upload throughput for the status line under the SYNC button.
    @Published private(set) var bytesPerSecond: Double = 0
    @Published private(set) var filesDone = 0
    @Published private(set) var filesTotal = 0
    @Published private(set) var syncingNow = false

    private var syncTimer: Timer?
    private var reconnectTimer: Timer?
    private var syncing = false
    private var syncQueued = false
    private var reconnectTesting = false

    var remoteURL: URL? {
        app?.settings.truenasPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Files that still have to reach TrueNAS: WebPs waiting in the upload folder
    /// plus livefolder photos that have not been composited into a WebP yet.
    var remaining: Int {
        pending + (app?.printer.unsynced ?? 0)
    }

    var speedText: String? {
        guard bytesPerSecond > 1 else { return nil }
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        }
        return String(format: "%.0f KB/s", bytesPerSecond / 1024)
    }

    /// One control: grey → connect, green → autosync off, green pulsing → autosync on.
    func toggle() {
        if enabled {
            userToggled(false)
        } else {
            Task { await enable() }
        }
    }

    // MARK: - Lifecycle

    func startup() {
        refreshCounts()
        guard let app else { return }
        if app.settings.uploadEnabled {
            Log.info("UPLOAD was ON last time — checking TrueNAS…")
            Task { await enable() }
        } else if let remote = remoteURL {
            Task {
                if let err = await Self.test(remote) {
                    connected = false
                    Log.warn("TrueNAS not reachable (UPLOAD is off): \(err)")
                    status = "Off — not reachable"
                } else {
                    connected = true
                    Log.ok("TrueNAS reachable: \(remote.path) (UPLOAD is off)")
                    status = "Off — reachable"
                }
            }
        } else {
            Log.info("TrueNAS folder not selected yet (UPLOAD tab)")
        }
    }

    func userToggled(_ on: Bool) {
        if on {
            Task { await enable() }
        } else {
            enabled = false
            stopSyncTimer()
            app?.settings.uploadEnabled = false
            status = "Off"
            Log.info("AUTOSYNC turned OFF")
        }
    }

    func enable() async {
        guard let app else { return }
        guard let remote = remoteURL else {
            fail("Choose the TrueNAS folder in the UPLOAD tab first.")
            return
        }
        checking = true
        status = "Checking connection…"
        Log.info("Checking TrueNAS connection: \(remote.path)")
        let err = await Self.test(remote)
        checking = false
        if let err {
            fail(err)
            return
        }
        enabled = true
        connected = true
        recovered = false
        stopReconnectWatch()
        app.settings.uploadEnabled = true
        status = "Connected"
        Log.ok("TrueNAS connected — AUTOSYNC ON")
        startSyncTimer()
        // Backfill: photos already in the livefolder but never composited.
        app.printer.prepareAllMissing()
        syncNow()
    }

    private func fail(_ reason: String) {
        enabled = false
        connected = false
        checking = false
        bytesPerSecond = 0
        syncingNow = false
        stopSyncTimer()
        app?.settings.uploadEnabled = false
        status = "Not connected"
        Log.error("UPLOAD turned OFF: \(reason)")
        app?.showAlert(
            title: "TrueNAS not connected",
            message: "\(reason)\n\nUPLOAD has been turned OFF. Printing still works — WebP files wait in the upload folder and sync when you tick UPLOAD again."
        )
        if remoteURL != nil { startReconnectWatch() }
    }

    // MARK: - Folder & manual test

    func chooseFolder() {
        guard let app else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose the mounted TrueNAS folder for uploads"
        panel.directoryURL = remoteURL ?? URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.settings.truenasPath = url.path
        Log.info("TrueNAS folder set: \(url.path)")
        if enabled {
            Task { await enable() }
        } else {
            testNow()
        }
    }

    func testNow() {
        guard let remote = remoteURL else { return }
        status = "Checking connection…"
        Task {
            if let err = await Self.test(remote) {
                if enabled {
                    fail(err)
                } else {
                    status = "Off — not reachable"
                    Log.error("TrueNAS test failed: \(err)")
                    app?.showAlert(title: "TrueNAS not connected", message: err)
                }
            } else {
                connected = true
                status = enabled ? "Connected" : "Off — reachable"
                Log.ok("TrueNAS test OK: \(remote.path)")
            }
        }
    }

    // MARK: - Sync

    func syncNow() {
        guard enabled, let app, let remote = remoteURL else {
            refreshCounts()
            return
        }
        if syncing {
            syncQueued = true
            return
        }
        syncing = true
        syncingNow = true
        status = "Syncing…"
        bytesPerSecond = 0
        filesDone = 0
        filesTotal = 0
        let local = WorkPaths.upload(in: app.cameraFolderURL)
        let doneDir = WorkPaths.done(in: app.cameraFolderURL)
        let started = Date()
        Task {
            let report = await Task.detached(priority: .utility) { [weak self] in
                UploadManager.syncOnce(local: local, done: doneDir, remote: remote) { done, total, bytes in
                    let elapsed = Date().timeIntervalSince(started)
                    Task { @MainActor in
                        guard let self else { return }
                        self.filesDone = done
                        self.filesTotal = total
                        self.bytesPerSecond = elapsed > 0.2 ? Double(bytes) / elapsed : 0
                    }
                }
            }.value
            syncing = false
            syncingNow = false
            bytesPerSecond = 0
            lastSync = Date()
            refreshCounts()
            guard enabled else { return }
            if let fatal = report.fatal {
                fail(fatal)
                return
            }
            if report.uploaded + report.alreadyThere > 0 {
                Log.ok("Sync: \(report.uploaded) uploaded, \(report.alreadyThere) already on TrueNAS — moved to DONE")
            }
            status = report.failed == 0 ? "Connected — in sync" : "Connected — \(report.failed) file(s) failed, will retry"
            if syncQueued {
                syncQueued = false
                syncNow()
            }
        }
    }

    func refreshCounts() {
        guard let app else { return }
        pending = Self.webpCount(in: WorkPaths.upload(in: app.cameraFolderURL))
        done = Self.webpCount(in: WorkPaths.done(in: app.cameraFolderURL))
    }

    private func startSyncTimer() {
        stopSyncTimer()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
    }

    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func startReconnectWatch() {
        stopReconnectWatch()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reconnectTick() }
        }
    }

    private func stopReconnectWatch() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    private func reconnectTick() async {
        guard !enabled, !reconnectTesting, let remote = remoteURL else { return }
        reconnectTesting = true
        let err = await Self.test(remote)
        reconnectTesting = false
        if err == nil, !enabled {
            connected = true
            recovered = true
            status = "Off — reachable again"
            stopReconnectWatch()
            Log.ok("TrueNAS is reachable again — tick UPLOAD to resume syncing")
        }
    }

    // MARK: - Background work

    struct SyncReport {
        var uploaded = 0
        var alreadyThere = 0
        var failed = 0
        var bytes: Int64 = 0
        var fatal: String?
    }

    nonisolated static func syncOnce(
        local: URL,
        done: URL,
        remote: URL,
        progress: (@Sendable (_ done: Int, _ total: Int, _ bytes: Int64) -> Void)? = nil
    ) -> SyncReport {
        var report = SyncReport()
        let fm = FileManager.default
        guard fm.isDirectory(remote) else {
            report.fatal = "TrueNAS folder disappeared: \(remote.path)"
            return report
        }
        let remoteNames: Set<String>
        do {
            remoteNames = Set(try fm.contentsOfDirectory(atPath: remote.path))
        } catch {
            report.fatal = "Cannot list TrueNAS folder: \(error.localizedDescription)"
            return report
        }
        try? fm.ensureDirectory(done)
        let files = webpFiles(in: local)
        progress?(0, files.count, 0)
        for file in files {
            let name = file.lastPathComponent
            let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            do {
                if remoteNames.contains(name) {
                    report.alreadyThere += 1
                } else {
                    let tmp = remote.appendingPathComponent(".\(name).uploading")
                    try? fm.removeItem(at: tmp)
                    try fm.copyItem(at: file, to: tmp)
                    try fm.moveItem(at: tmp, to: remote.appendingPathComponent(name))
                    report.uploaded += 1
                    report.bytes += size
                    Log.ok("Uploaded \(name)")
                }
                let target = done.appendingPathComponent(name)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.moveItem(at: file, to: target)
                progress?(report.uploaded + report.alreadyThere + report.failed, files.count, report.bytes)
            } catch {
                if !fm.isDirectory(remote) {
                    report.fatal = "Lost connection to TrueNAS while uploading \(name)"
                    return report
                }
                report.failed += 1
                Log.warn("Upload failed for \(name): \(error.localizedDescription)")
                progress?(report.uploaded + report.alreadyThere + report.failed, files.count, report.bytes)
            }
        }
        return report
    }

    nonisolated static func webpFiles(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return items.filter { $0.pathExtension.lowercased() == "webp" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    nonisolated static func webpCount(in folder: URL) -> Int { webpFiles(in: folder).count }

    /// Returns nil when the folder is mounted and writable. Network mounts can hang,
    /// so the check gives up after `timeout` seconds.
    nonisolated static func test(_ remote: URL, timeout: TimeInterval = 6) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let gate = OnceGate()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = testSync(remote)
                if gate.claim() { cont.resume(returning: result) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if gate.claim() { cont.resume(returning: "No response from \(remote.path) after \(Int(timeout))s") }
            }
        }
    }

    nonisolated static func testSync(_ remote: URL) -> String? {
        let fm = FileManager.default
        guard fm.isDirectory(remote) else {
            return "Folder not found: \(remote.path) — is the TrueNAS share mounted?"
        }
        if remote.path.hasPrefix("/Volumes/"),
           let values = try? remote.resourceValues(forKeys: [.volumeIsRootFileSystemKey]),
           values.volumeIsRootFileSystem == true {
            return "\(remote.path) is on this Mac's own disk, not on the TrueNAS share (share not mounted)."
        }
        if let err = fm.probeWrite(in: remote) {
            return "Cannot write to \(remote.path): \(err)"
        }
        return nil
    }
}

final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
