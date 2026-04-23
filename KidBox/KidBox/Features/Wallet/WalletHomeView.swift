//
//  WalletHomeView.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//
//  Home del Wallet: lista di biglietti renderizzati come card colorate
//  sovrapposte (stile Apple Wallet). Solo la parte superiore di ciascuna
//  card è visibile; la card in cima è completamente visibile.
//

import SwiftUI
import SwiftData

struct WalletHomeView: View {
    let familyId: String

    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var tickets: [KBWalletTicket]

    @State private var showAddSheet = false
    @State private var prefilledSharePath: String?
    @State private var prefilledShareTitle: String?

    // Costanti di layout per lo stack.
    private let cardHeight: CGFloat = 180
    private let peekHeight: CGFloat = 58     // porzione visibile delle card sottostanti
    private let stackTopPadding: CGFloat = 8
    private let stackBottomPadding: CGFloat = 24

    init(familyId: String) {
        self.familyId = familyId
        // Ordinamento: eventi più lontani nel futuro in alto (peek), eventi
        // più imminenti in basso (card fully-visible). Così appena apri il
        // Wallet vedi in primo piano il prossimo biglietto utile.
        _tickets = Query(
            filter: #Predicate<KBWalletTicket> { $0.familyId == familyId && $0.isDeleted == false },
            sort: [SortDescriptor(\KBWalletTicket.eventDate, order: .reverse),
                   SortDescriptor(\KBWalletTicket.updatedAt, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if tickets.isEmpty {
                ContentUnavailableView(
                    "Wallet vuoto",
                    systemImage: "wallet.pass",
                    description: Text("Importa un PDF di biglietto (Trenitalia, Italo, Ryanair, cinema, concerti…)")
                )
            } else {
                cardStack
            }
        }
        .navigationTitle("Wallet")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    prefilledSharePath = nil
                    prefilledShareTitle = nil
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddWalletTicketSheet(
                familyId: familyId,
                prefilledLocalPDFPath: prefilledSharePath,
                prefilledTitle: prefilledShareTitle
            ) { ticketId in
                coordinator.navigate(to: .walletTicketDetail(familyId: familyId, ticketId: ticketId))
            }
        }
        .onAppear {
            BadgeManager.shared.activeSections.insert("wallet")
            Task { @MainActor in
                BadgeManager.shared.clearWallet()
                await CountersService.shared.reset(familyId: familyId, field: .wallet)
            }
            consumePendingShareIfAny()
        }
        .onDisappear {
            BadgeManager.shared.activeSections.remove("wallet")
        }
        .onChange(of: coordinator.pendingShareWalletPDFPath) { _, newValue in
            guard let path = newValue, !path.isEmpty else { return }
            consumePendingShareIfAny()
        }
    }

    // MARK: - Stack

    private var cardStack: some View {
        ScrollView {
            // Layout: usiamo un VStack con spacing negativo così le card
            // successive si sovrappongono alla precedente lasciando visibile
            // solo `peekHeight` pt. L'ultima card (in fondo) ha tutto lo
            // spazio per la sua altezza piena.
            let overlap = cardHeight - peekHeight
            VStack(spacing: -overlap) {
                ForEach(Array(tickets.enumerated()), id: \.element.id) { index, ticket in
                    Button {
                        coordinator.navigate(to: .walletTicketDetail(familyId: familyId, ticketId: ticket.id))
                    } label: {
                        WalletTicketCardView(ticket: ticket, height: cardHeight)
                    }
                    .buttonStyle(.plain)
                    .zIndex(Double(index))
                    .accessibilityLabel(Text(accessibilityDescription(for: ticket)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, stackTopPadding)
            .padding(.bottom, stackBottomPadding)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Actions

    private func consumePendingShareIfAny() {
        guard let path = coordinator.pendingShareWalletPDFPath, !path.isEmpty else { return }
        prefilledSharePath = path
        prefilledShareTitle = coordinator.pendingShareWalletTitle
        coordinator.pendingShareWalletPDFPath = nil
        coordinator.pendingShareWalletTitle = nil
        showAddSheet = true
    }

    private func accessibilityDescription(for ticket: KBWalletTicket) -> String {
        var parts: [String] = [ticket.kind.displayName]
        if !ticket.title.isEmpty { parts.append(ticket.title) }
        if let d = ticket.eventDate {
            parts.append(d.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: ", ")
    }
}
