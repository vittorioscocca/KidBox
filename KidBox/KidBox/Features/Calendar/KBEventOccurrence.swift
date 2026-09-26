//
//  KBEventOccurrence.swift
//  KidBox
//
//  Le ripetizioni di un evento KidBox ricorrente.
//
//  `recurrenceRaw` si scriveva dalla prima versione del calendario ma nessuna
//  vista lo leggeva: un evento «settimanale» compariva solo il primo giorno.
//  Qui la serie si espande in occorrenze dentro una finestra di date, con le
//  stesse regole di Calendario di Apple per i casi limite:
//
//  - ogni occorrenza si calcola dall'inizio originale (`inizio + n × passo`),
//    mai dalla precedente, così il 31 non scivola al 30 e poi al 28 per sempre;
//  - l'orario è quello «da orologio» (`Calendar` gestisce l'ora legale);
//  - un mensile del 31 cade l'ultimo giorno dei mesi più corti, un annuale
//    del 29 febbraio il 28 negli anni non bisestili.
//
//  La serie non ha fine (il modello non ha una data di termine) né eccezioni:
//  si modifica e si cancella tutta insieme.
//

import Foundation

struct KBEventOccurrence: Identifiable {
    let event:     KBCalendarEvent
    /// Indice nella serie: 0 è l'evento originale.
    let index:     Int
    let startDate: Date
    let endDate:   Date

    var id: String { "\(event.id)|\(index)" }
    var isRecurring: Bool { event.recurrence != .none }
}

extension KBCalendarEvent {

    /// Le occorrenze che toccano `window`. Un evento non ricorrente ne ha al
    /// massimo una.
    func occurrences(in window: DateInterval, calendar: Calendar = .current) -> [KBEventOccurrence] {
        let start    = min(startDate, endDate)
        let duration = max(endDate.timeIntervalSince(startDate), 0)

        guard let step = recurrence.calendarStep else {
            let end = start.addingTimeInterval(duration)
            guard start <= window.end, end >= window.start else { return [] }
            return [KBEventOccurrence(event: self, index: 0, startDate: start, endDate: end)]
        }
        guard start <= window.end else { return [] }

        // Salta direttamente vicino alla finestra invece di contare da un
        // evento magari di tre anni fa. Un passo indietro di margine per le
        // occorrenze lunghe che iniziano prima e finiscono dentro.
        let from = window.start.addingTimeInterval(-duration)
        let elapsed = calendar.dateComponents([step.component], from: start, to: from)
        let skipped = max((elapsed.value(for: step.component) ?? 0) / step.value - 1, 0)

        var result: [KBEventOccurrence] = []
        var n = skipped
        // Tetto di sicurezza: un giornaliero su due anni sono ~730 occorrenze.
        while n < skipped + 2_000 {
            guard let occStart = calendar.date(byAdding: step.component, value: n * step.value, to: start) else { break }
            if occStart > window.end { break }
            let occEnd = occStart.addingTimeInterval(duration)
            if occEnd >= window.start {
                result.append(KBEventOccurrence(event: self, index: n, startDate: occStart, endDate: occEnd))
            }
            n += 1
        }
        return result
    }

    /// Il primo inizio della serie dopo `date`: serve al promemoria, che
    /// deve suonare per la prossima ripetizione e non per la prima.
    func nextOccurrenceStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard recurrence != .none else { return startDate > date ? startDate : nil }
        // Due anni bastano a trovare la prossima di qualsiasi passo.
        let window = DateInterval(start: date, duration: 86_400 * 800)
        return occurrences(in: window, calendar: calendar)
            .first { $0.startDate > date }?
            .startDate
    }
}

extension KBEventRecurrence {
    /// Il passo della serie, o `nil` per un evento singolo.
    var calendarStep: (component: Calendar.Component, value: Int)? {
        switch self {
        case .none:    return nil
        case .daily:   return (.day, 1)
        case .weekly:  return (.day, 7)
        case .monthly: return (.month, 1)
        case .yearly:  return (.year, 1)
        }
    }
}
