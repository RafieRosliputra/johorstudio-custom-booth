import Foundation

enum LogLevel: String, CaseIterable {
    case info = "INFO"
    case ok = "OK"
    case warn = "WARN"
    case error = "ERROR"
}

struct LogEntry: Identifiable {
    let id: Int
    let date: Date
    let level: LogLevel
    let message: String
}

/// In-app log (LOG tab / detached window) mirrored to logs/YYYY-MM-DD.log.
/// Safe to call from any thread.
final class LogStore: ObservableObject, @unchecked Sendable {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []
    private(set) var folder: URL?

    private let io = DispatchQueue(label: "booth.log")
    private var nextID = 0
    private let maxEntries = 5000

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let lineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func configure(folder: URL) {
        io.sync {
            self.folder = folder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    func add(_ level: LogLevel, _ message: String) {
        let date = Date()
        io.async { self.write(date: date, level: level, message: message) }
        if Thread.isMainThread {
            append(date: date, level: level, message: message)
        } else {
            DispatchQueue.main.async { self.append(date: date, level: level, message: message) }
        }
    }

    private func append(date: Date, level: LogLevel, message: String) {
        nextID += 1
        entries.append(LogEntry(id: nextID, date: date, level: level, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    // Runs on `io`.
    private func write(date: Date, level: LogLevel, message: String) {
        guard let folder else { return }
        let file = folder.appendingPathComponent(dayFormatter.string(from: date) + ".log")
        let line = Data("\(lineFormatter.string(from: date)) [\(level.rawValue)] \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: file)
        }
    }
}

enum Log {
    static func info(_ message: String) { LogStore.shared.add(.info, message) }
    static func ok(_ message: String) { LogStore.shared.add(.ok, message) }
    static func warn(_ message: String) { LogStore.shared.add(.warn, message) }
    static func error(_ message: String) { LogStore.shared.add(.error, message) }
}
