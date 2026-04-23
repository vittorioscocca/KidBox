//
//  WalletEmitterDetector.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation

struct WalletEmitterDetection {
    let kind: KBWalletTicketKind
    let emitter: String?
    let bookingCode: String?
}

/// Euristica su testo grezzo estratto dal PDF per dedurre categoria + emittente.
///
/// L'ordine dei controlli è rilevante: prima le categorie con keyword più specifiche
/// (voli, traghetti, bus) e poi quelle più generiche (treno, cinema, museo),
/// in modo che ad esempio "stazione marittima" venga preso dal ramo traghetto,
/// non da quello treno. L'ordine finale termina con `.other`.
enum WalletEmitterDetector {

    static func detect(from rawText: String) -> WalletEmitterDetection {
        let text = rawText.lowercased()
        let bookingCode = extractBookingCode(from: rawText)

        // MARK: - Voli
        if let flightEmitter = detectFlightEmitter(in: text) {
            return WalletEmitterDetection(kind: .flight, emitter: flightEmitter, bookingCode: bookingCode)
        }
        if containsAny(text, ["boarding pass", "iata", "carta d'imbarco", "volo da ", "volo per ", "gate "]) {
            return WalletEmitterDetection(kind: .flight, emitter: nil, bookingCode: bookingCode)
        }

        // MARK: - Traghetti
        if let ferryEmitter = detectFerryEmitter(in: text) {
            return WalletEmitterDetection(kind: .ferry, emitter: ferryEmitter, bookingCode: bookingCode)
        }
        if containsAny(text, ["imbarco nave", "terminal traghetti", "passeggero traghetto", "cabina"]) {
            return WalletEmitterDetection(kind: .ferry, emitter: nil, bookingCode: bookingCode)
        }

        // MARK: - Bus
        if let busEmitter = detectBusEmitter(in: text) {
            return WalletEmitterDetection(kind: .bus, emitter: busEmitter, bookingCode: bookingCode)
        }
        if containsAny(text, ["autostazione", "fermata pullman", "pullman da"]) {
            return WalletEmitterDetection(kind: .bus, emitter: nil, bookingCode: bookingCode)
        }

        // MARK: - Treni
        if let trainEmitter = detectTrainEmitter(in: text) {
            return WalletEmitterDetection(kind: .train, emitter: trainEmitter, bookingCode: bookingCode)
        }
        if containsAny(text, ["stazione di ", "carrozza", "binario"]) {
            return WalletEmitterDetection(kind: .train, emitter: nil, bookingCode: bookingCode)
        }

        // MARK: - Eventi / concerti
        if let concertEmitter = detectConcertEmitter(in: text) {
            return WalletEmitterDetection(kind: .concert, emitter: concertEmitter, bookingCode: bookingCode)
        }
        if containsAny(text, ["concerto", "live show", "festival"]) {
            return WalletEmitterDetection(kind: .concert, emitter: nil, bookingCode: bookingCode)
        }

        // MARK: - Cinema
        if let cinemaEmitter = detectCinemaEmitter(in: text) {
            return WalletEmitterDetection(kind: .cinema, emitter: cinemaEmitter, bookingCode: bookingCode)
        }
        if containsAny(text, ["cinema", "sala ", "posto a sedere"]) {
            return WalletEmitterDetection(kind: .cinema, emitter: nil, bookingCode: bookingCode)
        }

        // MARK: - Parcheggi
        if let parkingEmitter = detectParkingEmitter(in: text) {
            return WalletEmitterDetection(kind: .parking, emitter: parkingEmitter, bookingCode: bookingCode)
        }
        if containsAny(text, ["parcheggio", "parking", "targa"]) {
            return WalletEmitterDetection(kind: .parking, emitter: nil, bookingCode: bookingCode)
        }

        // MARK: - Musei / esperienze
        if let museumEmitter = detectMuseumEmitter(in: text) {
            return WalletEmitterDetection(kind: .museum, emitter: museumEmitter, bookingCode: bookingCode)
        }
        if containsAny(text, ["museo", "museum", "mostra", "galleria", "esposizione"]) {
            return WalletEmitterDetection(kind: .museum, emitter: nil, bookingCode: bookingCode)
        }

        return WalletEmitterDetection(kind: .other, emitter: nil, bookingCode: bookingCode)
    }

    // MARK: - Per-kind emitter detection

    private static func detectFlightEmitter(in lowercasedText: String) -> String? {
        let map: [(needle: String, label: String)] = [
            ("ryanair", "Ryanair"),
            ("easyjet", "easyJet"),
            ("ita airways", "ITA Airways"),
            ("alitalia", "Alitalia"),
            ("wizz air", "Wizz Air"),
            ("wizzair", "Wizz Air"),
            ("volotea", "Volotea"),
            ("vueling", "Vueling"),
            ("pegasus", "Pegasus"),
            ("lufthansa", "Lufthansa"),
            ("air france", "Air France"),
            ("klm", "KLM"),
            ("british airways", "British Airways"),
            ("iberia", "Iberia"),
            ("tap portugal", "TAP"),
            ("tap air portugal", "TAP"),
            ("swiss international", "Swiss"),
            ("austrian airlines", "Austrian"),
            ("brussels airlines", "Brussels Airlines"),
            ("turkish airlines", "Turkish Airlines"),
            ("emirates", "Emirates"),
            ("qatar airways", "Qatar Airways"),
            ("etihad", "Etihad"),
            ("delta air lines", "Delta"),
            ("american airlines", "American Airlines"),
            ("united airlines", "United"),
            ("jetblue", "JetBlue"),
            ("aer lingus", "Aer Lingus"),
            ("sas ", "SAS"),
            ("finnair", "Finnair"),
            ("norwegian", "Norwegian")
        ]
        return firstMatchLabel(in: lowercasedText, map: map)
    }

    private static func detectFerryEmitter(in lowercasedText: String) -> String? {
        let map: [(needle: String, label: String)] = [
            ("moby", "Moby"),
            ("tirrenia", "Tirrenia"),
            ("grimaldi lines", "Grimaldi Lines"),
            ("grandi navi veloci", "GNV"),
            ("gnv ", "GNV"),
            ("corsica ferries", "Corsica Ferries"),
            ("sardinia ferries", "Sardinia Ferries"),
            ("liberty lines", "Liberty Lines"),
            ("caronte & tourist", "Caronte & Tourist"),
            ("caronte e tourist", "Caronte & Tourist"),
            ("snav", "SNAV"),
            ("blu navy", "Blu Navy"),
            ("toremar", "Toremar"),
            ("siremar", "Siremar"),
            ("minoan lines", "Minoan Lines"),
            ("anek lines", "ANEK Lines"),
            ("superfast ferries", "Superfast"),
            ("dfds", "DFDS"),
            ("stena line", "Stena Line"),
            ("brittany ferries", "Brittany Ferries"),
            ("p&o ferries", "P&O Ferries"),
            ("irish ferries", "Irish Ferries")
        ]
        return firstMatchLabel(in: lowercasedText, map: map)
    }

    private static func detectBusEmitter(in lowercasedText: String) -> String? {
        let map: [(needle: String, label: String)] = [
            ("flixbus", "FlixBus"),
            ("itabus", "Itabus"),
            ("marinobus", "Marino Bus"),
            ("marino bus", "Marino Bus"),
            ("baltour", "Baltour"),
            ("megabus", "Megabus"),
            ("eurolines", "Eurolines"),
            ("blablabus", "BlaBlaBus")
        ]
        return firstMatchLabel(in: lowercasedText, map: map)
    }

    private static func detectTrainEmitter(in lowercasedText: String) -> String? {
        let map: [(needle: String, label: String)] = [
            ("frecciarossa", "Trenitalia"),
            ("frecciargento", "Trenitalia"),
            ("frecciabianca", "Trenitalia"),
            ("intercity", "Trenitalia"),
            ("trenitalia", "Trenitalia"),
            ("italo treno", "Italo"),
            ("italo ntv", "Italo"),
            ("italotreno", "Italo"),
            ("italo ", "Italo"),
            ("trenord", "Trenord"),
            ("tper", "Tper"),
            ("fse ", "FSE"),
            ("fnm ", "FNM"),
            ("sncf", "SNCF"),
            ("tgv inoui", "TGV"),
            ("ouigo", "Ouigo"),
            ("eurostar", "Eurostar"),
            ("renfe", "Renfe"),
            (" ave ", "Renfe AVE"),
            ("deutsche bahn", "Deutsche Bahn"),
            ("öbb", "ÖBB"),
            ("obb ", "ÖBB"),
            ("sbb ", "SBB")
        ]
        return firstMatchLabel(in: lowercasedText, map: map)
    }

    private static func detectConcertEmitter(in lowercasedText: String) -> String? {
        let map: [(needle: String, label: String)] = [
            ("ticketone", "TicketOne"),
            ("ticketmaster", "Ticketmaster"),
            ("live nation", "Live Nation"),
            ("dice.fm", "DICE"),
            ("vivaticket", "Vivaticket")
        ]
        return firstMatchLabel(in: lowercasedText, map: map)
    }

    private static func detectCinemaEmitter(in lowercasedText: String) -> String? {
        let map: [(needle: String, label: String)] = [
            ("uci cinemas", "UCI Cinemas"),
            ("the space", "The Space Cinema"),
            ("cinelandia", "Cinelandia"),
            ("notorious cinemas", "Notorious Cinemas"),
            ("anteo palazzo", "Anteo"),
            ("odeon ", "Odeon"),
            ("cineworld", "Cineworld")
        ]
        return firstMatchLabel(in: lowercasedText, map: map)
    }

    private static func detectParkingEmitter(in lowercasedText: String) -> String? {
        let map: [(needle: String, label: String)] = [
            ("telepass", "Telepass"),
            ("easypark", "EasyPark"),
            ("mycicero", "MyCicero"),
            ("saba ", "SABA"),
            ("apcoa", "APCOA"),
            ("q-park", "Q-Park"),
            ("interparking", "Interparking")
        ]
        return firstMatchLabel(in: lowercasedText, map: map)
    }

    private static func detectMuseumEmitter(in lowercasedText: String) -> String? {
        let map: [(needle: String, label: String)] = [
            ("musei vaticani", "Musei Vaticani"),
            ("uffizi", "Uffizi"),
            ("colosseo", "Colosseo"),
            ("pompei", "Pompei"),
            ("maxxi", "MAXXI"),
            ("triennale", "Triennale"),
            ("pinacoteca di brera", "Brera"),
            ("accademia", "Accademia"),
            ("palazzo ducale", "Palazzo Ducale"),
            ("musement", "Musement"),
            ("getyourguide", "GetYourGuide"),
            ("tiqets", "Tiqets"),
            ("headout", "Headout"),
            ("viator", "Viator")
        ]
        return firstMatchLabel(in: lowercasedText, map: map)
    }

    // MARK: - Helpers

    private static func firstMatchLabel(
        in haystack: String,
        map: [(needle: String, label: String)]
    ) -> String? {
        for entry in map where haystack.contains(entry.needle) {
            return entry.label
        }
        return nil
    }

    private static func containsAny(_ haystack: String, _ values: [String]) -> Bool {
        values.contains { haystack.contains($0) }
    }

    private static func extractBookingCode(from text: String) -> String? {
        // Pattern comuni: PNR ABC123, Booking code: ABC123, Codice: XYZ789
        let patterns = [
            #"(?i)(?:pnr|booking(?:\s*code)?|codice(?:\s*prenotazione)?)[\s:]*([A-Z0-9]{5,10})"#,
            #"\b([A-Z0-9]{6})\b"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= 5 { return value }
            }
        }
        return nil
    }
}
