//
//  KBNotificationCategoryRegistry.swift
//  KidBox
//
//  Punto unico di registrazione delle categorie di notifica con azioni rapide.
//
//  `setNotificationCategories` **sostituisce** l'intero insieme: registrare una
//  categoria da un altro punto dell'app cancellerebbe in silenzio le azioni
//  delle altre. Ogni categoria nuova va aggiunta qui.
//

import UserNotifications

enum KBNotificationCategoryRegistry {

    @MainActor
    static func registerAll() {
        UNUserNotificationCenter.current().setNotificationCategories([
            TreatmentNotificationCategory.category,
            FitnessPlanNotificationCategory.category,
        ])
        KBLog.app.kbDebug("Notification categories registered: terapie, piano fitness")
    }
}
