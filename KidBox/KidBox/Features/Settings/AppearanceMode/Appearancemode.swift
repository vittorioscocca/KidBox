//
//  Appearancemode.swift
//  KidBox
//
//  Created by vscocca on 13/03/26.
//

import SwiftUI

/// Preferenza tema dell'app (Chiaro / Scuro / Sistema).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case light  = "light"
    case dark   = "dark"
    case system = "system"
    
    var id: Self { self }
    
    var label: String {
        switch self {
        case .light:  return "Chiaro"
        case .dark:   return "Scuro"
        case .system: return "Sistema"
        }
    }
    
    var icon: String {
        switch self {
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
    
    /// Converte in `ColorScheme?` per `.preferredColorScheme()`.
    /// `nil` = lascia decidere a iOS.
    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}
