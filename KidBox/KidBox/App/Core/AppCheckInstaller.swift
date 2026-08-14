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
    public static func install() {
#if DEBUG || targetEnvironment(simulator)
        // Debug sul Simulatore (dove App Attest non esiste) o in build di test.
        // Il check copre anche una Release lanciata nel Simulatore: senza,
        // tenterebbe App Attest e fallirebbe a ogni avvio.
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
}
