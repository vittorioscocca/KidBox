//
//  NoteLiquidToolbar.swift
//  KidBox
//

import SwiftUI

struct NoteLiquidToolbar: View {
    @ObservedObject var model: RichTextToolbarModel
    let onCommand: (RichTextCommand) -> Void
    let onDismiss: () -> Void
    
    // sizes (tweak)
    private let iconSize: CGFloat = 18
    private let pillSize: CGFloat = 40
    private let radius: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 8) {
            if model.isExpanded {
                expandedPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            baseRow
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 0)
        .background(Color(.systemBackground)) // opaco => niente "gap" visivo
        .overlay(
            Rectangle().frame(height: 0.5).foregroundStyle(Color(.separator)),
            alignment: .top
        )
    }
    
    private var baseRow: some View {
        HStack(spacing: 10) {
            liquidTextPill("Aa", isOn: model.isExpanded) {
                model.isExpanded.toggle()
            }
            
            Divider().frame(height: 26)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    liquidIconPill("bold", isOn: model.isBold) { onCommand(.bold) }
                    liquidIconPill("italic", isOn: model.isItalic) { onCommand(.italic) }
                    liquidIconPill("underline", isOn: model.isUnderline) { onCommand(.underline) }
                    liquidIconPill("strikethrough", isOn: model.isStrikethrough) { onCommand(.strikethrough) }
                    
                    Divider().frame(height: 26)
                    
                    liquidIconPill("list.bullet", isOn: model.activeList == .bullet) { onCommand(.bullet) }
                    liquidIconPill("list.number", isOn: model.activeList == .number) { onCommand(.number) }
                    
                    // checklist icon bigger
                    liquidIconPill(model.activeList == .checklist ? "checkmark.circle.fill" : "checkmark.circle",
                                   isOn: model.activeList == .checklist,
                                   iconScale: 1.08) {
                        onCommand(.checklist)
                    }
                    
                    Divider().frame(height: 26)
                    
                    liquidIconPill("decrease.indent", isOn: false) { onCommand(.indentLess) }
                    liquidIconPill("increase.indent", isOn: false) { onCommand(.indentMore) }
                }
                .padding(.horizontal, 2)
            }
            
            liquidIconPill("keyboard.chevron.compact.down", isOn: false) { onDismiss() }
        }
        .frame(height: 48)
    }
    
    private var expandedPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    model.isExpanded = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Indietro")
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Formattazione")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    model.isExpanded = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    liquidChip("Intestazione") { onCommand(.h1) }
                    liquidChip("Sottointestazione") { onCommand(.h2) }
                    liquidChip("Corpo") { onCommand(.body) }
                    
                    Divider().frame(height: 26)
                    
                    liquidIconPill("list.bullet", isOn: model.activeList == .bullet) { onCommand(.bullet) }
                    liquidIconPill("list.number", isOn: model.activeList == .number) { onCommand(.number) }
                    
                    liquidIconPill(model.activeList == .checklist ? "checkmark.circle.fill" : "checkmark.circle",
                                   isOn: model.activeList == .checklist,
                                   iconScale: 1.08) {
                        onCommand(.checklist)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    
    // MARK: - Liquid components
    
    private func liquidIconPill(_ sf: String, isOn: Bool, iconScale: CGFloat = 1.0, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sf)
                .font(.system(size: iconSize * iconScale, weight: .semibold))
                .frame(width: pillSize, height: pillSize)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(
                    ZStack {
                        if isOn {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentColor)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
    
    private func liquidTextPill(_ title: String, isOn: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 48, height: pillSize)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(
                    ZStack {
                        if isOn {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentColor)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
    
    private func liquidChip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
