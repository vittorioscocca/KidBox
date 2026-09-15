//
//  InternalTraffic.swift
//  KidBox
//
//  Marca come «traffico interno» gli eventi GA4 degli account di test dello
//  sviluppatore, così il filtro «Traffico interno» di GA4 li tiene fuori dai
//  report.
//
//  Perché serve: con qualche decina di utenti attivi al giorno, un pomeriggio
//  di prove pesa come una settimana di utenti veri. Il 13/09/2026 cinque
//  registrazioni web e 136 aggiornamenti di password erano tutti dello
//  sviluppatore, e il 14/09 lo erano 28 messaggi AI: ogni volta il report
//  giornaliero ha dovuto «sospettare» invece di sapere.
//
//  Come funziona: dopo il login si confronta l'hash SHA-256 dell'email con un
//  elenco compilato qui (mai l'email in chiaro nel binario) e, se corrisponde,
//  si imposta il parametro di default `traffic_type = internal` su tutti gli
//  eventi successivi. È il parametro che GA4 usa per il suo filtro «Traffico
//  interno» (Amministrazione → Impostazioni dati → Filtri dati), che va
//  attivato una volta nella property. Al logout il parametro si toglie.
//
//  Cosa NON copre: gli eventi prima del login (`first_open`,
//  `pre_signup_screen_shown`) — a quel punto non si sa chi è. Sono pochi e
//  restano nel rumore di fondo dei dispositivi di test di Apple e Google.
//
//  Lo stesso elenco, come uid, sta in `config/internalUsers` su Firestore ed
//  esclude gli stessi account dal rollup analytics e dai report della console.
//

import CryptoKit
import FirebaseAnalytics
import FirebaseAuth
import Foundation

enum InternalTraffic {

    /// SHA-256 esadecimale delle email degli account di test, minuscole.
    /// Aggiornare qui e in `config/internalUsers.emailSha256`.
    private static let emailHashes: Set<String> = [
        "2932b8f0e073118c0ca7484c73ae1e33ba8b9e3011e4b78ae17da4dfb7c74f21",
        "ef18139763e351755d752d5ea05e5efc6aaf7a7dd666a9c559cda03236f540d3",
        "0b45a4dc93984656b8eec293859533018cc6d5dc3bac24d5c554d92bc8fb0486",
        "09ea5430711b0dc611c7eadf90e20a2072af2fc5224f0318ad82501e59d069d9",
        "e4876522f848d46ce31670b18e6e90486e6c90b41107670a199f98d46cff8aa3",
    ]

    static func isInternal(_ user: User?) -> Bool {
        guard let user else { return false }
        // Con Apple «nascondi la mia email» `user.email` è un relay: si guardano
        // anche le email dei provider, dove può esserci quella vera.
        var emails = user.providerData.compactMap(\.email)
        if let e = user.email { emails.append(e) }
        return emails.contains { emailHashes.contains(sha256Hex($0)) }
    }

    /// Da chiamare a ogni cambio di stato di autenticazione.
    static func apply(user: User?) {
        if isInternal(user) {
            Analytics.setDefaultEventParameters(["traffic_type": "internal"])
            KBLog.app.kbInfo("[Analytics] account di test: traffic_type=internal")
        } else {
            Analytics.setDefaultEventParameters(nil)
        }
    }

    private static func sha256Hex(_ email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
