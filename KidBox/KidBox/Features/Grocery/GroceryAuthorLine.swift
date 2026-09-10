//
//  GroceryAuthorLine.swift
//  KidBox
//

import Foundation

/// Riga "Aggiunto da … · oggi" sotto ogni articolo della spesa.
///
/// Serve soprattutto agli articoli dettati ad Alexa, che compaiono in lista
/// senza che nessuno li abbia scritti: senza attribuzione ci si chiede chi li
/// abbia messi. Ma vale per tutti, perché in una lista condivisa "chi e quando"
/// è l'informazione che evita di ricomprare due volte la stessa cosa.
enum GroceryAuthorLine {

    /// Giorni oltre i quali si passa alla data esplicita.
    ///
    /// Entro tre giorni il riferimento relativo è più utile della data: "ieri"
    /// si colloca da solo, "5 settembre" va ricalcolato a mente. Più indietro
    /// si inverte — "12 giorni fa" non dice niente, la data sì.
    private static let relativeDayLimit = 3

    /// Distanza in giorni di calendario, non in multipli di 24 ore: alle 00:30
    /// un articolo di ieri sera dev'essere "ieri", non "oggi".
    static func daysAgo(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: today).day ?? 0
    }

    /// Etichetta relativa: ore dentro la giornata, giorni oltre, poi la data.
    ///
    /// Dentro la giornata "oggi" dice troppo poco: fra un articolo di cinque
    /// minuti fa e uno di stamattina presto c'è la differenza fra "l'ho appena
    /// messo io" e "c'era già". Le ore quella differenza la mostrano.
    static func dateLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = daysAgo(from: date, now: now, calendar: calendar)

        // Una data futura non dovrebbe esistere, ma l'orologio del dispositivo
        // può essere indietro rispetto al server: meglio "adesso" di un valore
        // negativo.
        if days <= 0 { return withinTodayLabel(for: date, now: now) }
        if days == 1 { return String(localized: "ieri") }
        if days <= relativeDayLimit { return String(localized: "\(days) giorni fa") }

        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Sotto la giornata si scende a ore e minuti.
    private static func withinTodayLabel(for date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)

        // Sotto i due minuti "1 minuto fa" è più preciso che utile, e obbliga a
        // gestire il singolare in quattro lingue per guadagnare niente.
        if minutes < 2 { return String(localized: "adesso") }
        if minutes < 60 { return String(localized: "\(minutes) minuti fa") }

        let hours = minutes / 60
        if hours == 1 { return String(localized: "un'ora fa") }
        return String(localized: "\(hours) ore fa")
    }

    /// Riga completa. Senza autore resta la sola data: "Aggiunto da un ignoto"
    /// non aggiunge niente e occupa spazio.
    static func text(authorName: String?, date: Date, now: Date = Date()) -> String {
        let when = dateLabel(for: date, now: now)
        guard let authorName, !authorName.isEmpty else { return when }
        return String(localized: "Aggiunto da \(authorName) · \(when)")
    }
}
