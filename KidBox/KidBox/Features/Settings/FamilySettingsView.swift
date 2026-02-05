//
//  FamilySettingsView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData

struct FamilySettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var families: [KBFamily]
    
    private var family: KBFamily? { families.first }
    private var child: KBChild? { families.first?.children.first }
    private var hasFamily: Bool { family != nil }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                
                if hasFamily {
                    familySummaryCard
                    actionsWithFamily
                } else {
                    emptyStateCard
                    actionsWithoutFamily
                }
            }
            .padding()
        }
        .navigationTitle("Family")
    }
    
    // MARK: - UI
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Famiglia")
                .font(.title2).bold()
            Text("Qui gestisci la famiglia e inviti l’altro genitore.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
    
    /// Card riepilogo + matita (edit)
    private var familySummaryCard: some View {
        KBSettingsCard(
            title: family?.name ?? "Famiglia",
            subtitle: childSummaryText,
            systemImage: "person.2.fill",
            style: .info,
            action: nil, // card non tappabile
            trailingSystemImage: "pencil",
            trailingAction: {
                guard let family, let child else { return }
                coordinator.navigate(to: .editFamily(familyId: family.id, childId: child.id))
            }
        )
    }
    
    private var actionsWithFamily: some View {
        VStack(spacing: 12) {
            KBSettingsCard(
                title: "Invita l’altro genitore",
                subtitle: "Genera un codice e condividilo.",
                systemImage: "qrcode",
                style: .primary,
                action: {
                    coordinator.navigate(to: .inviteCode)
                }
            )
            
            KBSettingsCard(
                title: "Entra con codice",
                subtitle: "Usa un codice se vuoi unirti a un’altra famiglia.",
                systemImage: "key.fill",
                style: .secondary,
                action: {
                    coordinator.navigate(to: .joinFamily)
                }
            )
        }
    }
    
    private var emptyStateCard: some View {
        KBSettingsCard(
            title: "Nessuna famiglia configurata",
            subtitle: "Puoi crearne una nuova oppure entrare usando un codice invito.",
            systemImage: "exclamationmark.triangle",
            style: .warning,
            action: nil
        )
    }
    
    private var actionsWithoutFamily: some View {
        VStack(spacing: 12) {
            KBSettingsCard(
                title: "Crea una famiglia",
                subtitle: "Sei il primo genitore su questo account.",
                systemImage: "plus.circle.fill",
                style: .primary,
                action: {
                    coordinator.navigate(to: .setupFamily) // create
                }
            )
            
            KBSettingsCard(
                title: "Entra con codice",
                subtitle: "Se l’altro genitore ha già creato la famiglia, inserisci il codice.",
                systemImage: "key.fill",
                style: .secondary,
                action: {
                    coordinator.navigate(to: .joinFamily)
                }
            )
        }
    }
    
    private var childSummaryText: String {
        guard let child else { return "Nessun bimbo/a configurato" }
        if let birth = child.birthDate {
            return "Bimbo/a: \(child.name) • Nato/a: \(birth.formatted(date: .numeric, time: .omitted))"
        }
        return "Bimbo/a: \(child.name)"
    }
}

// MARK: - Reusable card (no dependencies)

private struct KBSettingsCard: View {
    enum Style { case primary, secondary, info, warning }
    
    let title: String
    let subtitle: String
    let systemImage: String
    let style: Style
    
    // action principale (tappare la card). Se nil, la card NON è tappabile.
    let action: (() -> Void)?
    
    // trailing action (es. matita). Se nil, non compare.
    let trailingSystemImage: String?
    let trailingAction: (() -> Void)?
    
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        style: Style,
        action: (() -> Void)? = nil,
        trailingSystemImage: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.style = style
        self.action = action
        self.trailingSystemImage = trailingSystemImage
        self.trailingAction = trailingAction
    }
    
    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }
    
    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(iconColor)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
            
            if let trailingSystemImage, let trailingAction {
                Button(action: trailingAction) {
                    Image(systemName: trailingSystemImage)
                        .font(.headline)
                        .padding(8)
                        .background(
                            Circle().fill(Color(.tertiarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modifica")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }
    
    private var iconColor: Color {
        switch style {
        case .primary: return .accentColor
        case .secondary: return .secondary
        case .info: return .blue
        case .warning: return .orange
        }
    }
    
    private var borderColor: Color {
        switch style {
        case .primary: return Color.accentColor.opacity(0.25)
        case .secondary: return Color.primary.opacity(0.08)
        case .info: return Color.blue.opacity(0.2)
        case .warning: return Color.orange.opacity(0.25)
        }
    }
}
