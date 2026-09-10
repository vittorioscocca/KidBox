//
//  AlexaAvailability.swift
//  KidBox
//
//  Se la skill Alexa vada mostrata o no, in un posto solo.
//

import Foundation

/// La skill Alexa esiste **solo in `it-IT`**: il nome di invocazione è
/// italiano e il backend risponde in italiano. Mostrarne le istruzioni a chi
/// usa l'app in un'altra lingua significa offrire una cosa che non può
/// installare, quindi la voce nelle impostazioni si nasconde.
///
/// Il segnale è la lingua **effettiva dell'app**, non `Locale.preferredLanguages`:
/// - chi sceglie «Italiano» dal selettore in-app tiene Alexa anche con il
///   telefono in un'altra lingua;
/// - chi ha il telefono in inglese ma regione Italia la tiene lo stesso, perché
///   `resolvedLanguageCode` risolve già quel caso in `it`. È il caso reale
///   dell'italiano che tiene il telefono in inglese e ha un Echo italiano:
///   nascondergli Alexa sarebbe stato l'errore peggiore dei due.
///
/// ⚠️ Nascondendo la voce si nasconde anche lo scollegamento. Chi ha già
/// collegato un account Alexa e poi passa a un'altra lingua non trova più il
/// pulsante: il collegamento resta valido, per gestirlo deve rimettere
/// l'italiano. Popolazione attesa ~0, ma se un giorno arriva una segnalazione
/// «non riesco a scollegare Alexa», la causa è questa.
enum AlexaAvailability {
    /// Codice della lingua in cui la skill esiste. Quando se ne aggiungeranno
    /// altre, questa diventa un insieme.
    private static let supportedLanguages: Set<String> = ["it"]

    static var isAvailable: Bool {
        supportedLanguages.contains(LanguageManager.shared.currentLanguageCode)
    }
}
