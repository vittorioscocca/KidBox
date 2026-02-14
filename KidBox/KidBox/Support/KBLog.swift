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
///   Use `.private` when logging user-generated data.
enum KBLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "it.vittorioscocca.kidbox"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let navigation = Logger(subsystem: subsystem, category: "navigation")
    static let data = Logger(subsystem: subsystem, category: "data")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let home = Logger(subsystem: subsystem, category: "home")
    static let routine = Logger(subsystem: subsystem, category: "routine")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let todo = Logger(subsystem: subsystem, category: "todo")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let crypto = Logger(subsystem: subsystem, category: "crypto")
    static let security = Logger(subsystem: subsystem, category: "security")
    
}

import OSLog

extension Logger {
    
    nonisolated func kbDebug(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        self.debug("[\(filename):\(function):\(line)] \(message)")
    }
    
    nonisolated func kbInfo(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        self.info("[\(filename):\(function):\(line)] \(message)")
    }
    
    nonisolated func kbError(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        self.error("[\(filename):\(function):\(line)] \(message)")
    }
}
