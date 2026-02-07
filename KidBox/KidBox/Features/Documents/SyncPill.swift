//
//  SyncPill.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI

struct SyncPill: View {
    let state: KBSyncState
    let error: String?
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption2)
            
            Text(label)
                .font(.caption2).bold()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
        .accessibilityLabel(accessibilityText)
    }
    
    private var label: String {
        switch state {
        case .synced:
            return "OK"
        case .pendingUpsert, .pendingDelete:
            return "In sync"
        case .error:
            return "Errore"
        }
    }
    
    private var iconName: String {
        switch state {
        case .synced:
            return "checkmark.circle.fill"
        case .pendingUpsert, .pendingDelete:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var backgroundColor: Color {
        switch state {
        case .synced:
            return .green.opacity(0.15)
        case .pendingUpsert, .pendingDelete:
            return .orange.opacity(0.15)
        case .error:
            return .red.opacity(0.15)
        }
    }
    
    private var foregroundColor: Color {
        switch state {
        case .synced:
            return .green
        case .pendingUpsert, .pendingDelete:
            return .orange
        case .error:
            return .red
        }
    }
    
    private var accessibilityText: String {
        if state == .error, let error {
            return "Errore di sincronizzazione: \(error)"
        }
        return "Stato sincronizzazione: \(label)"
    }
}
