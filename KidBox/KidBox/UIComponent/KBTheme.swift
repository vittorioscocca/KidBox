//
//  KBTheme.swift
//  KidBox
//
//  Created by vscocca on 04/03/26.
//

import SwiftUI

struct KBTheme {
    
    // MARK: - Tint principale (viola KidBox)
    static let tint = Color(red: 0.6, green: 0.45, blue: 0.85)
    static let green = Color(red: 0.3, green: 0.65, blue: 0.45)
    
    // MARK: - Sfondo principale (specchia LoginView)
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    // MARK: - Sfondo card / sheet
    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    // MARK: - Sfondo secondario (grouped)
    static func secondaryBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color(red: 0.16, green: 0.16, blue: 0.16)
        : Color(red: 0.93, green: 0.93, blue: 0.93)
    }
    
    // MARK: - Testo primario
    static func primaryText(_ scheme: ColorScheme) -> Color { .primary }
    
    // MARK: - Testo secondario
    static func secondaryText(_ scheme: ColorScheme) -> Color { .secondary }
    
    // MARK: - Shadow
    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color.white.opacity(0.04)
        : Color.black.opacity(0.07)
    }
    
    // MARK: - Input field background
    static func inputBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color(red: 0.22, green: 0.22, blue: 0.22)
        : Color(.systemGray6)
    }
    
    // MARK: - Button primario (specchia LoginView)
    static func primaryButtonBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
    
    static func primaryButtonForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }
    
    // MARK: - Overlay scrim (loading)
    static func overlayScrim(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }
    
    // MARK: - Separatore
    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }
}
