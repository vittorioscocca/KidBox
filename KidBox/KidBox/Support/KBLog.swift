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
}
