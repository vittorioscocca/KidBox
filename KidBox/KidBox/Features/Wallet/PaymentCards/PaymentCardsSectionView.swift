//
//  PaymentCardsSectionView.swift
//  KidBox
//
//  Created by vscocca on 03/10/26.
//
//  Sezione «Pagamento» del Wallet: le carte di credito, debito e prepagate
//  inserite a mano, una sotto l'altra.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PaymentCardsSectionView: View {
    let familyId: String

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var cards: [KBPaymentCard]

    @State private var showAddSheet = false

    init(familyId: String) {
        self.familyId = familyId
        _cards = Query(
            filter: #Predicate<KBPaymentCard> { $0.familyId == familyId && $0.isDeleted == false },
            sort: [SortDescriptor(\KBPaymentCard.createdAt, order: .reverse)]
        )
    }

    private var visibleCards: [(card: KBPaymentCard, plain: PaymentCardPlain)] {
        let uid = Auth.auth().currentUser?.uid
        return cards
            .filter { $0.isVisible(to: uid) }
            .map { ($0, PaymentCardPlain(card: $0, userId: uid)) }
    }

    var body: some View {
        let items = visibleCards
        Group {
            if items.isEmpty {
                KBEmptyStateView(
                    systemImage: "creditcard.and.123",
                    title: "Nessuna carta di pagamento",
                    message: "Salva numero, intestatario, scadenza e IBAN delle carte di famiglia, con la foto di fronte e retro. Tutto cifrato end-to-end, mai letto dall'AI. Non serve, e non va salvato, il CVV.",
                    actionTitle: "Aggiungi carta",
                    actionSystemImage: "plus.circle.fill",
                    action: { showAddSheet = true }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(items, id: \.card.id) { item in
                            Button {
                                coordinator.navigate(to: .paymentCardDetail(familyId: familyId, cardId: item.card.id))
                            } label: {
                                PaymentCardTileView(plain: item.plain, colorHex: item.card.colorHex)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(item.plain.displayTitle))
                        }
                    }
                    .padding(16)
                }
                .kbRefreshable {
                    await SyncCenter.shared.forceRefresh(modelContext: modelContext) {
                        SyncCenter.shared.stopPaymentCardsRealtime()
                        SyncCenter.shared.startPaymentCardsRealtime(familyId: familyId, modelContext: modelContext)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Aggiungi carta"))
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PaymentCardFormView(familyId: familyId, card: nil) { cardId in
                showAddSheet = false
                coordinator.navigate(to: .paymentCardDetail(familyId: familyId, cardId: cardId))
            }
        }
    }
}
