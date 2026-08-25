//
//  KBLocalNotificationBudget.swift
//  KidBox
//
//  Cancello unico per tutte le notifiche locali pianificate dall'app.
//

import Foundation
import UserNotifications

/// Quanto è importante che una notifica locale sopravviva quando lo spazio finisce.
enum KBLocalNotificationPriority: Int, Comparable, Sendable {
    /// Contenuti generati: nudge, briefing, recap, insight. Saltarne uno non fa danno.
    case background = 0
    /// Avvisi di servizio: abbonamento in scadenza, riepilogo sicurezza password.
    case informational = 1
    /// Scadenze reali con una data: to-do, visite, esami, vaccini, Wallet, veicoli,
    /// pagamenti casa, scadenza password.
    case deadline = 2
    /// Dosi delle terapie e relativa sentinella: sono promemoria sanitari, cedono per ultimi.
    case critical = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Quante notifiche pendenti può occupare al massimo questa classe.
    /// La somma sta sotto il limite utilizzabile: nessuna classe può affamare le altre.
    var quota: Int {
        switch self {
        case .critical:      return 32
        case .deadline:      return 20
        case .informational: return 4
        case .background:    return 4
        }
    }

    /// Classe di una notifica già pendente, dedotta dal suo `userInfo["type"]`.
    /// I tipi sconosciuti finiscono in `.deadline`: è la classe più affollata, quindi
    /// sbagliare per eccesso di prudenza lì costa meno che declassare per errore.
    static func forPending(_ request: UNNotificationRequest) -> KBLocalNotificationPriority {
        switch request.content.userInfo["type"] as? String {
        case "treatment_reminder", "treatment_reschedule_sentinel":
            return .critical
        case "nudge", "daily_briefing", "weekly_summary", "health_pattern":
            return .background
        case "subscription_expiring", "password_security_summary":
            return .informational
        default:
            return .deadline
        }
    }
}

/// iOS conserva al massimo 64 notifiche locali pendenti per app e **scarta le
/// eccedenti in silenzio**, tenendo le più imminenti. Senza un cancello unico
/// bastano due cure attive e due veicoli per superare il tetto: a sparire sono
/// le notifiche più lontane nel tempo, cioè proprio la coda delle terapie e le
/// scadenze veicoli — le cose che devono funzionare senza che l'utente ci pensi.
///
/// Questo attore è l'unico punto da cui l'app pianifica notifiche locali. Quando
/// lo spazio finisce decide *lei* cosa sacrificare, invece di lasciarlo fare a
/// iOS: prima le classi meno importanti, e all'interno della stessa classe le
/// notifiche più lontane nel tempo.
actor KBLocalNotificationBudget {

    static let shared = KBLocalNotificationBudget()

    /// Tetto di sistema, non modificabile.
    static let systemLimit = 64
    /// Margine lasciato libero: le notifiche push non contano qui, ma un po' di
    /// respiro evita di ballare sul filo del limite a ogni pianificazione.
    private static let safetyMargin = 4
    static var usableLimit: Int { systemLimit - safetyMargin }

    private let center = UNUserNotificationCenter.current()

    // MARK: - API

    /// Pianifica una notifica, facendole spazio se serve.
    /// - Returns: `true` se la notifica è stata accettata, `false` se il budget
    ///   era pieno di cose più importanti e questa è stata scartata.
    @discardableResult
    func add(_ request: UNNotificationRequest, priority: KBLocalNotificationPriority) async -> Bool {
        await add([request], priority: priority) == 1
    }

    /// Variante a lotti: una sola lettura dello stato pendente per l'intero gruppo.
    /// Le richieste vengono valutate dalla più imminente alla più lontana, così se
    /// lo spazio finisce a cadere è la coda del lotto e non un buco in mezzo.
    /// - Returns: quante richieste sono state effettivamente pianificate.
    @discardableResult
    func add(_ requests: [UNNotificationRequest], priority: KBLocalNotificationPriority) async -> Int {
        guard !requests.isEmpty else { return 0 }

        var pending = await center.pendingNotificationRequests()
        var accepted = 0

        for request in requests.sorted(by: { Self.fireDate($0) ?? .distantFuture < Self.fireDate($1) ?? .distantFuture }) {
            // Sostituzione di una richiesta con lo stesso identificatore: non
            // consuma un nuovo slot, iOS rimpiazza in place.
            if let idx = pending.firstIndex(where: { $0.identifier == request.identifier }) {
                pending.remove(at: idx)
            } else if !(await makeRoom(for: request, priority: priority, pending: &pending)) {
                KBLog.auth.kbInfo("[NotifBudget] scartata id=\(request.identifier) priority=\(priority) — budget pieno")
                continue
            }

            do {
                try await center.add(request)
                pending.append(request)
                accepted += 1
            } catch {
                KBLog.auth.kbError("[NotifBudget] add fallita id=\(request.identifier): \(error.localizedDescription)")
            }
        }
        return accepted
    }

    /// Stato corrente, per diagnostica.
    func snapshot() async -> (total: Int, byPriority: [KBLocalNotificationPriority: Int]) {
        let pending = await center.pendingNotificationRequests()
        var counts: [KBLocalNotificationPriority: Int] = [:]
        for request in pending {
            counts[.forPending(request), default: 0] += 1
        }
        return (pending.count, counts)
    }

    // MARK: - Privato

    /// Libera uno slot se necessario. `pending` viene aggiornato di conseguenza.
    /// - Returns: `false` se non c'è nulla di sacrificabile e la richiesta va scartata.
    private func makeRoom(
        for request: UNNotificationRequest,
        priority: KBLocalNotificationPriority,
        pending: inout [UNNotificationRequest]
    ) async -> Bool {
        let newFire = Self.fireDate(request) ?? .distantFuture
        let sameClass = pending.filter { KBLocalNotificationPriority.forPending($0) == priority }

        // Quota di classe superata: si cede all'interno della propria classe, e
        // solo se la nuova notifica scatta prima di quella che sostituisce.
        if sameClass.count >= priority.quota {
            guard let victim = Self.farthest(in: sameClass),
                  (Self.fireDate(victim) ?? .distantFuture) > newFire
            else { return false }
            await evict(victim, from: &pending, reason: "quota \(priority)")
            return true
        }

        guard pending.count >= Self.usableLimit else { return true }

        // Budget globale pieno: si sacrifica la classe meno importante, partendo
        // dalla notifica più lontana nel tempo. A parità di classe vince la più imminente.
        let sacrificeable = pending.filter { existing in
            let existingPriority = KBLocalNotificationPriority.forPending(existing)
            if existingPriority < priority { return true }
            guard existingPriority == priority else { return false }
            return (Self.fireDate(existing) ?? .distantFuture) > newFire
        }
        guard let victim = sacrificeable.min(by: { lhs, rhs in
            let lp = KBLocalNotificationPriority.forPending(lhs)
            let rp = KBLocalNotificationPriority.forPending(rhs)
            if lp != rp { return lp < rp }
            return (Self.fireDate(lhs) ?? .distantFuture) > (Self.fireDate(rhs) ?? .distantFuture)
        }) else { return false }

        await evict(victim, from: &pending, reason: "budget pieno")
        return true
    }

    private func evict(
        _ victim: UNNotificationRequest,
        from pending: inout [UNNotificationRequest],
        reason: String
    ) async {
        center.removePendingNotificationRequests(withIdentifiers: [victim.identifier])
        pending.removeAll { $0.identifier == victim.identifier }
        KBLog.auth.kbInfo("[NotifBudget] rimossa id=\(victim.identifier) — \(reason)")
    }

    private static func farthest(in requests: [UNNotificationRequest]) -> UNNotificationRequest? {
        requests.max { (fireDate($0) ?? .distantFuture) < (fireDate($1) ?? .distantFuture) }
    }

    /// Istante di scatto di una richiesta. Le notifiche ripetute non hanno una
    /// fine: valgono `.distantFuture`, così sono le prime a cedere il posto.
    private static func fireDate(_ request: UNNotificationRequest) -> Date? {
        switch request.trigger {
        case let trigger as UNCalendarNotificationTrigger:
            return trigger.repeats ? .distantFuture : trigger.nextTriggerDate()
        case let trigger as UNTimeIntervalNotificationTrigger:
            return trigger.repeats ? .distantFuture : trigger.nextTriggerDate()
        default:
            return nil
        }
    }
}
