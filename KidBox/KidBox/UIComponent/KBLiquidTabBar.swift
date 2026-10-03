//
//  KBLiquidTabBar.swift
//  KidBox
//
//  La barra in basso: Home · assistente AI · Notizie, in vetro liquido (iOS 26).
//  Home e Notizie sono le due radici dell'app; il cerchio al centro, un po' più
//  grande, non è una scheda ma un'azione: apre l'assistente (centrato sulla
//  persona, la visita o l'esame quando si è in Salute — vedi RootHostView).
//
//  Stesso disegno su Android in `ui/components/KidBoxBottomBar.kt`, dove la
//  barra ha il fondo della barra di sistema invece del vetro.
//
//  Solo SwiftUI: si prova da sola in un'app-banco (memoria «Verifica UI iOS»).
//

import SwiftUI

/// Le due radici della barra. L'assistente non è una radice: si apre sopra.
enum KBRootTab: String, Hashable {
    case home
    case news
}

struct KBLiquidTabBar: View {

    let selected: KBRootTab
    let onSelect: (KBRootTab) -> Void
    let onAssistant: () -> Void

    @Namespace private var selection

    /// Il cerchio dell'assistente sporge sopra e sotto la capsula.
    private let barHeight: CGFloat = 62
    private let assistantSize: CGFloat = 70

    var body: some View {
        ZStack {
            // Solo la capsula è vetro. Il cerchio dell'assistente sta fuori dal
            // contenitore: dentro, i due vetri si fondevano in una macchia
            // arancione dai bordi sfrangiati (visto nel banco il 03/10/2026).
            GlassEffectContainer {
                HStack(spacing: 0) {
                    tabButton(.home, title: "Home", symbol: "house", selectedSymbol: "house.fill")
                    Color.clear.frame(width: assistantSize + 10)
                    tabButton(.news, title: "Notizie", symbol: "newspaper", selectedSymbol: "newspaper.fill")
                }
                .padding(.horizontal, 6)
                .frame(height: barHeight)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            assistantButton
                .offset(y: -6)
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 24)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
    }

    // MARK: - Schede

    private func tabButton(_ tab: KBRootTab, title: LocalizedStringKey, symbol: String, selectedSymbol: String) -> some View {
        let isSelected = selected == tab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? selectedSymbol : symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? KBTheme.bubbleTint : Color.primary.opacity(0.75))
            .frame(maxWidth: .infinity)
            .frame(height: barHeight - 12)
            .background {
                if isSelected {
                    Capsule()
                        .fill(KBTheme.bubbleTint.opacity(0.14))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Assistente

    private var assistantButton: some View {
        Button(action: onAssistant) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: assistantSize - 16, height: assistantSize - 16)
        }
        // Il vetro «prominente» di sistema: pieno del colore dell'assistente,
        // con i riflessi e la risposta al tocco del vetro liquido.
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(KBTheme.aiFabOrange)
        .shadow(color: KBTheme.aiFabOrange.opacity(0.30), radius: 10, y: 4)
        .accessibilityLabel(Text("Assistente AI"))
        .accessibilityHint(Text("Apre l'assistente di famiglia"))
    }
}

#Preview {
    struct Demo: View {
        @State var tab: KBRootTab = .home
        var body: some View {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [.orange.opacity(0.3), .blue.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                KBLiquidTabBar(selected: tab, onSelect: { tab = $0 }, onAssistant: {})
                    .padding(.bottom, 8)
            }
        }
    }
    return Demo()
}
