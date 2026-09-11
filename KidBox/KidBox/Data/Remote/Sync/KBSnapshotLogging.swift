//
//  KBSnapshotLogging.swift
//  KidBox
//
//  Una riga di log per ogni snapshot Firestore, con la sola informazione che
//  serve a capire quanto costa davvero un avvio: **quanti documenti arrivano
//  dal server e quanti dalla cache**.
//
//  Perché esiste. L'11/09/2026, misurando due avvii isolati dell'app con la
//  metrica `firestore.googleapis.com/document/read_count`, un'apertura è
//  costata ~770 letture. I dieci store che già loggavano `fromCache`
//  riportavano tutti `changes=0 fromCache=false` — cioè il server non stava
//  ritrasferendo nulla — quindi quelle letture venivano dai ventitré store che
//  non loggavano niente, e non c'era modo di sapere quale. Senza questa riga
//  ogni ipotesi su dove intervenire è un'ipotesi.
//
//  Come si legge:
//  - `fromCache=true`  → consegna locale, non costa letture;
//  - `fromCache=false` con `changes=0` → il server ha confermato il set
//    invariato (existence filter) senza trasferire documenti: costa pochissimo;
//  - `fromCache=false` con `changes>0` → documenti davvero scaricati: è questo
//    che si paga, ed è questo che va ridotto.
//

import Foundation
import FirebaseFirestore

extension QuerySnapshot {

    /// Logga dimensione, delta e provenienza dello snapshot.
    /// - Parameter tag: nome breve dello store, per ritrovarlo nei log.
    func kbLogSnapshot(_ tag: String) {
        KBLog.sync.kbDebug(
            "[\(tag)] snapshot docs=\(documents.count) changes=\(documentChanges.count) fromCache=\(metadata.isFromCache)"
        )
    }
}
