//
//  KBTreatmentScope.swift
//  KidBox
//
//  Di chi può parlare un avviso proattivo (dose da registrare, briefing del
//  mattino, sintesi della settimana). Le cure sono di tutta la famiglia, ma chi
//  riceve la notifica deve sentire parlare solo di sé e dei bambini registrati:
//  la cura di un altro adulto è sua, e lui la legge dal suo telefono.
//
//  Vale solo per ciò che parte da solo. L'assistente in chat e la sezione Salute
//  continuano a vedere tutta la famiglia, perché lì è l'utente a chiedere.
//

import Foundation
import SwiftData

enum KBTreatmentScope {

    /// Id dei profili di cui `uid` può ricevere avvisi: lui stesso e i bambini
    /// registrati nella famiglia. Gli altri adulti (`childId` = loro uid) restano fuori.
    @MainActor
    static func subjectIds(familyId: String, uid: String, context: ModelContext) -> Set<String> {
        let fid: String? = familyId
        let kids = (try? context.fetch(FetchDescriptor<KBChild>(
            predicate: #Predicate { $0.familyId == fid }
        ))) ?? []
        return Set(kids.map(\.id)).union(uid.isEmpty ? [] : [uid])
    }

    /// La cura riguarda me, un bambino registrato o un animale della famiglia?
    static func includes(childId: String, petId: String, subjects: Set<String>) -> Bool {
        !petId.isEmpty || subjects.contains(childId)
    }

    @MainActor
    static func filter(_ treatments: [KBTreatment], familyId: String, uid: String, context: ModelContext) -> [KBTreatment] {
        let subjects = subjectIds(familyId: familyId, uid: uid, context: context)
        return treatments.filter { includes(childId: $0.childId, petId: $0.petId, subjects: subjects) }
    }
}
