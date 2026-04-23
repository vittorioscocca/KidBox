//
//  WalletEmitterIcon.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation

/// Mappa nome-emittente → miglior SF Symbol disponibile.
///
/// Idea: un biglietto può avere `kind == .flight` e mostrare il generico "airplane",
/// ma se conosciamo l'emittente possiamo sostituirlo con un simbolo più evocativo
/// (es. un volo Ryanair → `airplane.departure`, un treno notturno → `moon.stars.fill`,
/// un traghetto Moby → `ferry.fill`, un bus Flixbus → `bus.doubledecker.fill`, ecc.).
///
/// Tutti i simboli usati sono disponibili almeno da iOS 16. Per iOS 17+ potremmo
/// sostituire `tram.fill` con `train.side.front.car`, ma per retrocompatibilità
/// manteniamo l'insieme iOS 16.
enum WalletEmitterIcon {

    /// Restituisce l'SF Symbol più specifico per la coppia (emittente, kind).
    /// - Parameters:
    ///   - emitter: nome dell'emittente (case-insensitive), se riconosciuto dal parser.
    ///   - kind: categoria del biglietto (fallback se emitter è nil o sconosciuto).
    static func icon(for emitter: String?, kind: KBWalletTicketKind) -> String {
        if let emitter, let specific = specificIcon(for: emitter.lowercased()) {
            return specific
        }
        return kind.systemImage
    }

    private static func specificIcon(for lowercased: String) -> String? {
        // MARK: - Voli
        // Low-cost europee → decollo
        if matches(lowercased, ["ryanair", "easyjet", "wizz", "volotea", "vueling", "pegasus"]) {
            return "airplane.departure"
        }
        // Flag carriers → simbolo neutro / arrivo
        if matches(lowercased, [
            "ita airways", "alitalia",
            "lufthansa", "air france", "klm", "british airways",
            "iberia", "tap", "swiss", "austrian", "brussels airlines",
            "turkish", "emirates", "qatar", "etihad",
            "delta", "american", "united", "jetblue",
            "aer lingus", "sas", "finnair", "norwegian",
            "aeromexico", "avianca", "latam"
        ]) {
            return "airplane"
        }

        // MARK: - Treni
        if matches(lowercased, ["frecciarossa", "frecciargento", "frecciabianca", "trenitalia", "intercity"]) {
            return "tram.fill"
        }
        if matches(lowercased, ["italo"]) {
            return "tram.fill"
        }
        // Treni regionali / suburbani
        if matches(lowercased, ["trenord", "tper", "fse", "fnm", "sfm", "trenitalia tper"]) {
            return "tram.fill"
        }
        // Internazionali
        if matches(lowercased, ["sncf", "tgv", "ouigo", "eurostar", "renfe", "ave", "ice", "db ", "deutsche bahn", "öbb", "obb", "sbb"]) {
            return "tram.fill"
        }

        // MARK: - Traghetti / Navi
        if matches(lowercased, [
            "moby", "tirrenia", "grimaldi", "gnv", "grandi navi veloci",
            "corsica ferries", "sardinia ferries", "liberty lines",
            "caronte", "snav", "blu navy", "toremar", "siremar",
            "minoan", "anek", "superfast",
            "dfds", "stena", "brittany ferries", "p&o", "irish ferries"
        ]) {
            return "ferry.fill"
        }

        // MARK: - Bus
        if matches(lowercased, ["flixbus", "flix "]) {
            return "bus.doubledecker.fill"
        }
        if matches(lowercased, ["itabus", "marino bus", "marinobus", "baltour", "megabus", "eurolines", "blablabus"]) {
            return "bus.fill"
        }

        // MARK: - Parcheggi
        if matches(lowercased, ["telepass"]) {
            return "road.lanes"
        }
        if matches(lowercased, ["easypark", "mycicero", "saba", "apcoa", "q-park", "interparking"]) {
            return "parkingsign.circle.fill"
        }

        // MARK: - Eventi / Concerti
        if matches(lowercased, ["ticketone", "ticketmaster", "live nation", "dice"]) {
            return "music.mic"
        }
        if matches(lowercased, ["vivaticket"]) {
            return "music.note"
        }

        // MARK: - Cinema
        if matches(lowercased, ["uci cinemas", "the space", "cinelandia", "notorious", "anteo", "odeon", "cineworld"]) {
            return "film.fill"
        }

        // MARK: - Musei / Mostre / Esperienze
        if matches(lowercased, ["uffizi", "vaticano", "vatican", "colosseo", "pompei", "maxxi", "triennale", "brera", "accademia", "doge"]) {
            return "building.columns.fill"
        }
        if matches(lowercased, ["musement", "getyourguide", "tiqets", "headout", "viator"]) {
            return "ticket.fill"
        }

        return nil
    }

    private static func matches(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
