//
//  PushPrimingView.swift
//  KidBox
//
//  Schermata di "priming" del permesso notifiche, mostrata una sola volta al
//  primo accesso (utente autenticato con una famiglia).
//
//  Perché una schermata NOSTRA prima di quella di sistema: la richiesta di
//  sistema iOS si può mostrare una volta sola per installazione. Se l'utente
//  nega di getto, non è più possibile richiederla — resta solo il rimando alle
//  Impostazioni di sistema, che quasi nessuno percorre. Spiegare prima *perché*
//  servono, e far partire la richiesta di sistema solo su "Attiva", alza il
//  tasso di sì e non brucia quell'unica occasione su un no impulsivo.
//

import SwiftUI

struct PushPrimingView: View {

    /// `true` = l'utente ha toccato "Attiva" (parte la richiesta di sistema),
    /// `false` = "Non ora". In entrambi i casi la schermata non si ripresenta.
    let onDecision: (Bool) -> Void

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

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(KBTheme.bubbleTint)
                .padding(.bottom, 24)

            Text("Resta aggiornato con la famiglia")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("Ti avvisiamo quando un membro carica un documento, aggiunge una spesa, scrive in chat o si avvicina una scadenza. Puoi scegliere quali notifiche ricevere in qualsiasi momento dalle Impostazioni.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onDecision(true)
                } label: {
                    Text("Attiva le notifiche")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(KBTheme.bubbleTint)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onDecision(false)
                } label: {
                    Text("Non ora")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor.ignoresSafeArea())
    }
}
