import Foundation
import CoreImage

/// What has been printed for each source photo (print-history.json), so reprints
/// continue the COPY numbering and the WebP is only made once.
struct PrintRecord: Codable {
    var base: String       // yyyyMMdd-HHmmss from date taken
    var suffix: String     // 2-digit random, keeps names unique within the same second
    var copies: Int
    var webp: String?
}

@MainActor
final class PrintService: ObservableObject {
    weak var app: AppState?

    @Published private(set) var busy = false
    @Published private(set) var status = ""

    private var history: [String: PrintRecord] = [:]
    private var historyURL: URL?

    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    func loadHistory(_ url: URL) {
        historyURL = url
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            history = try JSONDecoder().decode([String: PrintRecord].self, from: data)
            Log.info("Print history loaded: \(history.count) photo(s)")
        } catch {
            Log.warn("print-history.json unreadable — starting fresh (\(error.localizedDescription))")
        }
    }

    private func saveHistory() {
        guard let historyURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(history).write(to: historyURL, options: .atomic)
        } catch {
            Log.error("Cannot save print-history.json: \(error.localizedDescription)")
        }
    }

    private func newRecord(for source: URL) -> PrintRecord {
        let base = Self.nameFormatter.string(from: ImageExport.dateTaken(source))
        let used = Set(history.values.filter { $0.base == base }.map(\.suffix))
        var suffix = String(Int.random(in: 10...99))
        while used.contains(suffix), used.count < 90 {
            suffix = String(Int.random(in: 10...99))
        }
        return PrintRecord(base: base, suffix: suffix, copies: 0, webp: nil)
    }

    /// Saves `copies` JPGs (1800×1200) to the hotfolder, then the 2500×1667 WebP
    /// to DIRECTORY/upload the first time this photo is printed.
    func printCopies(_ copies: Int) {
        guard let app, !busy else { return }
        guard let overlay = app.overlayCI else {
            app.showAlert(title: "Cannot print", message: "details not loaded — select an overlay first.")
            return
        }
        guard let hotfolder = app.hotfolderURL, FileManager.default.isDirectory(hotfolder) else {
            Log.error("PRINT: hotfolder not found — \(app.settings.hotfolderPath ?? "not selected")")
            app.showAlert(title: "Cannot print", message: "Hotfolder not found. Choose it with the HOTFOLDER button.")
            return
        }
        guard let source = app.library.current else {
            app.showAlert(title: "Cannot print", message: "No image loaded. Press LATEST IMAGE NAME first.")
            return
        }
        let count = max(1, min(20, copies))
        let key = source.lastPathComponent
        var record = history[key] ?? newRecord(for: source)
        let first = record.copies + 1
        record.copies += count
        history[key] = record
        saveHistory()

        let base = record.base
        let suffix = record.suffix
        let webpName = record.webp == nil ? "\(base)-\(suffix).webp" : nil
        let uploadDir = WorkPaths.upload(in: app.cameraFolderURL)
        let area = app.settings.printArea.cgRect
        let compositor = app.compositor

        busy = true
        status = "Printing \(count)× \(key)…"
        Log.info("PRINT \(count) cop\(count == 1 ? "y" : "ies") of \(key) → COPY-\(first)…\(first + count - 1)")

        Task {
            if !(await FileReady.wait(source, timeout: 10)) {
                Log.warn("\(key) may still be writing — printing anyway")
            }
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[String], Error> in
                Result { () throws -> [String] in
                    let fm = FileManager.default
                    let canvas = try compositor.composite(photo: source, overlay: overlay, area: area)
                    let jpg = try ImageExport.jpegData(compositor.render(canvas, size: Compositor.printSize))
                    var written: [String] = []
                    for n in first..<(first + count) {
                        let name = "\(base)-COPY-\(n)-\(suffix).jpg"
                        try ImageExport.writeAtomically(jpg, to: hotfolder.appendingPathComponent(name))
                        written.append(name)
                    }
                    if let webpName {
                        try fm.ensureDirectory(uploadDir)
                        let full = try compositor.render(canvas, size: Compositor.canvas)
                        let webp = try ImageExport.webpData(full, quality: 50)
                        try ImageExport.writeAtomically(webp, to: uploadDir.appendingPathComponent(webpName))
                        written.append(webpName)
                    }
                    return written
                }
            }.value
            finish(result, key: key, count: count, webpName: webpName)
        }
    }

    private func finish(_ result: Result<[String], Error>, key: String, count: Int, webpName: String?) {
        busy = false
        switch result {
        case .success(let names):
            for name in names { Log.ok("Saved \(name)") }
            if let webpName, var record = history[key] {
                record.webp = webpName
                history[key] = record
                saveHistory()
                app?.upload.syncNow()
            }
            status = "Saved \(count) cop\(count == 1 ? "y" : "ies") of \(key)"
        case .failure(let error):
            status = "Print failed: \(error.localizedDescription)"
            Log.error("PRINT failed for \(key): \(error.localizedDescription)")
            app?.showAlert(title: "Print failed", message: "\(key)\n\(error.localizedDescription)")
        }
    }
}
