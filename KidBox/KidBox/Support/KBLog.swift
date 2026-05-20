//
//  KBLog.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import OSLog

/// Centralized logging facility for KidBox.
///
/// Uses `os.Logger` with a shared subsystem and category-based loggers.
/// Logs are structured, filterable in Console.app, and privacy-aware.
///
/// - Important: Avoid logging personally identifiable information (PII).
///   Use `writeToFile: false` on kb* calls when the message contains sensitive data.
enum KBLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "it.vittorioscocca.kidbox"

    static let app = KBLoggingLogger(category: "app", subsystem: subsystem)
    static let navigation = KBLoggingLogger(category: "navigation", subsystem: subsystem)
    static let data = KBLoggingLogger(category: "data", subsystem: subsystem)
    static let persistence = KBLoggingLogger(category: "persistence", subsystem: subsystem)
    static let sync = KBLoggingLogger(category: "sync", subsystem: subsystem)
    static let home = KBLoggingLogger(category: "home", subsystem: subsystem)
    static let routine = KBLoggingLogger(category: "routine", subsystem: subsystem)
    static let calendar = KBLoggingLogger(category: "calendar", subsystem: subsystem)
    static let todo = KBLoggingLogger(category: "todo", subsystem: subsystem)
    static let auth = KBLoggingLogger(category: "auth", subsystem: subsystem)
    static let storage = KBLoggingLogger(category: "storage", subsystem: subsystem)
    static let ui = KBLoggingLogger(category: "ui", subsystem: subsystem)
    static let settings = KBLoggingLogger(category: "settings", subsystem: subsystem)
    static let crypto = KBLoggingLogger(category: "crypto", subsystem: subsystem)
    static let security = KBLoggingLogger(category: "security", subsystem: subsystem)
    static let ai = KBLoggingLogger(category: "ai", subsystem: subsystem)
}

/// Logger con categoria nota per OSLog e file di supporto.
struct KBLoggingLogger: Sendable {
    private let osLogger: Logger
    let category: String

    init(category: String, subsystem: String) {
        self.category = category
        self.osLogger = Logger(subsystem: subsystem, category: category)
    }

    nonisolated func kbDebug(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        osLogger.debug("[\(filename):\(function):\(line)] \(message)")
        if writeToFile {
            KBFileLogger.shared.append(
                level: .debug,
                category: category,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }

    nonisolated func kbInfo(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        osLogger.info("[\(filename):\(function):\(line)] \(message)")
        if writeToFile {
            KBFileLogger.shared.append(
                level: .info,
                category: category,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }

    nonisolated func kbWarning(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        osLogger.warning("[\(filename):\(function):\(line)] \(message)")
        if writeToFile {
            KBFileLogger.shared.append(
                level: .warning,
                category: category,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }

    nonisolated func kbError(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        osLogger.error("[\(filename):\(function):\(line)] \(message)")
        if writeToFile {
            KBFileLogger.shared.append(
                level: .error,
                category: category,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }

    nonisolated func kbCrash(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        osLogger.fault("[\(filename):\(function):\(line)] \(message)")
        if writeToFile {
            KBFileLogger.shared.append(
                level: .crash,
                category: category,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }
}

// MARK: - Legacy Logger extensions (redirect to app category)

extension Logger {

    nonisolated func kbDebug(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        KBLog.app.kbDebug(message, file: file, function: function, line: line, writeToFile: writeToFile)
    }

    nonisolated func kbInfo(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        KBLog.app.kbInfo(message, file: file, function: function, line: line, writeToFile: writeToFile)
    }

    nonisolated func kbWarning(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        KBLog.app.kbWarning(message, file: file, function: function, line: line, writeToFile: writeToFile)
    }

    nonisolated func kbError(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        KBLog.app.kbError(message, file: file, function: function, line: line, writeToFile: writeToFile)
    }

    nonisolated func kbCrash(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        writeToFile: Bool = true
    ) {
        KBLog.app.kbCrash(message, file: file, function: function, line: line, writeToFile: writeToFile)
    }
}
