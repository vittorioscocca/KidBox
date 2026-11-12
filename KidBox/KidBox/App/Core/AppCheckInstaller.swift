//
//  AppCheckInstaller.swift
//  KidBox
//
//  Created by vscocca on 14/08/2026.
//

import Foundation
import FirebaseCore
import FirebaseAppCheck

public struct AppCheckInstaller {

    /// Chiave in cui AppCheckCore conserva il token di debug.
    /// Sorgente: `GACAppCheckDebugProvider.m` (`kDebugTokenUserDefaultsKey`).
    /// L'ordine di precedenza del provider è: variabile d'ambiente
    /// `AppCheckDebugToken` → `FIRAAppCheckDebugToken` (deprecata) → questa
    /// chiave → token nuovo generato a caso e salvato qui.
    private static let debugTokenDefaultsKey = "GACAppCheckDebugToken"

    public static func install() {
#if DEBUG || targetEnvironment(simulator)
        // Debug sul Simulatore (dove App Attest non esiste) o in build di test.
        // Il check copre anche una Release lanciata nel Simulatore: senza,
        // tenterebbe App Attest e fallirebbe a ogni avvio.
        applyFixedDebugTokenIfPresent()
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
#else
        // In produzione usa AppAttest (iOS 14+) o DeviceCheck
        class ProductionAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
            func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
                if #available(iOS 14.0, *) {
                    return AppAttestProvider(app: app)
                } else {
                    return DeviceCheckProvider(app: app)
                }
            }
        }
        AppCheck.setAppCheckProviderFactory(ProductionAppCheckProviderFactory())
#endif
    }

#if DEBUG || targetEnvironment(simulator)
    /// Impone il token di debug fisso del progetto, così ogni simulatore e ogni
    /// device nuovo nasce già coperto.
    ///
    /// Senza questo, il provider genera un UUID per device e lo conserva: ogni
    /// simulatore nuovo, ogni iPhone su cui si lancia da Xcode e ogni
    /// cancellazione dell'app apre un buco che si vede solo giorni dopo, come
    /// richieste `INVALID` nelle metriche di App Check. È costato tre giri di
    /// diagnosi fra il 10 e il 12/11/2026.
    ///
    /// Il valore arriva da `AppCheck.local.xcconfig` (non versionato) via la
    /// chiave `KBAppCheckDebugToken` in Info.plist, ed è vuoto in Release
    /// perché un token di debug nel binario pubblicato sarebbe un bypass di
    /// App Check per l'intero progetto.
    private static func applyFixedDebugTokenIfPresent() {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "KBAppCheckDebugToken") as? String else {
            return
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        // Se l'xcconfig locale manca, la variabile non è risolta e resta il
        // letterale `$(APP_CHECK_DEBUG_TOKEN)`: non è un token, va ignorato.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return }
        guard UserDefaults.standard.string(forKey: debugTokenDefaultsKey) != trimmed else { return }
        UserDefaults.standard.set(trimmed, forKey: debugTokenDefaultsKey)
    }
#endif
}
