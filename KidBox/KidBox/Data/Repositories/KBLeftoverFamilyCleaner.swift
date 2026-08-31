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
//  Gemello di `LeftoverFamilyCleaner` su Android, stesse regole.
//

import Foundation
import SwiftData
import FirebaseAuth

@MainActor
enum KBLeftoverFamilyCleaner {

    /// Da chiamare dopo un join riuscito: `keepFamilyId` non viene mai toccata.
    static func deleteEmptyOwnedFamilies(keepFamilyId: String, modelContext: ModelContext) async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }

        let famiglie = (try? modelContext.fetch(FetchDescriptor<KBFamily>())) ?? []
        for famiglia in famiglie where famiglia.id != keepFamilyId && famiglia.createdBy == uid {
            guard isEmptyLeftover(familyId: famiglia.id, modelContext: modelContext) else {
                KBLog.sync.kbInfo("Famiglia \(famiglia.id) non vuota: non la elimino")
                continue
            }
            do {
                try await FamilyLeaveService(modelContext: modelContext).deleteFamily(familyId: famiglia.id)
                KBLog.sync.kbInfo("Eliminata la famiglia residua \(famiglia.id)")
            } catch {
                KBLog.sync.kbError("Eliminazione famiglia residua fallita: \(error.localizedDescription)")
            }
        }
    }

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
}
