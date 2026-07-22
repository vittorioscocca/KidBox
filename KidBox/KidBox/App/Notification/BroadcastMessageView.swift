//
//  BroadcastMessageView.swift
//  KidBox
//
//  View unica per gli annunci inviati dalla console admin (`sendBroadcast`).
//
//  È deliberatamente la STESSA view per ogni annuncio, senza varianti: il testo
//  della notifica è l'unico contenuto, non c'è una destinazione dentro l'app né
//  una famiglia di riferimento. Il messaggio arriva già dentro il deep link
//  (`DeepLink.broadcast`), quindi la view non fa alcuna lettura di rete — si
//  apre anche offline e anche se l'annuncio nel frattempo è stato cancellato.
//

import SwiftUI

struct BroadcastMessageView: View {

    let title: String
    /// Non si chiama `body`: in una View quel nome è già la requirement
    /// del protocollo, e il conflitto non è risolvibile.
    let message: String
    /// Etichetta del pulsante primario. `nil` = messaggio puramente
    /// informativo (il caso broadcast): resta solo "Ho capito".
    var actionTitle: String?
    /// Eseguita al tap sul pulsante primario, dopo la chiusura.
    var onAction: (() -> Void)?
    /// Eseguita quando l'utente chiude senza agire — serve a distinguere
    /// "non mi interessa" da "non l'ha nemmeno visto" nelle metriche.
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)

                    if !title.isEmpty {
                        Text(title)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // `message` è testo scritto a mano in console: niente markdown,
                    // niente HTML. Va mostrato per intero — la notifica di
                    // sistema lo tronca, questa view è il posto dove leggerlo.
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(cardBackground)
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            VStack(spacing: 8) {
                Button {
                    // L'azione parte DOPO la chiusura: navigare mentre la sheet
                    // è ancora sullo schermo lascia la destinazione coperta.
                    let action = onAction
                    dismiss()
                    if let action { action() }
                } label: {
                    Text(actionTitle ?? "Ho capito")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(KBTheme.bubbleTint)
                        )
                }
                .buttonStyle(.plain)

                if actionTitle != nil {
                    Button {
                        let onDismiss = onDismiss
                        dismiss()
                        if let onDismiss { onDismiss() }
                    } label: {
                        Text("Non ora")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(backgroundColor)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("KidBox")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.bold())
                        }
                    }
                }
        }
    }
}

/// Wrapper `Identifiable` per la presentazione via `.sheet(item:)`.
///
/// Usato sia dagli annunci della console (`destination` nil) sia dai nudge
/// (`destination` valorizzata). La view è deliberatamente la stessa: per
/// l'utente sono lo stesso oggetto — un messaggio da KidBox — e differenziarli
/// visivamente non aggiungerebbe informazione.
struct BroadcastMessage: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    /// Campagna di origine, se è un nudge. Serve solo alle metriche.
    var campaignId: String?
    var destination: NudgeDestination?
}
