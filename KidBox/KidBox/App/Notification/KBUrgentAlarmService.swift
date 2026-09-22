//
//  KBUrgentAlarmService.swift
//  KidBox
//
//  La sveglia dei promemoria «urgenti».
//

import Foundation
import CryptoKit

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
import AlarmKit
import ActivityKit
import SwiftUI
#endif

/// Cosa sta suonando: distingue le sveglie di un to-do da quelle di un evento,
/// così due elementi con lo stesso id non si sovrascrivono a vicenda.
enum KBUrgentAlarmKind: String, Sendable {
    case todo
    case calendarEvent
}

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
/// Il carico utile che viaggia con la sveglia. AlarmKit lo conserva e lo
/// restituisce negli aggiornamenti: è l'unico modo di sapere *quale* to-do o
/// evento sta suonando senza tenere un registro parallelo.
struct KBAlarmMetadata: AlarmMetadata {
    var kindRaw: String
    var entityId: String
    var familyId: String
    var childId: String?
    var listId: String?
}
#endif

/// Una notifica locale non suona se il telefono è in silenzioso o in full
/// immersion: è una notifica, e il sistema la tratta come tale. Un promemoria
/// segnato **urgente** promette l'opposto — «avvisami comunque» — e l'unico
/// modo di mantenerlo su iOS è AlarmKit, che programma una *sveglia* vera, con
/// la stessa interfaccia a tutto schermo dell'app Orologio.
///
/// Il permesso è separato da quello delle notifiche e si chiede la prima volta
/// che si salva qualcosa di urgente: è lo stesso dialogo che mostra Promemoria
/// di Apple («Vuoi consentire a KidBox di programmare sveglie e timer?»).
///
/// **Quando non si può, si degrada invece di mentire.** Su Mac Catalyst
/// AlarmKit non è disponibile e il permesso si può negare: in entrambi i casi
/// il chiamante ripiega sulla notifica locale marcata `.timeSensitive`, che
/// almeno attraversa le full immersion quando l'utente lo consente.
enum KBUrgentAlarmService {

    /// `false` su Mac Catalyst, dove AlarmKit è dichiarato non disponibile.
    static var isSupported: Bool {
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// L'utente ha già negato le sveglie? Serve alla UI per dire perché
    /// «urgente» non suonerà, invece di lasciarglielo credere.
    static var isDenied: Bool {
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        return AlarmManager.shared.authorizationState == .denied
        #else
        return false
        #endif
    }

    /// Chiede il permesso alle sveglie, se non è ancora stato deciso.
    @discardableResult
    static func ensureAuthorization() async -> Bool {
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await AlarmManager.shared.requestAuthorization() == .authorized
            } catch {
                KBLog.app.kbError("[Alarm] requestAuthorization FAIL err=\(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
        #else
        return false
        #endif
    }

    /// Arma la sveglia di un elemento urgente.
    /// - Returns: `true` se la sveglia è armata; `false` se il chiamante deve
    ///   ripiegare sulla notifica locale.
    @discardableResult
    static func schedule(
        entityId: String,
        kind: KBUrgentAlarmKind,
        title: String,
        fireAt: Date,
        familyId: String,
        childId: String? = nil,
        listId: String? = nil
    ) async -> Bool {
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        // Una sveglia già scaduta non suona mai e resta appesa in elenco.
        guard fireAt > Date() else {
            cancel(entityId: entityId, kind: kind)
            return false
        }
        guard await ensureAuthorization() else {
            KBLog.app.kbInfo("[Alarm] non autorizzato: si ripiega sulla notifica id=\(entityId)")
            return false
        }

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: KBAlarmMetadata(
                kindRaw: kind.rawValue,
                entityId: entityId,
                familyId: familyId,
                childId: childId,
                listId: listId
            ),
            tintColor: Color.accentColor
        )
        let configuration = AlarmManager.AlarmConfiguration(
            schedule: .fixed(fireAt),
            attributes: attributes,
            sound: .default
        )

        do {
            _ = try await AlarmManager.shared.schedule(
                id: alarmId(entityId: entityId, kind: kind),
                configuration: configuration
            )
            KBLog.app.kbInfo("[Alarm] armata kind=\(kind.rawValue) id=\(entityId) fireAt=\(fireAt)")
            return true
        } catch {
            KBLog.app.kbError("[Alarm] schedule FAIL id=\(entityId): \(error.localizedDescription)")
            return false
        }
        #else
        return false
        #endif
    }

    /// Toglie la sveglia. Si chiama anche quando non ce n'è una: con un id
    /// sconosciuto AlarmKit lancia, e qui quell'errore non è un problema.
    static func cancel(entityId: String, kind: KBUrgentAlarmKind) {
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        do {
            try AlarmManager.shared.cancel(id: alarmId(entityId: entityId, kind: kind))
            KBLog.app.kbInfo("[Alarm] annullata kind=\(kind.rawValue) id=\(entityId)")
        } catch {
            // Nessuna sveglia con quell'id: è il caso normale quando si salva
            // un elemento che urgente non è mai stato.
        }
        #endif
    }

    /// Spegne tutte le sveglie KidBox. Serve al logout: una sveglia armata
    /// sopravvive alla cancellazione del database locale e continuerebbe a
    /// suonare per l'account precedente.
    static func cancelAll() {
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        guard let alarms = try? AlarmManager.shared.alarms else { return }
        for alarm in alarms {
            try? AlarmManager.shared.cancel(id: alarm.id)
        }
        KBLog.app.kbInfo("[Alarm] cancelAll — \(alarms.count) sveglie rimosse")
        #endif
    }

    // MARK: - Id

    /// L'id di una sveglia è un `UUID`; l'id di un to-do è una stringa che
    /// *quasi sempre* è un UUID — non quando arriva da Alexa. Derivarlo con un
    /// digest stabile copre entrambi i casi e resta idempotente: ripianificare
    /// lo stesso promemoria sostituisce la sveglia invece di aggiungerne una.
    static func alarmId(entityId: String, kind: KBUrgentAlarmKind) -> UUID {
        let digest = SHA256.hash(data: Data("\(kind.rawValue):\(entityId)".utf8))
        var bytes = Array(digest.prefix(16))
        // Versione 4 e variante RFC 4122: un UUID malformato viene accettato
        // ma rende irriconoscibile la sveglia negli elenchi di sistema.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
