//
//  KBFeatureFlags.swift
//  KidBox
//
//  Interruttori che devono poter cambiare senza pubblicare una versione.
//
//  Nasce per il pulsante «Continua con Facebook». L'app Meta di KidBox è in
//  modalità sviluppo, quindi chi non ha un ruolo su di essa riceve «questa app
//  non funziona e lo sviluppatore ne è a conoscenza» — una frase che l'utente
//  legge come «KidBox è rotta», non come «questo provider è spento». Su 256
//  registrazioni un solo login Facebook è andato a buon fine, ed era quello
//  dello sviluppatore.
//
//  Il pulsante quindi va tolto, ma il giorno in cui Meta approva la
//  pubblicazione deve poter tornare **senza** una nuova release e senza
//  riattraversare la review degli store: da qui l'interruttore remoto.
//
//  Perché Remote Config e non Firestore. La schermata di login sta **prima**
//  dell'autenticazione, e ogni documento sotto `config/` richiede `isSignedIn()`
//  (`firestore.rules:41-42`): un flag lì sarebbe illeggibile proprio dove serve.
//  Remote Config si legge senza account.
//
//  Il valore vive in tre posti, dal più pronto al più autorevole:
//
//  1. il **default compilato**, usato al primissimo avvio e offline;
//  2. `UserDefaults`, l'ultimo valore visto — serve a disegnare la schermata
//     subito, senza far comparire un pulsante che un istante dopo sparisce;
//  3. **Remote Config**, la verità, recuperata a ogni avvio.
//
//  Il default è **spento**. Se la fetch non arriva mai — rete assente, primo
//  avvio, console non ancora configurata — resta lo stato che vogliamo oggi.
//  Un default acceso rimetterebbe il pulsante rotto davanti a chi è offline,
//  cioè esattamente il caso peggiore.
//
//  Gemello di `KBFeatureFlags` su Android: stessa chiave remota, stesso default.
//

import Foundation
import FirebaseRemoteConfig

enum KBFeatureFlags {

    // MARK: - Chiavi

    /// Chiave su Firebase Remote Config. Identica su Android: un solo parametro
    /// in console governa entrambe le piattaforme.
    static let facebookLoginRemoteKey = "facebook_login_enabled"

    /// Cache locale. È `static let` e non una stringa sparsa perché `LoginView`
    /// la legge con `@AppStorage`: così la schermata si ridisegna da sola se il
    /// valore cambia mentre l'app è aperta.
    static let facebookLoginDefaultsKey = "kb_facebookLoginEnabled"

    /// Spento finché Meta non pubblica l'app.
    private static let facebookLoginFallback = false

    // MARK: - Lettura

    /// `object(forKey:)` e non `bool(forKey:)`: quest'ultimo non distingue
    /// "mai scritta" da `false`, e qui la differenza conterà il giorno in cui il
    /// default compilato tornerà `true`.
    static var isFacebookLoginEnabled: Bool {
        UserDefaults.standard.object(forKey: facebookLoginDefaultsKey) as? Bool
            ?? facebookLoginFallback
    }

    // MARK: - Remote Config

    private static let remoteConfig: RemoteConfig = {
        let config = RemoteConfig.remoteConfig()
        config.setDefaults([
            facebookLoginRemoteKey: NSNumber(value: facebookLoginFallback)
        ])

        let settings = RemoteConfigSettings()
        // In debug si rilegge a ogni avvio, così una modifica in console si
        // verifica subito. In release un'ora: il flag cambia una volta all'anno,
        // non vale una chiamata di rete a ogni apertura.
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 3600
        #endif
        config.configSettings = settings

        return config
    }()

    /// Allinea la cache locale al valore remoto.
    ///
    /// Va chiamata subito dopo `FirebaseApp.configure()`. Non si attende: la
    /// schermata di login parte con la cache e, se il valore è cambiato,
    /// `@AppStorage` la aggiorna quando la risposta arriva.
    static func refresh() async {
        do {
            try await remoteConfig.fetchAndActivate()
            let enabled = remoteConfig[facebookLoginRemoteKey].boolValue
            UserDefaults.standard.set(enabled, forKey: facebookLoginDefaultsKey)
            KBLog.auth.kbInfo("FeatureFlags: \(facebookLoginRemoteKey)=\(enabled)")
        } catch {
            // Nessun fallback qui: senza risposta resta l'ultimo valore noto,
            // che è già la scelta giusta dell'ultima volta.
            KBLog.auth.kbError("FeatureFlags: fetch fallita, resta la cache locale")
        }
    }
}
