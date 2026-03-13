//
//  AppState.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import OSLog
import Combine

/// Global application state shared across the app.
///
/// `AppState` holds session-level information and high-level selections
/// (e.g. current family, current child).
///
/// - Note: This object does not perform navigation; it only exposes state.
///   Navigation decisions are handled by `AppCoordinator`.
final class AppState: ObservableObject {
    
    /// Current user session (authentication-related data).
    @Published var session: Session = Session()
    
    /// Currently selected family identifier.
    @Published var selectedFamilyId: String?
    
    /// Currently selected child identifier.
    @Published var selectedChildId: String?
    
    init() {
        KBLog.app.debug("AppState initialized")
    }
}
