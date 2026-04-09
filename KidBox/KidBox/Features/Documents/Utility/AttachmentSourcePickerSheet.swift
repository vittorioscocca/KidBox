//
//  AttachmentSourcePickerSheet.swift
//  KidBox
//
//  Created by vscocca on 09/04/26.
//

import SwiftUI

struct AttachmentSourcePickerSheet: View {
    var tint: Color = Color(red: 0.6, green: 0.45, blue: 0.85)
    let onCamera:          () -> Void
    let onGallery:         () -> Void
    let onDocument:        () -> Void
    /// Opzionale: se passato mostra il bottone "Da KidBox Documenti"
    var onKidBoxDocument: (() -> Void)? = nil
    
    // Altezza dinamica: 250 base + 56 se c'è il bottone KidBox
    private var sheetHeight: CGFloat {
        onKidBoxDocument != nil ? 306 : 250
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 16)
            
            Text("Aggiungi allegato")
                .font(.subheadline.bold())
                .padding(.bottom, 16)
            
            Divider()
            
            // ── Fotocamera ────────────────────────────────────────────────
            sourceRow(
                icon: "camera.fill",
                label: "Scatta foto",
                action: onCamera
            )
            
            Divider().padding(.leading, 64)
            
            // ── Galleria ──────────────────────────────────────────────────
            sourceRow(
                icon: "photo.on.rectangle",
                label: "Scegli dalla libreria",
                action: onGallery
            )
            
            Divider().padding(.leading, 64)
            
            // ── File (iPhone) ─────────────────────────────────────────────
            sourceRow(
                icon: "doc.fill",
                label: "File del telefono",
                action: onDocument
            )
            
            // ── KidBox Documenti (opzionale) ──────────────────────────────
            if let onKidBoxDocument {
                Divider().padding(.leading, 64)
                
                sourceRow(
                    icon: "folder.fill.badge.person.crop",
                    label: "Da KidBox Documenti",
                    action: onKidBoxDocument
                )
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Row builder
    
    @ViewBuilder
    private func sourceRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
