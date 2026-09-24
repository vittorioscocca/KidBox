//
//  KBLeftoverFamilyCleaner.swift
//  KidBox
//
//  Elimina la famiglia creata solo per superare l'onboarding, quando poi si
//  entra in quella vera su invito.
//
//  Chi installa l'app crea una famiglia per arrivare in fondo alla
//  configurazione iniziale, e subito dopo accetta l'invito della famiglia di
//  casa. Quella prima famiglia resta lì, vuota, e fa danni: occupa uno dei due
//  slot per account, e ogni pezzo di codice che deve scegliere "la famiglia" si
//  ritrova due candidate.
//
//  NON è una pulizia generica: un utente può benissimo avere una famiglia sua e
//  farsi invitare in un'altra (i nonni, l'ex partner). Si cancella solo ciò che
//  è dimostrabilmente un residuo:
//
//    - l'ha creata questo utente, e
//    - lui è l'unico membro attivo, e
//    - non contiene NIENTE: né figli, né documenti, wallet, esami, chat o eventi.
//
//  Se anche una sola di queste condizioni non regge, la famiglia resta dov'è.
//
//  ⚠️ Quelle tre condizioni vanno verificate **sul server**, non su SwiftData.
//  Il 23/09/2026 questa pulizia ha chiesto la cancellazione di una famiglia
//  d'origine viva — cinque membri, documenti, note e to-do — subito dopo un
//  join. Il motivo: il database locale di una famiglia **non attiva** è vuoto
//  per costruzione. Il bootstrap non ne scarica nemmeno i membri, e documenti,
//  wallet e chat arrivano solo dai listener della famiglia attiva: contarli in
//  locale significa contare ciò che non è mai stato scaricato. Quella volta la
//  famiglia si è salvata solo perché il presidio server rifiuta la
//  cancellazione con più di un membro attivo; con un membro solo sarebbe
//  sparita davvero, con tutto ciò che conteneva.
//
//  Da qui in poi il locale serve solo a scartare in fretta i casi ovvi: la
//  prova che autorizza la cancellazione arriva da Firestore, letta dal server
//  (`source: .server`, altrimenti risponde la cache con gli stessi buchi). E
//  vale la regola di `SyncCenter.verifyRevocation`: assenza di prove non è
//  prova. Se anche una sola lettura non riesce, non si cancella niente.
//
//  Gemello di `LeftoverFamilyCleaner` su Android, stesse regole.
//

import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore

@MainActor
enum KBLeftoverFamilyCleaner {

    /// Esito della verifica sul server.
    private enum ServerVerdict {
        /// Il server conferma: nessun altro membro attivo, nessun contenuto.
        case leftover
        /// Il server dice che la famiglia è viva: `reason` per il log.
        case inUse(String)
        /// Non è stato possibile saperlo (rete, regole, credenziali).
        case unknown(String)
    }

    /// Le sottocollezioni che dimostrano l'**uso** di una famiglia.
    ///
    /// Sono un sottoinsieme di `FAMILY_SUBCOLLECTIONS` in `functions/index.js`:
    /// restano fuori quelle che esistono anche in una famiglia mai usata e non
    /// proverebbero niente (`members`, `invites`, `locations`, `counters`,
    /// `stats`, `documentCategories`, `memberKeyBackups`) e quelle che sono
    /// figlie di un'altra (`routineChecks`, `geofenceEvents`).
    private static let contentCollections = [
        "children",
        "documents",
        "todos",
        "groceries",
        "calendarEvents",
        "events",
        "expenses",
        "medicalVisits",
        "medicalExams",
        "treatments",
        "vaccines",
        "pediatricProfiles",
        "photos",
        "notes",
        "chatMessages",
        "routines",
        "pets",
        "petEvents",
        "homeItems",
        "housePayments",
        "vehicles",
        "vehicleEvents",
        "walletTickets",
        "geofences",
    ]

    /// Da chiamare dopo un join riuscito: `keepFamilyId` non viene mai toccata.
    static func deleteEmptyOwnedFamilies(keepFamilyId: String, modelContext: ModelContext) async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }

        let famiglie = (try? modelContext.fetch(FetchDescriptor<KBFamily>())) ?? []
        for famiglia in famiglie where famiglia.id != keepFamilyId && famiglia.createdBy == uid {
            // Primo filtro, gratis: se il locale sa già di contenuti, è viva.
            // Il contrario non vale — vedi il commento in testa al file.
            guard isEmptyLeftover(familyId: famiglia.id, modelContext: modelContext) else {
                KBLog.sync.kbInfo("Famiglia \(famiglia.id) non vuota in locale: non la elimino")
                continue
            }

            switch await serverVerdict(familyId: famiglia.id, uid: uid) {
            case .inUse(let motivo):
                KBLog.sync.kbInfo("Famiglia \(famiglia.id) viva sul server (\(motivo)): non la elimino")
                continue
            case .unknown(let motivo):
                KBLog.sync.kbError("Famiglia \(famiglia.id): verifica sul server impossibile (\(motivo)). Nel dubbio non elimino")
                continue
            case .leftover:
                break
            }

            do {
                // `deleteFamilyIfServerConfirms` e non `deleteFamily`: il wipe
                // locale deve avvenire solo se il server ha davvero cancellato.
                // Il 23/09/2026 la Cloud Function ha rifiutato la richiesta e il
                // client ha cancellato lo stesso i dati locali, in silenzio: la
                // famiglia è sparita dall'app pur essendo intatta su Firestore.
                try await FamilyLeaveService(modelContext: modelContext)
                    .deleteFamilyIfServerConfirms(familyId: famiglia.id)
                KBLog.sync.kbInfo("Eliminata la famiglia residua \(famiglia.id)")
            } catch {
                KBLog.sync.kbError("Eliminazione famiglia residua fallita: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Prova locale (solo per scartare in fretta)

    private static func isEmptyLeftover(familyId: String, modelContext: ModelContext) -> Bool {
        func count<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) -> Int {
            (try? modelContext.fetchCount(FetchDescriptor<T>(predicate: predicate))) ?? 0
        }

        let membri = count(KBFamilyMember.self, #Predicate {
            $0.familyId == familyId && $0.isDeleted == false
        })
        guard membri <= 1 else { return false }

        return count(KBChild.self, #Predicate { $0.familyId == familyId }) == 0
            && count(KBDocument.self, #Predicate { $0.familyId == familyId && $0.isDeleted == false }) == 0
            && count(KBWalletTicket.self, #Predicate { $0.familyId == familyId && $0.isDeleted == false }) == 0
            && count(KBMedicalExam.self, #Predicate { $0.familyId == familyId && $0.isDeleted == false }) == 0
            && count(KBChatMessage.self, #Predicate { $0.familyId == familyId && $0.isDeleted == false }) == 0
            && count(KBCalendarEvent.self, #Predicate { $0.familyId == familyId && $0.isDeleted == false }) == 0
    }

    // MARK: - Prova sul server (l'unica che autorizza la cancellazione)

    /// Chiede a Firestore se la famiglia è davvero un residuo: un solo membro
    /// attivo (io) e nessun contenuto in nessuna sottocollezione.
    private static func serverVerdict(familyId: String, uid: String) async -> ServerVerdict {
        let famiglia = Firestore.firestore().collection("families").document(familyId)

        // 1) I membri. `source: .server` perché dalla cache una famiglia mai
        // sincronizzata risulta senza membri, che è esattamente l'errore da
        // evitare.
        let membri: QuerySnapshot
        do {
            membri = try await famiglia.collection("members").getDocuments(source: .server)
        } catch {
            return .unknown("membri non leggibili: \(error.localizedDescription)")
        }

        let attivi = membri.documents.filter { $0.data()["isDeleted"] as? Bool != true }
        guard attivi.count == 1 else {
            return .inUse("membri attivi=\(attivi.count)")
        }
        guard attivi[0].documentID == uid else {
            return .inUse("l'unico membro attivo non sono io")
        }

        // 2) I contenuti. Una riga qualsiasi in una qualsiasi di queste
        // collezioni basta a dire che la famiglia è stata usata: la pulizia
        // vale solo per una famiglia in cui non è mai entrato niente.
        for collezione in contentCollections {
            do {
                let snap = try await famiglia.collection(collezione)
                    .limit(to: 1)
                    .getDocuments(source: .server)
                if !snap.documents.isEmpty {
                    return .inUse("\(collezione) non è vuota")
                }
            } catch {
                return .unknown("\(collezione) non leggibile: \(error.localizedDescription)")
            }
        }

        return .leftover
    }
}
