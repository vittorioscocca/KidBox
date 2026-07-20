//
//  KBSubscriptionManager.swift
//  KidBox
//
//  Gestisce il piano abbonamento della famiglia:
//  - Legge il piano corrente da Firestore (users/{uid}.plan)
//  - Espone le quote di storage e AI in base al piano
//  - Gestisce l'acquisto via StoreKit 2
//  - Aggiorna il piano su Firestore dopo l'acquisto (via Cloud Function)
//
//  Product IDs (configurare in App Store Connect):
//    it.vittorioscocca.kidbox.pro.monthly
//    it.vittorioscocca.kidbox.max.monthly
//
//  Il piano è per famiglia: un solo acquisto copre tutti i membri.
//  Lo storage è condiviso; i messaggi AI sono per membro (uid).

import Foundation
import StoreKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import UserNotifications
import Combine

// MARK: - Plan

enum KBPlan: String, CaseIterable {
    case free   = "free"
    case pro    = "pro"
    case max    = "max"
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro:  return "Pro"
        case .max:  return "Max"
        }
    }
    
    /// `String` (non `LocalizedStringKey`): confrontato con `.isEmpty` e usato in `??`
    /// insieme a `product?.displayPrice` (StoreKit), quindi passa da NSLocalizedString.
    var monthlyPrice: String {
        switch self {
        case .free: return NSLocalizedString("Gratis", comment: "Free plan price")
        case .pro:  return NSLocalizedString("€4,99/mese", comment: "Pro plan monthly price")
        case .max:  return NSLocalizedString("€9,99/mese", comment: "Max plan monthly price")
        }
    }
    
    var storageQuota: Int64 {
        switch self {
        case .free: return 200  * 1024 * 1024        // 200 MB
        case .pro:  return 5    * 1024 * 1024 * 1024 // 5 GB
        case .max:  return 20   * 1024 * 1024 * 1024 // 20 GB
        }
    }
    
    /// Messaggi AI al giorno per famiglia (condivisi tra tutti i membri)
    var aiDailyLimit: Int {
        switch self {
        case .free: return 0
        case .pro:  return 30
        case .max:  return 100
        }
    }
    
    var includesAI: Bool { self != .free }
    
    var storageLabel: String { storageQuota.formattedFileSize }
    
    /// Product ID App Store Connect
    var productId: String? {
        switch self {
        case .free: return nil
        case .pro:  return "it.vittorioscocca.kidbox.pro.monthly"
        case .max:  return "it.vittorioscocca.kidbox.max.monthly"
        }
    }
    
    /// `String` (non `LocalizedStringKey`): confrontato con `.isEmpty`, quindi passa da NSLocalizedString.
    var badge: String {
        switch self {
        case .free: return ""
        case .pro:  return NSLocalizedString("Più popolare", comment: "Pro plan badge")
        case .max:  return NSLocalizedString("Migliore", comment: "Max plan badge")
        }
    }
}

// MARK: - Manager

@MainActor
final class KBSubscriptionManager: ObservableObject {
    
    static let shared = KBSubscriptionManager()
    
    // MARK: - Published
    
    @Published private(set) var currentPlan: KBPlan = .free
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var purchaseError: String?
    @Published private(set) var isPurchasing: Bool = false
    
    /// Prodotti StoreKit caricati
    @Published private(set) var products: [Product] = []
    
    /// true = l'abbonamento si rinnoverà automaticamente
    /// false = l'utente ha cancellato, le quote restano attive fino a expirationDate
    @Published private(set) var subscriptionWillRenew: Bool = true
    
    /// Data di scadenza dell'abbonamento corrente (nil se Free o non disponibile)
    @Published private(set) var subscriptionExpirationDate: Date? = nil
    
    /// `true` finché `loadPlan()` non ha determinato il ruolo (evita flash UI da non-owner).
    /// Solo l'owner famiglia può acquistare/riscattare piani Pro/Max.
    @Published private(set) var isFamilyOwner: Bool = true
    
    /// true = abbonamento attivo ma cancellato (non si rinnoverà)
    var isCancelledButActive: Bool {
        currentPlan != .free && !subscriptionWillRenew && subscriptionExpirationDate != nil
    }
    
    /// Impostato da AppCoordinator al momento del login / cambio famiglia.
    /// Usato per leggere `planOverride` da Firestore.
    var currentFamilyId: String? = nil
    
    
    // MARK: - Private
    
    private let db        = Firestore.firestore()
    private let functions = Functions.functions(region: "europe-west1")
    private var listenerTask: Task<Void, Never>?
    
    private init() {
        startTransactionListener()
    }
    
    deinit {
        listenerTask?.cancel()
    }
    
    // MARK: - Load plan from Firestore
    
    /// Aggiorna solo `currentPlan` da Firestore (famiglia + fallback utente). Non modifica `isFamilyOwner`.
    private func syncPlanFromFirestore(uid: String, familyId: String) async {
        do {
            var plan = "free"
            
            if !familyId.isEmpty {
                let familySnap = try await db.collection("families").document(familyId).getDocument()
                let data = familySnap.data()
                let overrideRaw = (data?["planOverride"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""
                if overrideRaw == KBPlan.pro.rawValue || overrideRaw == KBPlan.max.rawValue {
                    plan = overrideRaw
                } else {
                    plan = (data?["plan"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() ?? "free"
                }
            }
            
            if plan == "free" {
                let userSnap = try await db.collection("users").document(uid).getDocument()
                plan = userSnap.data()?["plan"] as? String ?? "free"
            }
            
            currentPlan = KBPlan(rawValue: plan) ?? .free
            KBLog.app.kbInfo("SubscriptionManager: plan loaded plan=\(currentPlan.rawValue) familyId=\(familyId)")
        } catch {
            KBLog.app.kbError("SubscriptionManager: loadPlan failed \(error.localizedDescription)")
        }
    }
    
    func loadPlan() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isFamilyOwner = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        
        let familyId = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
            .string(forKey: "activeFamilyId") ?? ""
        
        if familyId.isEmpty {
            isFamilyOwner = true
        } else {
            let memberSnap = try? await db
                .collection("families").document(familyId)
                .collection("members").document(uid)
                .getDocument()
            let role = memberSnap?.data()?["role"] as? String ?? "owner"
            
            if role == "owner" {
                isFamilyOwner = true
            } else {
                // Doppio check su ownerUid della famiglia
                let familyMemberSnap = try? await db
                    .collection("families").document(familyId)
                    .getDocument()
                let ownerUid = familyMemberSnap?.data()?["ownerUid"] as? String ?? ""
                isFamilyOwner = (ownerUid == uid)
            }
            KBLog.app.kbDebug("SubscriptionManager: role=\(role) isFamilyOwner=\(isFamilyOwner) uid=\(uid) familyId=\(familyId)")
        }
        
        // Leggi Firestore come punto di partenza rapido...
        await syncPlanFromFirestore(uid: uid, familyId: familyId)
        
        // FIX 2: ...poi verifica subito StoreKit per correggere eventuali dati stale.
        // Se l'abbonamento è scaduto/cancellato, refreshCurrentEntitlement() aggiorna
        // currentPlan e, se siamo l'owner, riscrive "free" su Firestore in modo atomico.
        await refreshCurrentEntitlement()
    }
    
    func clearPurchaseError() {
        purchaseError = nil
    }
    
    /// Chiamare al logout: azzera il ruolo famiglia fino al prossimo `loadPlan()`.
    func resetOnSignOut() {
        isFamilyOwner = false
        currentFamilyId = nil
    }
    
    // MARK: - Load StoreKit products
    
    func loadProducts() async {
        let ids = KBPlan.allCases.compactMap(\.productId)
        guard !ids.isEmpty else { return }
        
        do {
            products = try await Product.products(for: Set(ids))
                .sorted { $0.price < $1.price }
            KBLog.app.kbInfo("SubscriptionManager: products loaded count=\(products.count)")
        } catch {
            KBLog.app.kbError("SubscriptionManager: loadProducts failed \(error.localizedDescription)")
        }
    }
    
    // MARK: - Purchase
    
    func purchase(_ plan: KBPlan) async {
        guard let productId = plan.productId else { return }
        guard let product   = products.first(where: { $0.id == productId }) else {
            purchaseError = "Prodotto non disponibile. Riprova tra qualche istante."
            return
        }
        
        isPurchasing  = true
        purchaseError = nil
        defer { isPurchasing = false }
        
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updatePlanOnServer(plan: plan, transactionId: String(transaction.id))
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Acquisto in attesa di approvazione."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Acquisto non completato: \(error.localizedDescription)"
            KBLog.app.kbError("SubscriptionManager: purchase failed \(error.localizedDescription)")
        }
    }
    
    // MARK: - Restore
    
    func restorePurchases() async {
        isPurchasing  = true
        purchaseError = nil
        defer { isPurchasing = false }
        
        do {
            try await AppStore.sync()
            await loadPlan()
            // Aggiorna il gate con il piano ripristinato
            let familyId = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.string(forKey: "activeFamilyId") ?? ""
            if !familyId.isEmpty {
                Task.detached(priority: .utility) {
                    await StorageUsageViewModel.prefetchForGate(familyId: familyId)
                }
            }
        } catch {
            purchaseError = "Ripristino non riuscito: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Product for plan
    
    func storeProduct(for plan: KBPlan) -> Product? {
        guard let pid = plan.productId else { return nil }
        return products.first(where: { $0.id == pid })
    }
    
    // MARK: - Manage / Cancel subscription
    
    // Lo sheet Apple viene aperto dalla view tramite il modifier
    // .manageSubscriptionsSheet(isPresented:) con uno @State locale.
    // Non serve alcun metodo qui: il button nella view setta direttamente il bool.
    
    // MARK: - Private helpers
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):   return value
        case .unverified(_, let e):  throw e
        }
    }
    
    private func loadPlanOverride() async -> KBPlan? {
        let fallback = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.string(forKey: "activeFamilyId") ?? ""
        let familyId: String
        if let id = currentFamilyId, !id.isEmpty {
            familyId = id
        } else if !fallback.isEmpty {
            familyId = fallback
        } else {
            return nil
        }
        
        guard let data = try? await db.collection("families").document(familyId).getDocument().data() else { return nil }
        
        let overrideRaw = (data["planOverride"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard overrideRaw == KBPlan.pro.rawValue || overrideRaw == KBPlan.max.rawValue,
              let plan = KBPlan(rawValue: overrideRaw) else { return nil }
        
        KBLog.app.kbInfo("SubscriptionManager: planOverride trovato → \(plan.rawValue)")
        return plan
    }
    
    /// Scrive il piano aggiornato su Firestore (users/{uid}.plan).
    /// In produzione sostituire con una Cloud Function che verifica il receipt lato server.
    private func updatePlanOnServer(plan: KBPlan, transactionId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if await loadPlanOverride() != nil {
            KBLog.app.kbDebug("SubscriptionManager: skip updatePlanOnServer — override amministrativo attivo")
            return
        }
        let sharedDefaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
        let familyId = sharedDefaults?.string(forKey: "activeFamilyId") ?? ""
        
        do {
            // 1. Scrivi su families/{familyId} — fonte di verità condivisa da tutti i membri
            if !familyId.isEmpty {
                try await db.collection("families").document(familyId).setData(
                    ["plan": plan.rawValue, "planUpdatedAt": FieldValue.serverTimestamp()],
                    merge: true
                )
            }
            
            // 2. Scrivi su users/{uid} — retrocompatibilità e fallback Cloud Functions
            try await db.collection("users").document(uid).setData(
                ["plan": plan.rawValue, "planUpdatedAt": FieldValue.serverTimestamp()],
                merge: true
            )
            
            currentPlan = plan
            KBLog.app.kbInfo("SubscriptionManager: plan updated to \(plan.rawValue) txId=\(transactionId) familyId=\(familyId)")
            
            // Aggiorna il gate con la nuova quota
            if !familyId.isEmpty {
                Task.detached(priority: .utility) {
                    await StorageUsageViewModel.prefetchForGate(familyId: familyId)
                }
            }
        } catch {
            purchaseError = "Piano acquistato ma aggiornamento profilo fallito. Contatta il supporto."
            KBLog.app.kbError("SubscriptionManager: updatePlan failed \(error.localizedDescription)")
        }
    }
    
    // MARK: - Debug (rimuovere prima del rilascio)
    
    func debugDumpAllTransactions() async {
        KBLog.app.kbInfo("=== DEBUG: Transaction.currentEntitlements ===")
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let tx):
                KBLog.app.kbInfo("  ✅ VERIFIED: \(tx.productID) | expires: \(tx.expirationDate?.description ?? "nil") | revoked: \(tx.revocationDate?.description ?? "nil")")
            case .unverified(let tx, let err):
                KBLog.app.kbInfo("  ❌ UNVERIFIED: \(tx.productID) | err: \(err)")
            }
        }
        KBLog.app.kbInfo("=== DEBUG: Transaction.latest per product ===")
        for plan in KBPlan.allCases {
            guard let pid = plan.productId else { continue }
            let result = await Transaction.latest(for: pid)
            switch result {
            case .verified(let tx):
                KBLog.app.kbInfo("  latest \(pid): expires=\(tx.expirationDate?.description ?? "nil") revoked=\(tx.revocationDate?.description ?? "nil")")
            case .unverified(_, let err):
                KBLog.app.kbInfo("  latest \(pid): UNVERIFIED \(err)")
            case nil:
                KBLog.app.kbInfo("  latest \(pid): NIL - nessuna transazione")
            }
        }
        KBLog.app.kbInfo("=== END DEBUG ===")
    }
    
    /// Listener per transazioni completate anche fuori dall'app (rinnovi, acquisti web).
    ///
    /// FIX: dopo ogni evento in Transaction.updates viene chiamato refreshCurrentEntitlement().
    /// Questo copre il caso della cancellazione, che non genera una nuova transazione
    /// ma modifica RenewalInfo.willAutoRenew — aggiornato solo tramite entitlement check.
    private func startTransactionListener() {
        listenerTask = Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                if case .verified(let tx) = result {
                    let planRaw = tx.productID
                        .replacingOccurrences(of: "it.vittorioscocca.kidbox.", with: "")
                        .replacingOccurrences(of: ".monthly", with: "")
                    if let plan = KBPlan(rawValue: planRaw) {
                        await self.updatePlanOnServer(plan: plan, transactionId: String(tx.id))
                    }
                    await tx.finish()
                }
                // FIX: rivaluta sempre willAutoRenew e expirationDate dopo ogni update,
                // indipendentemente dal tipo di transazione (acquisto, rinnovo, cancellazione).
                await self.refreshCurrentEntitlement()
            }
        }
    }
    
    // MARK: - Entitlement check (scadenza / downgrade)
    
    /// Verifica lo stato corrente degli abbonamenti StoreKit.
    /// Da chiamare ogni volta che l'app torna in foreground (scenePhase .active)
    /// e al rientro dallo sheet di gestione abbonamenti Apple.
    ///
    /// FIX 1: usa subscriptionGroupID per leggere willAutoRenew — Product.SubscriptionInfo.status(for:)
    ///         si aspetta il group ID, non il product ID. Con il product ID restituisce sempre nil
    ///         e willRenew cade nel default `true`, nascondendo la cancellazione.
    /// FIX 2: currentPlan viene aggiornato SUBITO da StoreKit, prima dell'aggiornamento Firestore,
    ///         così la UI riflette lo stato reale senza attendere la Cloud Function.
    func refreshCurrentEntitlement() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        KBLog.app.kbInfo("SubscriptionManager: refreshCurrentEntitlement")
        
        if let overridePlan = await loadPlanOverride() {
            currentPlan = overridePlan
            subscriptionWillRenew = false
            subscriptionExpirationDate = nil
            cancelExpirationNotification()
            KBLog.app.kbInfo("SubscriptionManager: override attivo → \(overridePlan.rawValue), skip StoreKit")
            return
        }
        
        var activePlan: KBPlan?         = nil
        var activeTransactionId: String = "entitlement-check"
        var willRenew: Bool             = true
        var expiryDate: Date?           = nil
        
        // Strategia a due livelli:
        // 1. Transaction.currentEntitlements — fonte di verità ufficiale
        // 2. Transaction.latest(for:) per ogni product ID — fallback per Sandbox
        //    dove currentEntitlements può restare stale dopo un upgrade nello sheet.
        
        // — Livello 1: currentEntitlements —
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            if let revoked = tx.revocationDate, revoked <= Date() { continue }
            if let expiry  = tx.expirationDate,  expiry  <= Date() { continue }
            
            let planRaw = tx.productID
                .replacingOccurrences(of: "it.vittorioscocca.kidbox.", with: "")
                .replacingOccurrences(of: ".monthly", with: "")
            guard let plan = KBPlan(rawValue: planRaw) else { continue }
            guard activePlan == nil || plan.storageQuota > (activePlan?.storageQuota ?? 0) else { continue }
            
            activePlan          = plan
            activeTransactionId = String(tx.id)
            expiryDate          = tx.expirationDate
            
            let groupID = tx.subscriptionGroupID ?? tx.productID
            if let statuses = try? await Product.SubscriptionInfo.status(for: groupID) {
                let matched = statuses.first {
                    if case .verified(let info) = $0.renewalInfo,
                       info.currentProductID == tx.productID { return true }
                    return false
                } ?? statuses.first
                if let status = matched, case .verified(let info) = status.renewalInfo {
                    willRenew = info.willAutoRenew
                    KBLog.app.kbDebug("SubscriptionManager: willAutoRenew=\(willRenew) groupID=\(groupID) product=\(tx.productID)")
                } else {
                    willRenew = true
                }
            } else {
                willRenew = true
            }
        }
        
        // — Livello 2: fallback Transaction.latest(for:) —
        // In Sandbox, currentEntitlements può restare su Pro anche dopo che
        // l'utente ha cambiato piano a Max nello sheet. Transaction.latest(for:)
        // interroga il server StoreKit fresco e restituisce la transazione
        // più recente per quel product ID, indipendentemente dalla cache locale.
        for plan in KBPlan.allCases {
            guard let productId = plan.productId else { continue }
            if let current = activePlan, current.storageQuota >= plan.storageQuota { continue }
            
            guard let result = await Transaction.latest(for: productId),
                  case .verified(let tx) = result else { continue }
            if let revoked = tx.revocationDate, revoked <= Date() { continue }
            if let expiry  = tx.expirationDate,  expiry  <= Date() { continue }
            
            KBLog.app.kbInfo("SubscriptionManager: fallback latest tx found product=\(productId) plan=\(plan.rawValue)")
            activePlan          = plan
            activeTransactionId = String(tx.id)
            expiryDate          = tx.expirationDate
            
            let groupID = tx.subscriptionGroupID ?? tx.productID
            if let statuses = try? await Product.SubscriptionInfo.status(for: groupID),
               let matched  = statuses.first(where: {
                   if case .verified(let info) = $0.renewalInfo,
                      info.currentProductID == tx.productID { return true }
                   return false
               }) ?? statuses.first,
               case .verified(let info) = matched.renewalInfo {
                willRenew = info.willAutoRenew
            } else {
                willRenew = true
            }
        }
        
        let resolvedPlan = activePlan ?? .free
        
        subscriptionWillRenew      = resolvedPlan == .free ? true : willRenew
        subscriptionExpirationDate = resolvedPlan == .free ? nil  : expiryDate
        
        let planDidChange = resolvedPlan != currentPlan
        if planDidChange {
            KBLog.app.kbInfo("SubscriptionManager: entitlement changed \(currentPlan.rawValue) → \(resolvedPlan.rawValue)")
            currentPlan = resolvedPlan
        }
        
        KBLog.app.kbDebug("SubscriptionManager: resolved plan=\(resolvedPlan.rawValue) willRenew=\(subscriptionWillRenew) expiry=\(subscriptionExpirationDate?.description ?? "nil")")
        
        if resolvedPlan != .free && !willRenew, let expiry = expiryDate {
            await scheduleExpirationNotification(plan: resolvedPlan, expirationDate: expiry)
        } else {
            cancelExpirationNotification()
        }
        
        // ── Scrittura Firestore ───────────────────────────────────────────────────
        // FIX 1: solo l'owner scrive su Firestore — sia quando ha un abbonamento attivo
        // che quando è scaduto/cancellato (activePlan == nil → scrive "free").
        // I membri leggono sempre e solo da Firestore tramite syncPlanFromFirestore().
        //
        // PRIMA: la scrittura era condizionata a (activePlan != nil), il che bloccava
        // il downgrade a "free" su Firestore quando l'abbonamento scadeva, lasciando
        // Firestore stale con "pro" e facendo rientrare l'utente come Pro al riavvio.
        if isFamilyOwner {
            // Siamo l'owner: scriviamo sempre il piano reale (attivo o "free")
            guard planDidChange else { return }
            await updatePlanOnServer(plan: resolvedPlan, transactionId: activeTransactionId)
        } else {
            // Siamo un membro: non scriviamo mai, allineiamo da Firestore
            if planDidChange {
                let familyId = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                    .string(forKey: "activeFamilyId") ?? ""
                await syncPlanFromFirestore(uid: uid, familyId: familyId)
            }
        }
    }
    
    // MARK: - Notifiche scadenza abbonamento
    
    private static let expirationNotificationId = "kb.subscription.expiring"
    
    /// Schedula una notifica locale 3 giorni prima della scadenza.
    /// Sostituisce sempre la notifica precedente (idempotente).
    private func scheduleExpirationNotification(plan: KBPlan, expirationDate: Date) async {
        let center = UNUserNotificationCenter.current()
        
        // Rimuovi notifica precedente
        center.removePendingNotificationRequests(withIdentifiers: [Self.expirationNotificationId])
        
        // Calcola data notifica: 3 giorni prima della scadenza
        let notifyDate = expirationDate.addingTimeInterval(-3 * 24 * 60 * 60)
        guard notifyDate > Date() else {
            // Meno di 3 giorni alla scadenza: notifica immediata (1 minuto)
            let soon = Date().addingTimeInterval(60)
            await scheduleNotification(triggerDate: soon, plan: plan, expirationDate: expirationDate)
            return
        }
        
        await scheduleNotification(triggerDate: notifyDate, plan: plan, expirationDate: expirationDate)
    }
    
    private func scheduleNotification(triggerDate: Date, plan: KBPlan, expirationDate: Date) async {
        let center = UNUserNotificationCenter.current()
        
        let authStatus = await center.notificationSettings().authorizationStatus
        guard authStatus == .authorized || authStatus == .provisional else {
            KBLog.app.kbDebug("SubscriptionManager: notifiche non autorizzate, skip expiration reminder")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Il tuo piano \(plan.displayName) sta per scadere"
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale    = kbDeviceLocale()
        let dateStr = formatter.string(from: expirationDate)
        content.body  = "Il tuo abbonamento KidBox \(plan.displayName) scade il \(dateStr). Rinnova per continuare ad usare AI e storage esteso."
        content.sound = .default
        
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: Self.expirationNotificationId,
            content:    content,
            trigger:    trigger
        )
        
        do {
            try await center.add(request)
            KBLog.app.kbInfo("SubscriptionManager: expiration notification scheduled for \(triggerDate)")
        } catch {
            KBLog.app.kbError("SubscriptionManager: failed to schedule expiration notification: \(error.localizedDescription)")
        }
    }
    
    private func cancelExpirationNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.expirationNotificationId])
        KBLog.app.kbDebug("SubscriptionManager: expiration notification cancelled")
    }
}
