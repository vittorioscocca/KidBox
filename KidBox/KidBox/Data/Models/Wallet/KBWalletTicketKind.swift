//
//  KBWalletTicketKind.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation
import SwiftUI

/// Categoria del biglietto custodito nel Wallet di KidBox.
///
/// Usata per:
/// - icona/colore della card
/// - euristiche del `WalletPDFParser` (riconoscimento emittente)
/// - default smart del `WalletReminderService`
enum KBWalletTicketKind: String, Codable, CaseIterable, Hashable {
    case train      // Trenitalia, Italo, Trenord, Tper, ecc.
    case flight     // Ryanair, ITA, easyJet, Lufthansa, ecc.
    case ferry      // Moby, Tirrenia, GNV, Grimaldi, Corsica, ecc.
    case bus        // Flixbus, Itabus, Marino, Baltour, ecc.
    case concert    // TicketOne, Vivaticket, DICE, Live Nation, ecc.
    case cinema     // UCI, The Space, Cinelandia, ecc.
    case parking    // Telepass, EasyPark, SABA, MyCicero, ecc.
    case museum     // Uffizi, MAXXI, GetYourGuide, Musement, ecc.
    case other

    /// `String` (non `LocalizedStringKey`): usato in confronti (`title == kind.displayName`),
    /// notifiche (`UNMutableNotificationContent.title/body`) e `.uppercased()`,
    /// quindi passa da NSLocalizedString invece che da LocalizedStringKey.
    var displayName: String {
        switch self {
        case .train:    return NSLocalizedString("Treno", comment: "Ticket kind: train")
        case .flight:   return NSLocalizedString("Volo", comment: "Ticket kind: flight")
        case .ferry:    return NSLocalizedString("Traghetto", comment: "Ticket kind: ferry")
        case .bus:      return NSLocalizedString("Autobus", comment: "Ticket kind: bus")
        case .concert:  return NSLocalizedString("Concerto", comment: "Ticket kind: concert")
        case .cinema:   return NSLocalizedString("Cinema", comment: "Ticket kind: cinema")
        case .parking:  return NSLocalizedString("Parcheggio", comment: "Ticket kind: parking")
        case .museum:   return NSLocalizedString("Museo / Mostra", comment: "Ticket kind: museum")
        case .other:    return NSLocalizedString("Biglietto", comment: "Ticket kind: other")
        }
    }

    /// Icona di default per la categoria. Può essere sovrascritta dall'emittente
    /// via `WalletEmitterIcon.icon(for:kind:)` — es. un biglietto `.flight` di
    /// Ryanair può mostrare l'icona `airplane.departure` invece della generica.
    var systemImage: String {
        switch self {
        case .train:    return "tram.fill"
        case .flight:   return "airplane"
        case .ferry:    return "ferry.fill"
        case .bus:      return "bus.fill"
        case .concert:  return "music.note"
        case .cinema:   return "ticket.fill"
        case .parking:  return "parkingsign.circle.fill"
        case .museum:   return "building.columns.fill"
        case .other:    return "wallet.pass.fill"
        }
    }

    /// Colore accent per la card del biglietto (gradient top).
    /// Pensato per contrastare testo bianco e mantenere leggibilità.
    var accentColor: Color {
        switch self {
        case .train:    return Color(red: 0.16, green: 0.49, blue: 0.78)  // blu ferroviario
        case .flight:   return Color(red: 0.10, green: 0.33, blue: 0.55)  // blu notte
        case .ferry:    return Color(red: 0.00, green: 0.52, blue: 0.68)  // azzurro mare
        case .bus:      return Color(red: 0.88, green: 0.46, blue: 0.14)  // arancio bus
        case .concert:  return Color(red: 0.58, green: 0.20, blue: 0.72)  // viola
        case .cinema:   return Color(red: 0.75, green: 0.14, blue: 0.24)  // rosso cinema
        case .parking:  return Color(red: 0.30, green: 0.55, blue: 0.30)  // verde parcheggio
        case .museum:   return Color(red: 0.62, green: 0.41, blue: 0.20)  // bronzo
        case .other:    return Color(red: 0.35, green: 0.35, blue: 0.42)  // grafite
        }
    }

    /// Secondo colore del gradient (versione scurita dell'accent).
    var accentColorSecondary: Color {
        switch self {
        case .train:    return Color(red: 0.08, green: 0.27, blue: 0.50)
        case .flight:   return Color(red: 0.05, green: 0.17, blue: 0.32)
        case .ferry:    return Color(red: 0.00, green: 0.31, blue: 0.44)
        case .bus:      return Color(red: 0.62, green: 0.27, blue: 0.03)
        case .concert:  return Color(red: 0.35, green: 0.10, blue: 0.48)
        case .cinema:   return Color(red: 0.45, green: 0.07, blue: 0.12)
        case .parking:  return Color(red: 0.16, green: 0.33, blue: 0.18)
        case .museum:   return Color(red: 0.38, green: 0.23, blue: 0.09)
        case .other:    return Color(red: 0.18, green: 0.18, blue: 0.22)
        }
    }

    /// Promemoria di default (offset negativi rispetto a `eventDate`).
    /// Riusati anche dalla Cloud Function schedulata, lì semplificati a T-24h e T-2h.
    var defaultReminderOffsets: [TimeInterval] {
        switch self {
        case .flight:   return [-24 * 3600, -3 * 3600]      // T-24h, T-3h
        case .ferry:    return [-12 * 3600, -2 * 3600]      // T-12h, T-2h
        case .train:    return [-12 * 3600, -3600]          // T-12h, T-1h
        case .bus:      return [-6 * 3600, -3600]           // T-6h, T-1h
        case .cinema:   return [-30 * 60]                   // T-30min
        case .concert,
             .museum:   return [-24 * 3600, -2 * 3600]      // T-24h, T-2h
        case .parking:  return [-15 * 60]                   // T-15min
        case .other:    return [-24 * 3600, -2 * 3600]      // T-24h, T-2h
        }
    }
}
