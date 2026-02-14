//
//  SyncPill.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import OSLog

/// Visual indicator for document/category sync state.
///
/// Designed to:
/// - Remain visually stable inside grids and tight layouts
/// - Avoid compression issues
/// - Provide meaningful accessibility feedback
///
/// - Important: No logging inside `body` to avoid SwiftUI recomposition noise.
struct SyncPill: View {
    let state: KBSyncState
    let error: String?
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption2.weight(.semibold))
                .imageScale(.small)
                .frame(width: 14, height: 14)     // ✅ evita deformazioni visive
            
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor, in: Capsule()) // ✅ meglio di background+clip
        .foregroundStyle(foregroundColor)
        .fixedSize(horizontal: true, vertical: true) // ✅ NON si strizza in grid
        .layoutPriority(1)                           // ✅ vince su title/fileName
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(accessibilityHint)
    }
    
    // MARK: - Derived UI
    
    /// Short visual label shown inside the pill.
    private var label: String {
        switch state {
        case .synced: return "OK"
        case .pendingUpsert, .pendingDelete: return "Sync"
        case .error: return "Errore"
        }
    }
    
    /// SF Symbol representing current sync state.
    private var iconName: String {
        switch state {
        case .synced: return "checkmark.circle.fill"
        case .pendingUpsert, .pendingDelete: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    /// Background tint based on state.
    private var backgroundColor: Color {
        switch state {
        case .synced: return .green.opacity(0.15)
        case .pendingUpsert, .pendingDelete: return .orange.opacity(0.15)
        case .error: return .red.opacity(0.15)
        }
    }
    
    /// Foreground (text/icon) tint based on state.
    private var foregroundColor: Color {
        switch state {
        case .synced: return .green
        case .pendingUpsert, .pendingDelete: return .orange
        case .error: return .red
        }
    }
    
    // MARK: - Accessibility
    
    /// VoiceOver full description.
    private var accessibilityText: String {
        if state == .error, let error {
            return "Errore di sincronizzazione: \(error)"
        }
        return "Stato sincronizzazione: \(label)"
    }
    
    /// Additional VoiceOver hint for clarity.
    private var accessibilityHint: String {
        switch state {
        case .synced:
            return "Il documento è sincronizzato con il server."
        case .pendingUpsert, .pendingDelete:
            return "La sincronizzazione è in corso."
        case .error:
            return "La sincronizzazione non è riuscita."
        }
    }
}
