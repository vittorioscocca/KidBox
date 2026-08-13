//
//  FamilyCreationError.swift
//  KidBox
//
//  Errore mostrato in UI quando la creazione di una famiglia viene rifiutata
//  da Firestore. Oggi l'unico motivo realistico di rifiuto in questo punto
//  sono le firestore.rules sul limite di 2 famiglie per account
//  (vedi `ownedFamilyCount()` in firestore.rules): mappiamo quindi ogni
//  permission-denied su una create famiglia a questo messaggio, invece di
//  mostrare l'eccezione Firestore grezza.
//

import Foundation
import FirebaseFirestore

enum FamilyCreationError: LocalizedError {
    case familyLimitReached
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .familyLimitReached:
            return NSLocalizedString(
                "Hai raggiunto il limite di 2 famiglie per account. Elimina una famiglia esistente per crearne una nuova.",
                comment: "Error shown when the user tries to create a 3rd family"
            )
        case .underlying(let error):
            return error.localizedDescription
        }
    }

    /// Rimappa un errore di creazione famiglia: permission-denied → limite raggiunto, altrimenti invariato.
    ///
    /// Riimplementa qui il check invece di chiamare `SyncCenter.isPermissionDenied`
    /// (equivalente, stesso dominio/codice Firestore): quel metodo è `@MainActor`
    /// mentre questa funzione deve restare chiamabile anche da contesti non isolati.
    static func map(_ error: Error) -> FamilyCreationError {
        let ns = error as NSError
        let isPermissionDenied = ns.domain == FirestoreErrorDomain
            && ns.code == FirestoreErrorCode.permissionDenied.rawValue
        return isPermissionDenied ? .familyLimitReached : .underlying(error)
    }
}
