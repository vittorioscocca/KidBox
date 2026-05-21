//
//  KBFileLogger.swift
//  KidBox
//

import Foundation

/// Persistenza su file dei log KidBox (complementare a OSLog).
final class KBFileLogger: @unchecked Sendable {

    static let shared = KBFileLogger()

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case crash = "CRASH"
    }

    private let queue = DispatchQueue(label: "it.vittorioscocca.kidbox.filelogger", qos: .utility)
    private let syncIOLock = NSLock()
    private let maxFileBytes = 500 * 1024
    private let retentionDays = 3

    private lazy var logFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("KidBox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("kidbox_log.txt")
    }()

    private let lineDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private let parseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private init() {}

    // MARK: - Public API

    func performStartupMaintenance() {
        warmUpForCrashLogging()
        queue.async { [self] in
            self.rotateAndTrimLocked()
        }
    }

    /// Inizializza path e directory prima degli handler di crash.
    func warmUpForCrashLogging() {
        syncIOLock.lock()
        defer { syncIOLock.unlock() }
        _ = logFileURL
    }

    /// Scrittura sincrona e bloccante (handler segnali / fine processo).
    func appendSync(_ line: String) {
        let sanitized = sanitizeMessage(line)
        guard !sanitized.isEmpty else { return }
        syncIOLock.lock()
        defer { syncIOLock.unlock() }
        appendLineLocked(sanitized)
    }

    func append(
        level: Level,
        category: String,
        message: String,
        file: String,
        function: String,
        line: Int
    ) {
        let sanitized = sanitizeMessage(message)
        guard !sanitized.isEmpty else { return }

        queue.async { [self] in
            let line = self.formatLine(
                level: level,
                category: category,
                message: sanitized,
                file: file,
                function: function,
                line: line
            )
            self.appendLineLocked(line)
            self.enforceMaxSizeLocked()
        }
    }

    /// Attende il completamento delle scritture in coda (es. prima di un crash di test).
    func flush() {
        queue.sync { }
    }

    func readLogs() -> String {
        queue.sync {
            guard let data = try? Data(contentsOf: logFileURL),
                  let text = String(data: data, encoding: .utf8) else {
                return ""
            }
            return text
        }
    }

    func clearLogs() {
        queue.sync {
            try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }

    func fileSize() -> Int {
        queue.sync {
            (try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int) ?? 0
        }
    }

    // MARK: - Formatting

    private func formatLine(
        level: Level,
        category: String,
        message: String,
        file: String,
        function: String,
        line: Int
    ) -> String {
        let timestamp = lineDateFormatter.string(from: Date())
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        let location = "[\(filename):\(function):\(line)]"
        return "[\(timestamp)] [\(level.rawValue)] [\(category)] \(location) \(message)"
    }

    private func sanitizeMessage(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - File IO

    private func appendLineLocked(_ line: String) {
        let payload = line + "\n"
        guard let data = payload.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    private func rotateAndTrimLocked() {
        guard FileManager.default.fileExists(atPath: logFileURL.path),
              let raw = try? String(contentsOf: logFileURL, encoding: .utf8),
              !raw.isEmpty else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast
        var kept = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                guard let date = parseTimestamp(from: String(line)) else { return true }
                return date >= cutoff
            }
            .map(String.init)

        kept = trimLinesToMaxBytes(kept)
        let output = kept.joined(separator: "\n")
        let final = output.isEmpty ? "" : output + "\n"
        try? final.write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    private func enforceMaxSizeLocked() {
        guard let raw = try? String(contentsOf: logFileURL, encoding: .utf8), !raw.isEmpty else { return }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let trimmed = trimLinesToMaxBytes(lines)
        if trimmed.count == lines.count { return }
        let output = trimmed.joined(separator: "\n")
        let final = output.isEmpty ? "" : output + "\n"
        try? final.write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    private func trimLinesToMaxBytes(_ lines: [String]) -> [String] {
        var result = lines
        while !result.isEmpty {
            let joined = result.joined(separator: "\n") + "\n"
            if joined.utf8.count <= maxFileBytes { break }
            result.removeFirst()
        }
        return result
    }

    private func parseTimestamp(from line: String) -> Date? {
        guard line.first == "[",
              let end = line.firstIndex(of: "]") else { return nil }
        let stamp = line[line.index(after: line.startIndex)..<end]
        return parseDateFormatter.date(from: String(stamp))
    }
}
