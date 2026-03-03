//
//  NoteLiquidToolbar.swift
//  KidBox
//
//  Contiene tutta la UI della toolbar:
//    • LiquidPressStyle      – stile bottone spring
//    • NoteLiquidBarView     – barra 44pt fissa (vive in inputAccessoryView)
//    • NoteLiquidPanelView   – pannello stili flottante (aggiunto sulla window)
//

import SwiftUI

// MARK: - Press style

struct LiquidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.83 : 1.0)
            .animation(.spring(response: 0.17, dampingFraction: 0.52),
                       value: configuration.isPressed)
    }
}

// MARK: - NoteLiquidBarView  (44pt, sempre visibile sopra la tastiera)

struct NoteLiquidBarView: View {
    @ObservedObject var model: RichTextToolbarModel
    let onCommand: (RichTextCommand) -> Void
    let onDismiss: () -> Void
    
    private let btnSize: CGFloat  = 36
    private let iconSize: CGFloat = 18
    
    var body: some View {
        HStack(spacing: 0) {
            aaButton
            sep()
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    // Inline
                    icon("bold",          on: model.isBold)          { onCommand(.bold) }
                    icon("italic",        on: model.isItalic)        { onCommand(.italic) }
                    icon("underline",     on: model.isUnderline)     { onCommand(.underline) }
                    icon("strikethrough", on: model.isStrikethrough) { onCommand(.strikethrough) }
                    sep()
                    // Liste (mutuamente esclusive)
                    icon("list.bullet",
                         on: model.activeList == .bullet)   { onCommand(.bullet) }
                    icon("list.number",
                         on: model.activeList == .number)   { onCommand(.number) }
                    icon(model.activeList == .checklist
                         ? "checkmark.circle.fill"
                         : "checkmark.circle",
                         on: model.activeList == .checklist) { onCommand(.checklist) }
                    sep()
                    // Indentazione
                    icon("decrease.indent", on: false) { onCommand(.indentLess) }
                    icon("increase.indent", on: false) { onCommand(.indentMore) }
                }
                .padding(.horizontal, 4)
            }
            
            sep()
            
            // Chiudi tastiera
            Button(action: onDismiss) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: btnSize, height: btnSize)
            }
            .buttonStyle(LiquidPressStyle())
            .padding(.trailing, 6)
        }
        .frame(height: 44)
        .padding(.leading, 6)
        .background(Color.clear)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.09))
                .frame(height: 0.33)
        }
    }
    
    // MARK: Aa button
    
    private var aaButton: some View {
        Button { model.isExpanded.toggle() } label: {
            Text("Aa")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(model.isExpanded
                                 ? Color.accentColor
                                 : Color.primary.opacity(0.80))
                .frame(width: 46, height: btnSize)
                .background {
                    if model.isExpanded {
                        Capsule().fill(Color.accentColor.opacity(0.13))
                    }
                }
        }
        .buttonStyle(LiquidPressStyle())
        .padding(.horizontal, 2)
    }
    
    // MARK: Helpers
    
    private func icon(_ sf: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sf)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(on ? Color.accentColor : Color.primary.opacity(0.72))
                .frame(width: btnSize, height: btnSize)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.13))
                    }
                }
        }
        .buttonStyle(LiquidPressStyle())
    }
    
    private func sep() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 0.33, height: 18)
            .padding(.horizontal, 4)
    }
}

// MARK: - NoteLiquidPanelView  (flottante sulla window, sopra la tastiera)

struct NoteLiquidPanelView: View {
    @ObservedObject var model: RichTextToolbarModel
    let onCommand: (RichTextCommand) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            // Header
            HStack {
                Text("Stile testo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .kerning(0.7)
                Spacer()
                Button { model.isExpanded = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Card stili
            HStack(spacing: 8) {
                styleCard("T", "Intestazione", .bold,     22) { onCommand(.heading) }
                styleCard("T", "Sottoint.",    .semibold, 17) { onCommand(.subheading) }
                styleCard("T", "Corpo",        .regular,  14) { onCommand(.body) }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), Color.primary.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.13), radius: 16, x: 0, y: 4)
    }
    
    private func styleCard(_ preview: String, _ label: String,
                           _ weight: Font.Weight, _ size: CGFloat,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(preview)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(Color.primary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
        }
        .buttonStyle(LiquidPressStyle())
    }
}
