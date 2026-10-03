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
    /// Compatta mentre si scorre per leggere oltre (`KBTabBarScrollObserver`).
    var isMinimized: Bool = false
    let onSelect: (KBRootTab) -> Void
    let onAssistant: () -> Void

    @Namespace private var selection

    /// Il cerchio dell'assistente sporge sopra e sotto la capsula.
    private var barHeight: CGFloat { isMinimized ? 46 : 62 }
    private var assistantSize: CGFloat { isMinimized ? 52 : 70 }
    private var raise: CGFloat { isMinimized ? 2 : 6 }

    /// Lo spazio che la barra occupa in basso non cambia mai: è quello della
    /// barra grande, cerchio rialzato compreso. Così rimpicciolendosi non sposta
    /// le schermate (niente salti mentre si scorre) e non può finire sopra un
    /// pulsante o un contenuto: quello che sta sopra questo spazio resta sopra.
    static let reservedHeight: CGFloat = 78

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
                .offset(y: -raise)
        }
        .frame(maxWidth: isMinimized ? 240 : 360)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: Self.reservedHeight, alignment: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isMinimized)
    }

    // MARK: - Schede

    private func tabButton(_ tab: KBRootTab, title: LocalizedStringKey, symbol: String, selectedSymbol: String) -> some View {
        let isSelected = selected == tab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? selectedSymbol : symbol)
                    .font(.system(size: isMinimized ? 18 : 20, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                // Compatta: solo le icone, come le barre di sistema ridotte.
                if !isMinimized {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
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
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Assistente

    private var assistantButton: some View {
        Button(action: onAssistant) {
            Image(systemName: "sparkles")
                .font(.system(size: isMinimized ? 21 : 26, weight: .semibold))
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
                VStack(spacing: 0) {
                    KBLiquidTabBar(selected: tab, isMinimized: true, onSelect: { tab = $0 }, onAssistant: {})
                    KBLiquidTabBar(selected: tab, onSelect: { tab = $0 }, onAssistant: {})
                }
                .padding(.bottom, 8)
            }
        }
    }
    return Demo()
}
