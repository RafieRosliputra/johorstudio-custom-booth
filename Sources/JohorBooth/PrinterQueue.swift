import Foundation

struct PrinterQueueError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The default macOS printer's queue, through the CUPS command line tools.
enum PrinterQueue {
    static func defaultPrinter() -> String? {
        let out = run("/usr/bin/lpstat", ["-d"])
        guard out.status == 0, let range = out.text.range(of: "destination: ") else { return nil }
        let name = out.text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func jobCount(_ printer: String) -> Int {
        run("/usr/bin/lpstat", ["-o", printer]).text
            .split(separator: "\n")
            .filter { $0.hasPrefix(printer) }
            .count
    }

    /// Cancels and purges (-x) every job on the default printer.
    static func purgeDefault() -> Result<String, PrinterQueueError> {
        guard let printer = defaultPrinter() else {
            return .failure(PrinterQueueError(message: "No default printer. Set one in System Settings › Printers & Scanners."))
        }
        let before = jobCount(printer)
        let out = run("/usr/bin/cancel", ["-a", "-x", printer])
        guard out.status == 0 else {
            let detail = out.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(PrinterQueueError(message: "Could not purge \(printer): \(detail.isEmpty ? "cancel exited with \(out.status)" : detail)"))
        }
        let left = jobCount(printer)
        if left > 0 {
            return .failure(PrinterQueueError(message: "\(printer): \(left) job(s) still in the queue after purge."))
        }
        return .success("Removed \(before) job(s) from \(printer)")
    }

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
