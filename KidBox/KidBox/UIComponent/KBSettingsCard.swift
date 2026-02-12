//
//   KBSettingsCard.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI

// MARK: - Base card (NO generics)

struct KBSettingsCard: View {
    enum Style { case primary, secondary, info, warning, danger}
    
    let title: String
    let subtitle: String
    let systemImage: String
    let style: Style
    
    let action: (() -> Void)?
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
        case .danger: return .red
        }
    }
    
    private var borderColor: Color {
        switch style {
        case .primary: return Color.accentColor.opacity(0.25)
        case .secondary: return Color.primary.opacity(0.08)
        case .info: return Color.blue.opacity(0.2)
        case .warning: return Color.orange.opacity(0.25)
        case .danger:  return Color.red.opacity(0.25)
        }
    }
}

// MARK: - Card with extra content (GENERIC only when needed)

struct KBSettingsCardWithExtra<ExtraContent: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let style: KBSettingsCard.Style
    let action: (() -> Void)?
    let trailingSystemImage: String?
    let trailingAction: (() -> Void)?
    let extraContent: () -> ExtraContent
    
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        style: KBSettingsCard.Style,
        action: (() -> Void)? = nil,
        trailingSystemImage: String? = nil,
        trailingAction: (() -> Void)? = nil,
        @ViewBuilder extraContent: @escaping () -> ExtraContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.style = style
        self.action = action
        self.trailingSystemImage = trailingSystemImage
        self.trailingAction = trailingAction
        self.extraContent = extraContent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KBSettingsCard(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                style: style,
                action: action,
                trailingSystemImage: trailingSystemImage,
                trailingAction: trailingAction
            )
            
            // extra section inside the same “visual group”
            extraContent()
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
