//
//  WalletTicketCardView.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//
//  Card visiva del biglietto, stile Apple Wallet: gradient per kind,
//  testo bianco, data prominente. Usata sia nello stack della WalletHomeView
//  (sovrapposte con offset verticale) sia come header del dettaglio.
//

import SwiftUI

struct WalletTicketCardView: View {
    let ticket: KBWalletTicket

    /// Altezza "nominale" della card. In modalità stack, la home mostra solo
    /// la porzione superiore (~90pt) per le card non in cima — questo valore
    /// definisce invece la forma completa quando è in cima / in dettaglio.
    var height: CGFloat = 205

    var body: some View {
        ZStack(alignment: .topLeading) {
            gradient

            // Pattern decorativo leggero (cerchi sfumati) per dare profondità
            // senza distrarre. Solo il 6% di opacità.
            decorativePattern
                .blendMode(.overlay)
                .opacity(0.6)

            VStack(alignment: .leading, spacing: 10) {
                header
                Spacer(minLength: 6)
                footer
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: ticket.kind.accentColorSecondary.opacity(0.35), radius: 10, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Pieces

    private var gradient: some View {
        LinearGradient(
            colors: [ticket.kind.accentColor, ticket.kind.accentColorSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var decorativePattern: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: geo.size.width * 0.9)
                    .offset(x: geo.size.width * 0.45, y: -geo.size.width * 0.25)
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: -geo.size.width * 0.2, y: geo.size.height * 0.7)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: WalletEmitterIcon.icon(for: ticket.emitter, kind: ticket.kind))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(Color.white.opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(categoryLabel.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.85))

                Text(ticket.title.isEmpty ? "Biglietto" : ticket.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
    }

    /// In alto a sinistra mostriamo "TRENITALIA • TRENO" se abbiamo l'emittente,
    /// altrimenti solo "TRENO". Testo corto (<~24 char) per non andare a capo.
    private var categoryLabel: String {
        if let emitter = ticket.emitter?.trimmingCharacters(in: .whitespacesAndNewlines),
           !emitter.isEmpty {
            return "\(emitter) • \(ticket.kind.displayName)"
        }
        return ticket.kind.displayName
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if let eventDate = ticket.eventDate {
                    Text(localizedTicketDay(eventDate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(localizedTicketTime(eventDate))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                } else if let location = ticket.location, !location.isEmpty {
                    Text(location)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()

            if let bookingCode = ticket.bookingCode, !bookingCode.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("CODICE")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(bookingCode)
                        .font(.system(.footnote, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
    }

    private func localizedTicketDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.calendar = kbDeviceCalendar()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: date)
    }

    private func localizedTicketTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.calendar = kbDeviceCalendar()
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter.string(from: date)
    }
}
