import Foundation

/// Folder layout around the app:
///
///     <working folder>/            e.g. Desktop/<event>/
///       johorstudio-custom-photobooth.app
///       settings.json
///       print-history.json
///       logs/
///       camera/                    DIRECTORY (default, can be changed)
///         upload/                  WebP waiting to sync to TrueNAS
///           DONE/                  WebP already on TrueNAS
///
/// The printer hotfolder is chosen with the HOTFOLDER button and can be anywhere.
struct WorkPaths {
    let root: URL

    static func detect() -> WorkPaths {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            return WorkPaths(root: bundle.deletingLastPathComponent())
        }
        // Running from `swift run` / Xcode: use the current directory.
        return WorkPaths(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
    }

    /// macOS runs quarantined apps from a random read-only location.
    var isTranslocated: Bool { root.path.contains("/AppTranslocation/") }

    var defaultCamera: URL { root.appendingPathComponent("camera", isDirectory: true) }
    var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    var settingsFile: URL { root.appendingPathComponent("settings.json") }
    var historyFile: URL { root.appendingPathComponent("print-history.json") }

    static func upload(in camera: URL) -> URL { camera.appendingPathComponent("WEBP", isDirectory: true) }
    static func original(in camera: URL) -> URL { upload(in: camera).appendingPathComponent("ORIGINAL", isDirectory: true) }
}

extension FileManager {
    func ensureDirectory(_ url: URL) throws {
        try createDirectory(at: url, withIntermediateDirectories: true)
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Writes and deletes a probe file to prove the folder is writable.
    func probeWrite(in folder: URL) -> String? {
        let probe = folder.appendingPathComponent(".johorbooth-probe-\(UUID().uuidString)")
        do {
            try Data("ok".utf8).write(to: probe)
            _ = try Data(contentsOf: probe)
            try removeItem(at: probe)
            return nil
        } catch {
            try? removeItem(at: probe)
            return error.localizedDescription
        }
    }
}

enum BoothError: LocalizedError {
    case cannotRead(String)
    case renderFailed
    case encodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotRead(let name): return "Cannot read image \(name)"
        case .renderFailed: return "Image render failed"
        case .encodeFailed(let kind): return "\(kind) encoding failed"
        }
    }
}
