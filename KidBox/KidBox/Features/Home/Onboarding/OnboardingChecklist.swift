//
//  OnboardingChecklist.swift
//  KidBox
//
//  Checklist "Per iniziare": i cinque passi che trasformano un'installazione in
//  una famiglia che usa KidBox davvero.
//
//  Perché una checklist e non l'ennesima card promozionale. La Home aveva già
//  tre modi di suggerire cosa fare — il carosello promo, la card di invito e la
//  lista Suggerimenti — e nessuno dei tre sapeva cosa l'utente avesse già fatto:
//  il carosello propone "Invita nuovi membri" anche a chi ha quattro membri. Il
//  solo componente che quel profilo lo calcola davvero è `NudgeEngine.Signals`,
//  ma parla unicamente via notifica push, cioè fuori dall'app. Questa checklist
//  è quello stesso profilo reso visibile dentro la Home.
//
//  Due regole che ne determinano quasi tutto il comportamento:
//
//  1. **Le spunte sono derivate, mai manuali.** Un passo si chiude perché il
//     dato esiste (un documento caricato, un secondo membro nella famiglia), non
//     perché qualcuno ha toccato un cerchietto. Una checklist che si spunta da
//     sola quando fai la cosa è un feedback; una che si spunta al tap è un
//     adempimento.
//
//  2. **La selezione dei cinque passi si congela alla prima valutazione.** Serve
//     a distinguere due casi che altrimenti si confondono: un passo *non
//     applicabile all'inizio* (permesso notifiche già concesso) va sostituito
//     prima di mostrare la card; un passo *completato mentre la checklist vive*
//     deve restare al suo posto e mostrarsi spuntato — è la ricompensa. Congelare
//     dà anche l'ordine stabile: la leggibilità di una lista del genere viene
//     dalla posizione fissa delle righe.
//

import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Passi

/// I passi disponibili. L'ordine di `core` è l'ordine mostrato; `bench` entra
/// solo per rimpiazzare i passi core già chiusi alla prima valutazione.
enum OnboardingStepID: String, CaseIterable {
    case notifications
    case invite
    case document
    case photo
    case calendarEvent
    // Panchina.
    case expense
    case note
    case grocery

    /// I cinque passi che vogliamo davvero: permesso, rete, contenuto, ricordo,
    /// impegno condiviso. Coprono le tre curve di attivazione (rete, contenuto,
    /// abitudine) invece di insistere su una sola area.
    static let core: [OnboardingStepID] = [
        .notifications, .invite, .document, .photo, .calendarEvent
    ]

    /// Riserve, per chi arriva con qualche passo core già chiuso — tipicamente
    /// chi entra in una famiglia già popolata tramite QR.
    static let bench: [OnboardingStepID] = [.expense, .note, .grocery]

    /// Quanti passi mostra la card. Cinque è il numero oltre il quale una lista
    /// di cose da fare smette di leggersi come un invito e inizia a leggersi
    /// come un compito.
    static let displayCount = 5

    var title: LocalizedStringKey {
        switch self {
        case .notifications:  return "Abilita le notifiche"
        case .invite:         return "Invita un familiare"
        case .document:       return "Carica il primo documento"
        case .photo:          return "Condividi la prima foto"
        case .calendarEvent:  return "Aggiungi un evento in calendario"
        case .expense:        return "Registra la prima spesa"
        case .note:           return "Scrivi la prima nota"
        case .grocery:        return "Aggiungi qualcosa alla spesa"
        }
    }

    var symbol: String {
        switch self {
        case .notifications:  return "bell.badge.fill"
        case .invite:         return "person.badge.plus"
        case .document:       return "doc.text.fill"
        case .photo:          return "photo.fill"
        case .calendarEvent:  return "calendar"
        case .expense:        return "eurosign.circle.fill"
        case .note:           return "note.text"
        case .grocery:        return "cart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notifications:  return .orange
        case .invite:         return .teal
        case .document:       return .orange
        case .photo:          return .pink
        case .calendarEvent:  return .purple
        case .expense:        return .mint
        case .note:           return .yellow
        case .grocery:        return .green
        }
    }

    /// Dove porta il tap. `nil` per le notifiche: il permesso si chiede sul
    /// posto, mandare l'utente in una schermata per poi mostrargli un dialog di
    /// sistema aggiungerebbe un passaggio senza aggiungere niente.
    func destination(familyId: String) -> HomeDestination? {
        switch self {
        case .notifications:  return nil
        case .invite:         return .inviteCode
        case .document:       return .document
        case .photo:          return .familyPhotos(familyId: familyId)
        case .calendarEvent:  return .calendar(familyId: familyId)
        case .expense:        return .expenses(familyId: familyId)
        case .note:           return .notes(familyId: familyId)
        case .grocery:        return .shopping(familyId: familyId)
        }
    }
}

// MARK: - Segnali

/// Fotografia dello stato dell'utente, letta dal database locale e dal sistema.
/// Stessa natura dei `NudgeEngine.Signals`: costruita per una valutazione e mai
/// persistita. Nessuna query di rete, nessun profilo per-utente lato server.
struct OnboardingSignals {
    var notificationsAuthorized = false
    var familyMembers = 0
    /// Passi chiusi dalla presenza di un contenuto.
    var contentDone: Set<OnboardingStepID> = []

    func isComplete(_ step: OnboardingStepID) -> Bool {
        switch step {
        case .notifications: return notificationsAuthorized
        case .invite:        return familyMembers >= 2
        default:             return contentDone.contains(step)
        }
    }

    @MainActor
    static func build(
        modelContext: ModelContext,
        familyId: String,
        notificationsAuthorized: Bool
    ) -> OnboardingSignals {
        func count<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) -> Int {
            (try? modelContext.fetchCount(FetchDescriptor<T>(predicate: predicate))) ?? 0
        }

        var signals = OnboardingSignals()
        signals.notificationsAuthorized = notificationsAuthorized
        signals.familyMembers = count(KBFamilyMember.self, #Predicate {
            $0.familyId == familyId && $0.isDeleted == false
        })

        if count(KBDocument.self, #Predicate {
            $0.familyId == familyId && $0.isDeleted == false
        }) > 0 { signals.contentDone.insert(.document) }

        if count(KBFamilyPhoto.self, #Predicate {
            $0.familyId == familyId && $0.isDeleted == false
        }) > 0 { signals.contentDone.insert(.photo) }

        if count(KBCalendarEvent.self, #Predicate {
            $0.familyId == familyId && $0.isDeleted == false
        }) > 0 { signals.contentDone.insert(.calendarEvent) }

        if count(KBExpense.self, #Predicate {
            $0.familyId == familyId && $0.isDeleted == false
        }) > 0 { signals.contentDone.insert(.expense) }

        if count(KBNote.self, #Predicate {
            $0.familyId == familyId && $0.isDeleted == false
        }) > 0 { signals.contentDone.insert(.note) }

        if count(KBGroceryItem.self, #Predicate {
            $0.familyId == familyId && $0.isDeleted == false
        }) > 0 { signals.contentDone.insert(.grocery) }

        return signals
    }
}

// MARK: - Stato persistito

/// Quello che va salvato è pochissimo, ed è tutto ciò che *non* si può ricavare
/// dai dati: la selezione congelata, le due uscite (chiusa a mano, o soppressa
/// perché inutile) e il momento del completamento. Le spunte no: quelle si
/// ricalcolano, così non possono raccontare una cosa diversa dal database.
enum OnboardingChecklistState {

    /// Istante in cui il processo ha toccato la checklist la prima volta: serve
    /// solo a riconoscere "la sessione in cui è stata completata", per non far
    /// sparire la card nello stesso istante dell'ultima spunta.
    static let launchDate = Date()

    private static let stepsKey = "kb_onboardingChecklistSteps"
    private static let dismissedKey = "kb_onboardingChecklistDismissed"
    private static let suppressedKey = "kb_onboardingChecklistSuppressed"
    private static let completedAtKey = "kb_onboardingChecklistCompletedAt"
    private static let shownLoggedKey = "kb_onboardingChecklistShownLogged"
    private static let completedLoggedKey = "kb_onboardingChecklistCompletedLogged"
    private static let forcedKey = "kb_onboardingChecklistForced"

    private static var defaults: UserDefaults { .standard }

    /// Selezione congelata. Vuota = non ancora decisa.
    static var steps: [OnboardingStepID] {
        get {
            (defaults.string(forKey: stepsKey) ?? "")
                .split(separator: ",")
                .compactMap { OnboardingStepID(rawValue: String($0)) }
        }
        set {
            defaults.set(newValue.map(\.rawValue).joined(separator: ","), forKey: stepsKey)
        }
    }

    /// L'utente ha chiuso la card. Recuperabile dai Suggerimenti.
    static var isDismissed: Bool {
        get { defaults.bool(forKey: dismissedKey) }
        set { defaults.set(newValue, forKey: dismissedKey) }
    }

    /// La checklist non aveva senso per questo utente (già attivo all'arrivo).
    /// Diverso da `isDismissed`: qui non è mai stata mostrata, e riproporla
    /// dopo non avrebbe più senso di quanto ne avesse la prima volta.
    static var isSuppressed: Bool {
        get { defaults.bool(forKey: suppressedKey) }
        set { defaults.set(newValue, forKey: suppressedKey) }
    }

    /// Istante dell'ultima spunta. `nil` finché non sono chiusi tutti e cinque.
    static var completedAt: Date? {
        get {
            let t = defaults.double(forKey: completedAtKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: completedAtKey)
        }
    }

    /// Passi per cui l'evento `shown` è già partito: si registra una volta per
    /// passo per utente, altrimenti il denominatore conterebbe le aperture della
    /// Home invece delle persone.
    static func markShownIfNeeded(_ step: OnboardingStepID) -> Bool {
        markOnce(step, key: shownLoggedKey)
    }

    /// Stessa logica per il completamento: la card si ridisegna a ogni apertura
    /// della Home, ma un passo si chiude una volta sola.
    static func markCompletedIfNeeded(_ step: OnboardingStepID) -> Bool {
        markOnce(step, key: completedLoggedKey)
    }

    private static func markOnce(_ step: OnboardingStepID, key: String) -> Bool {
        let raw = defaults.string(forKey: key) ?? ""
        var logged = Set(raw.split(separator: ",").map(String.init))
        guard !logged.contains(step.rawValue) else { return false }
        logged.insert(step.rawValue)
        defaults.set(logged.sorted().joined(separator: ","), forKey: key)
        return true
    }

    /// L'utente ha chiesto lui la checklist. Sospende i due filtri che servono a
    /// non importunare chi non ne ha bisogno: chi la chiede esplicitamente ne ha
    /// bisogno per definizione, e negargliela perché "sembra già attivo" sarebbe
    /// il prodotto che contraddice una richiesta diretta.
    static var isForced: Bool {
        get { defaults.bool(forKey: forcedKey) }
        set { defaults.set(newValue, forKey: forcedKey) }
    }

    /// Riporta la card dopo una chiusura manuale (dalla schermata Suggerimenti).
    static func restore() {
        isDismissed = false
        isSuppressed = false
        isForced = true
    }

    /// I passi che la Home sta effettivamente proponendo adesso. Vuoto se la
    /// checklist non è in scena, per qualunque ragione: la usa il motore dei
    /// nudge per non chiedere via push quello che è già scritto in Home.
    static var liveSteps: [OnboardingStepID] {
        guard !isDismissed, !isSuppressed, completedAt == nil else { return [] }
        return steps
    }

    /// Esiste una checklist da poter riaprire? Una già completata non si
    /// ripropone: non è una funzione, è un percorso, e i percorsi finiscono.
    static var isRestorable: Bool {
        completedAt == nil && (isDismissed || isSuppressed)
    }

#if DEBUG
    /// Solo per le anteprime e i test manuali.
    static func reset() {
        defaults.removeObject(forKey: stepsKey)
        defaults.removeObject(forKey: dismissedKey)
        defaults.removeObject(forKey: suppressedKey)
        defaults.removeObject(forKey: completedAtKey)
        defaults.removeObject(forKey: shownLoggedKey)
        defaults.removeObject(forKey: completedLoggedKey)
        defaults.removeObject(forKey: forcedKey)
    }
#endif
}

// MARK: - Modello

/// Una riga della card: il passo e il suo stato al momento del calcolo.
struct OnboardingChecklistItem: Identifiable {
    let step: OnboardingStepID
    let isComplete: Bool
    var id: OnboardingStepID { step }
}

@MainActor
final class OnboardingChecklistModel: ObservableObject {

    @Published private(set) var rows: [OnboardingChecklistItem] = []
    @Published private(set) var isVisible = false
    /// Tutti e cinque chiusi *in questa sessione*: la card resta, con il suo
    /// stato di arrivo, e sparirà alla prossima apertura. Toglierla nell'istante
    /// dell'ultima spunta significherebbe togliere la ricompensa di aver finito.
    @Published private(set) var isCelebrating = false

    /// Solo per non far partire due richieste di permesso da un doppio tap:
    /// nessuna vista la osserva, il feedback lo dà il dialog di sistema.
    private var isRequestingNotifications = false

    var completedCount: Int { rows.filter(\.isComplete).count }
    var totalCount: Int { rows.count }

    /// Ricalcola tutto: da chiamare all'apparire della Home e a ogni ritorno in
    /// foreground. Costa una manciata di `fetchCount` locali, e ricalcolare
    /// evita l'errore peggiore — una riga che chiede di fare una cosa già fatta.
    func refresh(modelContext: ModelContext, familyId: String) async {
        guard !familyId.isEmpty else {
            isVisible = false
            return
        }
        guard !OnboardingChecklistState.isDismissed,
              !OnboardingChecklistState.isSuppressed else {
            isVisible = false
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional

        let signals = OnboardingSignals.build(
            modelContext: modelContext,
            familyId: familyId,
            notificationsAuthorized: authorized
        )

        let selection = OnboardingChecklistState.steps.isEmpty
            ? freezeSelection(signals: signals)
            : OnboardingChecklistState.steps

        guard !selection.isEmpty else {
            isVisible = false
            return
        }

        let newRows = selection.map {
            OnboardingChecklistItem(step: $0, isComplete: signals.isComplete($0))
        }
        let allDone = newRows.allSatisfy(\.isComplete)

        if allDone, OnboardingChecklistState.completedAt == nil {
            OnboardingChecklistState.completedAt = Date()
        }

        // Completata in una sessione precedente: ha finito il suo lavoro.
        if let completedAt = OnboardingChecklistState.completedAt,
           completedAt < OnboardingChecklistState.launchDate {
            isVisible = false
            return
        }

        rows = newRows
        isCelebrating = allDone
        isVisible = true

        for row in newRows {
            if OnboardingChecklistState.markShownIfNeeded(row.step) {
                await KBAnalytics.shared.logOnboarding(action: "shown", step: row.step.rawValue)
            }
            if row.isComplete, OnboardingChecklistState.markCompletedIfNeeded(row.step) {
                await KBAnalytics.shared.logOnboarding(action: "completed", step: row.step.rawValue)
            }
        }
    }

    /// Decide una volta per tutte quali cinque passi mostrare.
    ///
    /// Chi arriva con almeno tre passi core già chiusi non è un utente da
    /// attivare: è entrato in una famiglia che già funziona. Una checklist quasi
    /// tutta spuntata al primo sguardo non insegna niente e si legge come un bug,
    /// quindi a quell'utente non si mostra affatto.
    private func freezeSelection(signals: OnboardingSignals) -> [OnboardingStepID] {
        let forced = OnboardingChecklistState.isForced
        let coreDone = OnboardingStepID.core.filter { signals.isComplete($0) }.count

        if !forced, coreDone >= 3 {
            OnboardingChecklistState.isSuppressed = true
            return []
        }

        let candidates = (OnboardingStepID.core + OnboardingStepID.bench)
            .filter { !signals.isComplete($0) }

        // Meno di cinque passi aperti in tutto il catalogo: l'utente si è già
        // mosso abbastanza da rendere la card una ripetizione. Su richiesta
        // esplicita basta che ne resti almeno uno: meglio una lista corta di un
        // rifiuto senza spiegazione.
        let minimum = forced ? 1 : OnboardingStepID.displayCount
        guard candidates.count >= minimum else {
            OnboardingChecklistState.isSuppressed = true
            return []
        }

        let selection = Array(candidates.prefix(OnboardingStepID.displayCount))
        OnboardingChecklistState.steps = selection
        return selection
    }

    // MARK: - Azioni

    func dismiss() {
        OnboardingChecklistState.isDismissed = true
        isVisible = false
        Task { await KBAnalytics.shared.logOnboarding(action: "dismissed", step: "card") }
    }

    /// Gestisce il tap su una riga. Restituisce la destinazione da aprire, se il
    /// passo ne ha una: la navigazione resta responsabilità della Home, che è
    /// l'unica a possedere il coordinator.
    func handleTap(_ step: OnboardingStepID, familyId: String) -> HomeDestination? {
        Task { await KBAnalytics.shared.logOnboarding(action: "tapped", step: step.rawValue) }

        guard step == .notifications else {
            return step.destination(familyId: familyId)
        }
        Task { await requestNotifications() }
        return nil
    }

    /// Il permesso notifiche si chiede da qui. Se il sistema l'ha già negato non
    /// c'è più niente da chiedere — iOS mostra il dialog una volta sola per
    /// installazione — e l'unica strada che resta sono le Impostazioni.
    private func requestNotifications() async {
        guard !isRequestingNotifications else { return }
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            try? await NotificationManager.shared.enablePushNotificationsForCurrentUser()
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                _ = await UIApplication.shared.open(url)
            }
        default:
            break
        }
        await NotificationManager.shared.refreshAuthorizationStatus()
    }
}
