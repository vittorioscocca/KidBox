//
//  FamilyKeyMissing.swift
//  KidBox
//
//  Testo unico per il caso "manca la chiave di famiglia".
//
//  Il caso si presenta in Documenti, Wallet, Chat e Foto — sono tutti cifrati
//  con la stessa master key — e prima ogni area diceva la sua: Documenti
//  parlava di iCloud Portachiavi, Wallet di "chiave non disponibile", le altre
//  mostravano l'errore tecnico grezzo. Nessuna spiegava come uscirne.
//
//  Qui c'è una sola formulazione, che dice cosa manca, cosa non funziona di
//  conseguenza e — soprattutto — l'unica azione che risolve davvero:
//  farsi rifare l'invito QR da chi ha creato la famiglia.
//

import Foundation

enum FamilyKeyMissing {

    // `String(localized:)` e non stringhe nude: `Text(String)` in SwiftUI usa
    // l'inizializzatore verbatim e NON localizza — solo i literal lo fanno.
    // Con le stringhe nude il messaggio sarebbe rimasto in italiano in tutte e
    // quattro le lingue. Le chiavi sono il testo italiano, come nel resto del
    // progetto (String Catalog con sourceLanguage "it").

    /// Titolo per alert e intestazioni.
    static var title: String {
        String(localized: "Chiave di famiglia mancante")
    }

    /// Corpo del messaggio: causa, conseguenza, azione.
    static var message: String {
        String(localized: "Su questo dispositivo manca la chiave che protegge i contenuti condivisi, quindi documenti, wallet, foto e allegati della chat non possono essere aperti.\n\nPer recuperarla, fatti invitare di nuovo da chi ha creato la famiglia e inquadra il codice QR che genera.")
    }

    /// Versione su una riga, per spazi stretti (righe di errore, toast, celle).
    static var shortMessage: String {
        String(localized: "Manca la chiave di famiglia: fatti invitare di nuovo da chi ha creato la famiglia e inquadra il suo codice QR.")
    }

    /// Errore da lanciare quando la chiave non è recuperabile.
    ///
    /// Usa `shortMessage` come `localizedDescription`, così ogni schermata che
    /// già mostra `error.localizedDescription` si allinea senza modifiche.
    static func error() -> NSError {
        NSError(
            domain: "KidBox.FamilyKey",
            code: -10,
            userInfo: [NSLocalizedDescriptionKey: shortMessage]
        )
    }

    /// `true` se l'errore rappresenta una chiave di famiglia assente.
    ///
    /// Copre i tre modi in cui il caso può arrivare: l'errore del crypto dei
    /// documenti, quello delle password e l'`NSError` prodotto da [error()].
    static func matches(_ error: Error) -> Bool {
        if let crypto = error as? DocumentCryptoService.CryptoError,
           case .missingFamilyKey = crypto {
            return true
        }
        if let pwd = error as? PasswordCypher.PasswordCryptoError,
           case .missingFamilyKey = pwd {
            return true
        }
        let ns = error as NSError
        return ns.domain == "KidBox.FamilyKey" && ns.code == -10
    }
}

// MARK: - localizedDescription dei due errori di crypto
//
// Senza queste conformità gli errori arrivavano alla UI come stringhe tecniche
// ("The operation couldn't be completed…"). Dandogli un messaggio, ogni
// schermata che già mostra `error.localizedDescription` — Chat, Foto, Wallet,
// anteprime — si allinea da sola, senza doverla modificare una per una.

extension DocumentCryptoService.CryptoError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingFamilyKey: return FamilyKeyMissing.shortMessage
        case .invalidCipher:    return String(localized: "Contenuto non leggibile: il file risulta danneggiato.")
        }
    }
}

extension PasswordCypher.PasswordCryptoError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingFamilyKey:
            return FamilyKeyMissing.shortMessage
        case .missingCurrentUser:
            return String(localized: "Sessione scaduta: accedi di nuovo.")
        case .notCreatorForPrivateEntry:
            return String(localized: "Questa voce è privata: può aprirla solo chi l'ha creata.")
        case .invalidUTF8, .invalidCipher:
            return String(localized: "Contenuto non leggibile: il dato risulta danneggiato.")
        }
    }
}
