//
//  CalendarFeedStore.swift
//  KidBox
//
//  I calendari iscritti da link (feed ICS): scuola, squadra, festività,
//  l'indirizzo iCal di un Google Calendar. Li scarica e li rilegge il server
//  (`functions/calendarFeeds.js`), che salva le occorrenze già espanse DENTRO
//  il documento `families/{id}/calendarFeeds/{feedId}`: qui si ascolta e basta,
//  una lettura per feed. Il documento non si scrive dal client (rules): si
//  passa da `saveCalendarFeed` / `deleteCalendarFeed`.
//
//  A differenza dei calendari del telefono questi li vede tutta la famiglia,
//  anche sul web. Gemello di `CalendarFeedRepository` su Android.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseFunctions

struct CalendarFeed: Identifiable, Equatable {
    let id:          String
    let name:        String
    let url:         String
    let colorHex:    String
    let eventCount:  Int
    /// Codice dell'ultimo aggiornamento fallito (`calendarFeeds.js` → `ERR`), o nil.
    let lastError:   String?
    let lastFetchAt: Date?
    let truncated:   Bool

    var color: Color { Color(hex: colorHex) ?? .blue }
}

final class CalendarFeedStore: ObservableObject {

    static let shared = CalendarFeedStore()

    /// Colori proposti all'iscrizione: gli stessi su Android e web.
    static let palette = ["#5B8DEF", "#E67E22", "#27AE60", "#8E44AD", "#E74C3C", "#16A085"]

    @Published private(set) var feeds:  [CalendarFeed] = []
    @Published private(set) var events: [DeviceCalendarEvent] = []

    private var listener: ListenerRegistration?
    private var listeningFamilyId: String?
    private let functions = Functions.functions(region: "europe-west1")
    /// Feed già rinfrescati dal telefono in questo avvio: niente giri a vuoto.
    private var refreshedThisRun = Set<String>()
    nonisolated private static let maxBytes = 5 * 1024 * 1024
    private static let staleAfter: TimeInterval = 12 * 3600

    private init() {}

    func start(familyId: String) {
        guard !familyId.isEmpty, familyId != listeningFamilyId else { return }
        stop()
        listeningFamilyId = familyId
        listener = Firestore.firestore()
            .collection("families").document(familyId).collection("calendarFeeds")
            .addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    KBLog.calendar.kbError("CalendarFeedStore: ascolto fallito \(error.localizedDescription)")
                    return
                }
                // Il risultato completo, non il delta: con la cache locale il
                // delta può arrivare vuoto anche con documenti veri.
                let docs = snap?.documents ?? []
                var feeds: [CalendarFeed] = []
                var events: [DeviceCalendarEvent] = []
                for doc in docs {
                    let d = doc.data()
                    let name = d["name"] as? String ?? ""
                    let colorHex = d["colorHex"] as? String ?? Self.palette[0]
                    feeds.append(CalendarFeed(
                        id: doc.documentID,
                        name: name,
                        url: d["url"] as? String ?? "",
                        colorHex: colorHex,
                        eventCount: d["eventCount"] as? Int ?? 0,
                        lastError: d["lastError"] as? String,
                        lastFetchAt: (d["lastFetchAt"] as? Timestamp)?.dateValue(),
                        truncated: d["truncated"] as? Bool ?? false
                    ))
                    for raw in d["events"] as? [[String: Any]] ?? [] {
                        if let ev = Self.parse(raw, feedId: doc.documentID, feedName: name, colorHex: colorHex) {
                            events.append(ev)
                        }
                    }
                }
                self.feeds = feeds.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.events = events.sorted { $0.startDate < $1.startDate }
                self.refreshStaleFromPhone(familyId: familyId, feeds: feeds)
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        listeningFamilyId = nil
        feeds = []
        events = []
    }

    /// Un evento come lo salva il server. Tutto il giorno: date "YYYY-MM-DD"
    /// (fine esclusa) riportate alla mezzanotte LOCALE, così Natale resta il 25
    /// in ogni fuso. A orario: millisecondi epoch.
    private static func parse(_ e: [String: Any], feedId: String, feedName: String, colorHex: String) -> DeviceCalendarEvent? {
        let allDay = e["a"] as? Bool ?? false
        let start: Date
        let end: Date
        if allDay {
            guard let s = e["s"] as? String, let sd = localMidnight(s) else { return nil }
            start = sd
            end = (e["e"] as? String).flatMap { localMidnight($0) } ?? sd.addingTimeInterval(86_400)
        } else {
            guard let s = (e["s"] as? NSNumber)?.doubleValue else { return nil }
            start = Date(timeIntervalSince1970: s / 1000)
            end = (e["e"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? start
        }
        let rawId = e["id"] as? String ?? "\(start.timeIntervalSince1970)"
        let title = (e["t"] as? String) ?? ""
        return DeviceCalendarEvent(
            id: "feed:\(feedId)|\(rawId)",
            eventIdentifier: rawId,
            title: title.isEmpty ? String(localized: "Evento senza titolo") : title,
            location: (e["l"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            notes: (e["n"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            startDate: start,
            endDate: max(end, start),
            isAllDay: allDay,
            calendarId: "feed:\(feedId)",
            calendarTitle: feedName,
            colorHex: colorHex,
            feedId: feedId
        )
    }

    nonisolated private static func localMidnight(_ ymd: String) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: - Iscrizione e rimozione

    enum Outcome: Equatable {
        case ok(eventCount: Int)
        /// Codice che il server mette in `details.reason`.
        case failed(reason: String)
    }

    /// Il server scarica subito il link: se è sbagliato lo si sa adesso. Se il
    /// sito respinge il server (Google Calendar risponde 429 agli indirizzi
    /// delle Cloud Functions, non ai telefoni) lo scarica il telefono e al
    /// server va solo il contenuto da leggere.
    func subscribe(familyId: String, name: String, url: String, colorHex: String) async -> Outcome {
        var data: [String: Any] = ["familyId": familyId, "name": name, "url": url, "colorHex": colorHex]
        let first = await call("saveCalendarFeed", data)
        guard case .failed(let reason) = first, reason == "unreachable",
              let text = await Self.downloadFromPhone(url) else { return first }
        data["icsText"] = text
        return await call("saveCalendarFeed", data)
    }

    /// I feed rimasti indietro (ultimo aggiornamento fallito o più vecchio di
    /// 12 ore) li rinfresca il telefono. Una volta per feed a ogni avvio.
    private func refreshStaleFromPhone(familyId: String, feeds: [CalendarFeed]) {
        let now = Date()
        let stale = feeds.filter { feed in
            !refreshedThisRun.contains(feed.id) &&
                (feed.lastError != nil || (feed.lastFetchAt ?? .distantPast) < now.addingTimeInterval(-Self.staleAfter))
        }
        guard !stale.isEmpty else { return }
        stale.forEach { refreshedThisRun.insert($0.id) }
        Task {
            for feed in stale {
                guard let text = await Self.downloadFromPhone(feed.url) else { continue }
                let outcome = await call("uploadCalendarFeedContent", [
                    "familyId": familyId, "feedId": feed.id, "icsText": text,
                ])
                KBLog.calendar.kbInfo("CalendarFeedStore: rinfrescato dal telefono \(feed.id) → \(String(describing: outcome))")
            }
        }
    }

    /// Scarica il feed dal telefono, con lo stesso tetto di 5 MB del server.
    nonisolated private static func downloadFromPhone(_ raw: String) async -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: "^webcals?://", options: [.regularExpression, .caseInsensitive]) {
            s.replaceSubrange(range, with: "https://")
        }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), url.scheme == "https" || url.scheme == "http" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("text/calendar, */*;q=0.5", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= maxBytes,
                  let text = String(data: data, encoding: .utf8),
                  text.range(of: "BEGIN:VCALENDAR", options: .caseInsensitive) != nil
            else { return nil }
            return text
        } catch {
            return nil
        }
    }

    func delete(familyId: String, feedId: String) async -> Outcome {
        await call("deleteCalendarFeed", ["familyId": familyId, "feedId": feedId])
    }

    private func call(_ name: String, _ data: [String: Any]) async -> Outcome {
        do {
            let result = try await functions.httpsCallable(name).call(data)
            let count = (result.data as? [String: Any])?["eventCount"] as? Int ?? 0
            return .ok(eventCount: count)
        } catch {
            let ns = error as NSError
            let reason = (ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any])?["reason"] as? String
            KBLog.calendar.kbError("CalendarFeedStore: \(name) fallita reason=\(reason ?? "nil") \(ns.localizedDescription)")
            return .failed(reason: reason ?? "unreachable")
        }
    }

    /// I codici di `calendarFeeds.js` → testo per chi ha incollato il link.
    static func message(for reason: String) -> String {
        switch reason {
        case "invalid_url":     return String(localized: "Il link non è valido.")
        case "private_address": return String(localized: "Questo indirizzo non è raggiungibile da KidBox.")
        case "http_error":      return String(localized: "Il sito ha rifiutato la richiesta: il link potrebbe essere privato o scaduto.")
        case "too_large":       return String(localized: "Il calendario è troppo grande.")
        case "not_ics":         return String(localized: "Il link non porta a un calendario (.ics).")
        case "too_many_feeds":  return String(localized: "La famiglia ha già 10 calendari iscritti.")
        default:                return String(localized: "Il sito del calendario non risponde. Riprova più tardi.")
        }
    }
}
