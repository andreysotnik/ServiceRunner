import Foundation

struct LogLine: Identifiable {
    enum Kind { case output, system }

    let id: Int
    let date: Date
    let text: String
    let kind: Kind
}

/// Keeps the most recent lines in memory and appends every line to a log file.
final class LogBuffer {
    static let capacity = 10_000

    private(set) var lines: [LogLine] = []
    private var nextID = 0
    private let fileQueue = DispatchQueue(label: "ServiceRunner.LogBuffer")
    private var fileHandle: FileHandle?
    let fileURL: URL

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        _ = try? fileHandle?.seekToEnd()
    }

    deinit {
        try? fileHandle?.close()
    }

    func append(_ text: String, kind: LogLine.Kind = .output, date: Date = Date()) {
        let clean = Self.stripANSI(text)
        lines.append(LogLine(id: nextID, date: date, text: clean, kind: kind))
        nextID += 1
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
        let prefix = kind == .system ? "[runner] " : ""
        let record = "\(Self.timeFormatter.string(from: date)) \(prefix)\(clean)\n"
        fileQueue.async { [fileHandle] in
            fileHandle?.write(Data(record.utf8))
        }
    }

    /// Clears the in-memory view; the log file is kept.
    func clear() {
        lines.removeAll()
    }

    private static let ansiRegex = try! NSRegularExpression(
        pattern: "\u{1B}(?:\\[[0-?]*[ -/]*[@-~]|\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)|[@-Z\\\\-_])"
    )

    static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return ansiRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }
}
