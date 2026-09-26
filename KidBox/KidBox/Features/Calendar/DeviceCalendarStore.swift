//
//  DeviceCalendarStore.swift
//  KidBox
//
//  I calendari del telefono (Google, iCloud, Outlook, Exchange: quelli già
//  configurati in Impostazioni › Calendario) mostrati dentro il calendario
//  KidBox, in SOLA LETTURA.
//
//  Niente OAuth e niente server: la sincronizzazione con Google o iCloud la fa
//  il sistema operativo, qui si legge l'archivio locale di EventKit. Per questo
//  non c'è nulla da tenere allineato: un evento spostato su Google compare
//  spostato qui appena il telefono lo riceve (`EKEventStoreChanged`).
//
//  Questi eventi NON escono mai dal dispositivo e non li vede la famiglia:
//  per condividerne uno si usa «Copia in KidBox», che crea un
//  `KBCalendarEvent` normale e indipendente dall'originale.
//
//  Le preferenze (interruttore generale e calendari nascosti) sono del
//  dispositivo, non della famiglia: stanno in `UserDefaults`.
//

import Foundation
import EventKit
import SwiftUI
import UIKit
import Combine

// MARK: - DeviceCalendarEvent

/// Un'occorrenza di un evento del telefono, copiata in un valore: gli `EKEvent`
/// non devono uscire dal thread che li ha letti né sopravvivere a un
/// `EKEventStoreChanged`.
nonisolated struct DeviceCalendarEvent: Identifiable, Hashable, Sendable {
    /// `eventIdentifier` è lo stesso per tutte le occorrenze di un ricorrente:
    /// l'inizio lo rende unico.
    let id:              String
    let eventIdentifier: String
    let title:           String
    let location:        String?
    let notes:           String?
    let startDate:       Date
    let endDate:         Date
    let isAllDay:        Bool
    let calendarId:      String
    let calendarTitle:   String
    let colorHex:        String
    /// Valorizzato per gli eventi di un calendario iscritto da link (feed
    /// ICS, `CalendarFeedStore`): quelli li vede tutta la famiglia e non si
    /// aprono nell'app Calendario.
    var feedId:          String? = nil
}

/// Un calendario del telefono, per l'elenco degli interruttori.
nonisolated struct DeviceCalendarInfo: Identifiable, Hashable, Sendable {
    let id:          String
    let title:       String
    let sourceTitle: String
    let colorHex:    String
}

// Il colore è un tipo della UI: resta sul main actor, fuori dai valori
// che attraversano la lettura in background.
extension DeviceCalendarEvent {
    var color: Color { Color(hex: colorHex) ?? .gray }
}

extension DeviceCalendarInfo {
    var color: Color { Color(hex: colorHex) ?? .gray }
}

// MARK: - DeviceCalendarStore

final class DeviceCalendarStore: ObservableObject {

    static let shared = DeviceCalendarStore()

    private static let enabledKey = "kb.calendar.device.enabled"
    private static let hiddenKey  = "kb.calendar.device.hiddenIds"

    private let eventStore = EKEventStore()

    @Published private(set) var authorization: EKAuthorizationStatus
    @Published private(set) var calendars: [DeviceCalendarInfo] = []
    @Published private(set) var events: [DeviceCalendarEvent] = []

    /// L'interruttore generale. Parte spento: si accende solo quando l'utente
    /// concede l'accesso dalla scheda dei calendari.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            reload()
        }
    }

    /// Si salvano i calendari NASCOSTI, non quelli visibili: un calendario
    /// aggiunto dopo (un secondo account Google) compare da solo.
    @Published private(set) var hiddenCalendarIds: Set<String>

    /// La finestra di date che le viste stanno guardando, e quella caricata.
    private var requestedWindow: DateInterval?
    private var loadedWindow:    DateInterval?
    /// Scarta i risultati di una lettura superata da una più recente.
    private var fetchGeneration = 0
    private var changeObserver: AnyCancellable?

    private init() {
        authorization     = EKEventStore.authorizationStatus(for: .event)
        isEnabled         = UserDefaults.standard.bool(forKey: Self.enabledKey)
        hiddenCalendarIds = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])

        changeObserver = NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: eventStore)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                KBLog.calendar.kbInfo("DeviceCalendarStore: EKEventStoreChanged")
                self?.loadedWindow = nil
                self?.reload()
            }
    }

    // MARK: Stato

    var hasAccess: Bool { authorization == .fullAccess }

    /// L'utente non ha ancora risposto alla domanda di sistema.
    var isUndetermined: Bool { authorization == .notDetermined }

    /// Vero quando gli eventi del telefono vanno disegnati.
    var isShowing: Bool { isEnabled && hasAccess }

    /// L'utente ha detto no (o un profilo lo impedisce): l'unica strada è
    /// Impostazioni. `.writeOnly` conta come no: per leggere serve l'accesso
    /// completo.
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted || authorization == .writeOnly
    }

    /// Da chiamare quando la schermata torna in primo piano: l'accesso può
    /// essere stato tolto o dato da Impostazioni nel frattempo.
    func refreshAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status != authorization else { return }
        authorization = status
        loadedWindow = nil
        reload()
    }

    /// Chiede l'accesso completo e, se arriva, accende la funzione.
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorization = EKEventStore.authorizationStatus(for: .event)
            KBLog.calendar.kbInfo("DeviceCalendarStore: accesso calendari granted=\(granted)")
            if granted {
                // Dopo il primo permesso lo store va rinfrescato, altrimenti
                // `calendars(for:)` può rispondere vuoto.
                eventStore.reset()
                AppAnalytics.featureFirstUse(feature: "device_calendar")
                isEnabled = true
            }
            return granted
        } catch {
            authorization = EKEventStore.authorizationStatus(for: .event)
            KBLog.calendar.kbError("DeviceCalendarStore: richiesta accesso fallita \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Calendari

    func isVisible(calendarId: String) -> Bool {
        !hiddenCalendarIds.contains(calendarId)
    }

    func setVisible(_ visible: Bool, calendarId: String) {
        if visible {
            hiddenCalendarIds.remove(calendarId)
        } else {
            hiddenCalendarIds.insert(calendarId)
        }
        UserDefaults.standard.set(Array(hiddenCalendarIds).sorted(), forKey: Self.hiddenKey)
        loadedWindow = nil
        reload()
    }

    // MARK: Eventi

    /// Le viste dicono quale giorno stanno guardando; si carica una finestra
    /// larga attorno (l'anno intero più qualche mese) così lo scorrimento di
    /// mese e settimana non rilegge a ogni passo.
    func show(around date: Date) {
        let cal = Calendar.current
        let year = cal.dateInterval(of: .year, for: date)
            ?? DateInterval(start: date, duration: 86_400 * 365)
        let start = min(year.start, cal.date(byAdding: .month, value: -3, to: date) ?? year.start)
        let end   = max(year.end,   cal.date(byAdding: .month, value: 4, to: date) ?? year.end)
        let wanted = DateInterval(start: start, end: end)

        // Basta che il giorno guardato stia comodo dentro quello già letto.
        if let loaded = loadedWindow,
           let margin = cal.date(byAdding: .month, value: -2, to: date),
           let marginEnd = cal.date(byAdding: .month, value: 3, to: date),
           loaded.start <= margin, loaded.end >= marginEnd {
            return
        }
        requestedWindow = wanted
        reload()
    }

    func reload() {
        guard isShowing else {
            if !events.isEmpty { events = [] }
            if !hasAccess, !calendars.isEmpty { calendars = [] }
            loadedWindow = nil
            return
        }

        let allCalendars = eventStore.calendars(for: .event)
        calendars = allCalendars
            .map {
                DeviceCalendarInfo(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source?.title ?? "",
                    colorHex: Self.hex(of: $0.cgColor)
                )
            }
            .sorted { lhs, rhs in
                let bySource = lhs.sourceTitle.localizedStandardCompare(rhs.sourceTitle)
                if bySource != .orderedSame { return bySource == .orderedAscending }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        guard let window = requestedWindow ?? loadedWindow else { return }
        let visible = allCalendars.filter { !hiddenCalendarIds.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else {
            events = []
            loadedWindow = window
            return
        }

        fetchGeneration += 1
        let generation = fetchGeneration
        let store = eventStore
        Task.detached(priority: .userInitiated) {
            let loaded = Self.fetch(store: store, calendars: visible, window: window)
            await MainActor.run {
                guard generation == self.fetchGeneration else { return }
                self.events = loaded
                self.loadedWindow = window
            }
        }
    }

    /// Lettura vera e propria, fuori dal main thread: EventKit espande da sé
    /// le ricorrenze, e su un anno pieno di calendari condivisi possono essere
    /// migliaia di occorrenze.
    nonisolated private static func fetch(
        store: EKEventStore,
        calendars: [EKCalendar],
        window: DateInterval
    ) -> [DeviceCalendarEvent] {
        let predicate = store.predicateForEvents(
            withStart: window.start, end: window.end, calendars: calendars)
        return store.events(matching: predicate).map { ev in
            let identifier = ev.eventIdentifier ?? UUID().uuidString
            return DeviceCalendarEvent(
                id:              "\(identifier)|\(Int(ev.startDate.timeIntervalSince1970))",
                eventIdentifier: identifier,
                title:           (ev.title?.isEmpty == false ? ev.title : nil) ?? String(localized: "Evento senza titolo"),
                location:        ev.location?.isEmpty == false ? ev.location : nil,
                notes:           ev.notes?.isEmpty == false ? ev.notes : nil,
                startDate:       ev.startDate,
                endDate:         ev.endDate,
                isAllDay:        ev.isAllDay,
                calendarId:      ev.calendar.calendarIdentifier,
                calendarTitle:   ev.calendar.title,
                colorHex:        hex(of: ev.calendar.cgColor)
            )
        }
    }

    nonisolated private static func hex(of cgColor: CGColor?) -> String {
        guard let cgColor,
              let rgb = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 3 else { return "#8E8E93" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c[0]), byte(c[1]), byte(c[2]))
    }

    // MARK: Apertura in Calendario

    /// Apre l'app Calendario sul giorno dell'evento: `calshow:` vuole i
    /// secondi dal 1° gennaio 2001, non dal 1970.
    func openInSystemCalendar(_ event: DeviceCalendarEvent) {
        let seconds = Int(event.startDate.timeIntervalSinceReferenceDate)
        guard let url = URL(string: "calshow:\(seconds)") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Doppioni

nonisolated extension DeviceCalendarEvent {
    /// Un evento del telefono già copiato in KidBox non va disegnato due volte.
    /// Si confronta il contenuto e non un id: così sparisce anche per l'altro
    /// genitore, che ha lo stesso evento della scuola sul suo Google e non ha
    /// fatto la copia.
    var dedupKey: String {
        Self.dedupKey(title: title, startDate: startDate, isAllDay: isAllDay)
    }

    /// Titolo senza maiuscole e accenti, inizio al minuto, tutto-il-giorno.
    static func dedupKey(title: String, startDate: Date, isAllDay: Bool) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let minute = Int((startDate.timeIntervalSince1970 / 60).rounded())
        return "\(t)|\(minute)|\(isAllDay)"
    }
}
