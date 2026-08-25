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

// MARK: - AI quota period

/// Periodo su cui si resetta la quota messaggi AI condivisa dalla famiglia.
/// `daily` (Pro/Max) si resetta ogni giorno; `lifetime` (Free) è un bonus
/// una tantum che non si resetta mai.
enum AIQuotaPeriod: String {
    case daily
    case lifetime
}

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
    
    /// Messaggi AI per famiglia nel periodo di quota (condivisi tra tutti i membri).
    /// Free = 5 a vita (una tantum, non si rinnova), Pro = 30/giorno, Max = 100/giorno.
    var aiMessageLimit: Int {
        switch self {
        case .free: return 5
        case .pro:  return 30
        case .max:  return 100
        }
    }

    /// Periodo su cui si resetta la quota AI: a vita (una tantum) su Free, giornaliero su Pro/Max.
    var aiQuotaPeriod: AIQuotaPeriod {
        self == .free ? .lifetime : .daily
    }

    /// Etichetta quota AI da mostrare in UI, es. "5 msg AI una tantum" o "30 msg AI/giorno".
    var aiQuotaLabel: String {
        if aiQuotaPeriod == .lifetime {
            let format = NSLocalizedString(
                "%d msg AI una tantum",
                comment: "AI quota label, one-time free bonus (%d = message count)"
            )
            return String(format: format, aiMessageLimit)
        }
        return "\(aiMessageLimit) msg AI/giorno"
    }
    
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

    /// true = la famiglia Free ha esaurito il bonus una tantum di `KBPlan.aiMessageLimit`
    /// messaggi. Su Pro/Max resta sempre false: la loro quota è giornaliera e si
    /// rinnova da sola, quindi non deve mai bloccare l'ingresso in UI.
    @Published private(set) var aiAccessBlocked: Bool = false

    /// true = l'assistente AI è utilizzabile ORA dalla famiglia corrente,
    /// tenendo conto anche dell'esaurimento del bonus una tantum su Free.
    var isAIAccessible: Bool { !aiAccessBlocked }

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
    private var aiUsageObserver: NSObjectProtocol?

    private init() {
        startTransactionListener()
        observeAIUsageChanges()
    }

    deinit {
        listenerTask?.cancel()
        if let aiUsageObserver {
            NotificationCenter.default.removeObserver(aiUsageObserver)
        }
    }

    // MARK: - AI quota status

    /// Ogni chiamata AI aggiorna `AIUsageStore` (vedi `AIService.swift`): intercettiamo
    /// il notification così `aiAccessBlocked` riflette subito l'esaurimento del bonus
    /// Free, senza aspettare il prossimo `loadPlan()`.
    private func observeAIUsageChanges() {
        aiUsageObserver = NotificationCenter.default.addObserver(
            forName: .aiUsageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let usageToday = notification.userInfo?["usageToday"] as? Int,
                  let dailyLimit = notification.userInfo?["dailyLimit"] as? Int else { return }
            self.applyAIQuotaStatus(usageToday: usageToday, limit: dailyLimit)
        }
    }

    private func applyAIQuotaStatus(usageToday: Int, limit: Int) {
        guard currentPlan == .free else {
            aiAccessBlocked = false
            return
        }
        aiAccessBlocked = limit > 0 && usageToday >= limit
    }

    /// Interroga `getAIUsage` per sapere se la famiglia Free ha già esaurito il bonus.
    /// Su Pro/Max non serve: la loro quota giornaliera non blocca mai l'ingresso in UI.
    private func refreshAIQuotaStatus(familyId: String) async {
        guard currentPlan == .free, !familyId.isEmpty else {
            aiAccessBlocked = false
            return
        }
        do {
            let usage = try await AIService.shared.fetchUsage()
            applyAIQuotaStatus(usageToday: usage.usageToday, limit: usage.dailyLimit)
        } catch {
            // Fail-open: non blocchiamo l'UI per un errore di rete: il backend
            // resta comunque l'ultima parola quando l'utente invia davvero un messaggio.
            KBLog.app.kbError("SubscriptionManager: refreshAIQuotaStatus failed \(error.localizedDescription)")
        }
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

        // Su Free verifica se il bonus una tantum di messaggi AI è già esaurito,
        // così l'ingresso in UI (bottoni AskAI, sezione AI, ecc.) è coerente da subito.
        await refreshAIQuotaStatus(familyId: familyId)
    }
    
    func clearPurchaseError() {
        purchaseError = nil
    }
    
    /// Chiamare al logout: azzera il ruolo famiglia fino al prossimo `loadPlan()`.
    func resetOnSignOut() {
        isFamilyOwner = false
        currentFamilyId = nil
        aiAccessBlocked = false
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
                AppAnalytics.subscriptionStarted(plan: plan.rawValue, trial: transaction.offerType == .introductory)
                // Alla Cloud Function serve la ricevuta FIRMATA, non l'id transazione:
                // è la firma di Apple a rendere la prova d'acquisto non falsificabile.
                await syncPlanWithServer(jwsRepresentation: verification.jwsRepresentation)
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
    
    /// Invia la ricevuta firmata alla Cloud Function `validatePurchase`, che la
    /// verifica con Apple e scrive il piano lato server.
    ///
    /// Il client NON scrive più `plan` su Firestore: quelle scritture erano
    /// consentite dalle rules, quindi chiunque poteva regalarsi Pro/Max. Ora
    /// l'unica fonte di verità è la ricevuta verificata dal server.
    private func syncPlanWithServer(jwsRepresentation: String) async {
        guard Auth.auth().currentUser != nil else { return }
        if await loadPlanOverride() != nil {
            KBLog.app.kbDebug("SubscriptionManager: skip validatePurchase — override amministrativo attivo")
            return
        }
        let sharedDefaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
        let familyId = sharedDefaults?.string(forKey: "activeFamilyId") ?? ""
        guard !familyId.isEmpty else {
            KBLog.app.kbError("SubscriptionManager: validatePurchase saltata — familyId mancante")
            return
        }

        do {
            let result = try await functions.httpsCallable("validatePurchase").call([
                "familyId": familyId,
                "platform": "ios",
                "signedTransaction": jwsRepresentation,
            ])
            guard let data = result.data as? [String: Any],
                  let planRaw = data["plan"] as? String,
                  let plan = KBPlan(rawValue: planRaw) else {
                KBLog.app.kbError("SubscriptionManager: validatePurchase risposta non valida")
                return
            }

            currentPlan = plan
            KBLog.app.kbInfo("SubscriptionManager: piano validato dal server → \(plan.rawValue) familyId=\(familyId)")

            // Aggiorna il gate con la nuova quota
            Task.detached(priority: .utility) {
                await StorageUsageViewModel.prefetchForGate(familyId: familyId)
            }
        } catch {
            // Il piano resta quello che il server già conosce: non forziamo nulla
            // localmente, altrimenti la UI mostrerebbe un piano che il server non riconosce.
            purchaseError = "Acquisto registrato ma non ancora verificato. Riapri l'app tra poco o contatta il supporto."
            KBLog.app.kbError("SubscriptionManager: validatePurchase fallita \(error.localizedDescription)")
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
                    // Il piano lo deduce il server dal product id dentro la ricevuta
                    // firmata: non serve (né va) dedurlo qui dalla stringa.
                    await self.syncPlanWithServer(jwsRepresentation: result.jwsRepresentation)
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
        /// Ricevuta firmata dell'abbonamento attivo: è ciò che il server verifica.
        var activeJWS: String?          = nil
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
            activeJWS           = result.jwsRepresentation
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
            activeJWS           = result.jwsRepresentation
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
        
        // ── Allineamento col server ───────────────────────────────────────────────
        // Il client non scrive più il piano: manda la ricevuta firmata e il server
        // decide. Rimandarla a ogni refresh tiene aggiornato anche `planExpiresAt`,
        // che è ciò con cui il server fa scadere il piano da solo.
        //
        // Quando NON c'è un abbonamento attivo non c'è nulla da inviare: al
        // declassamento pensa il server confrontando `planExpiresAt` con l'ora
        // corrente, quindi qui aggiorniamo solo lo stato locale.
        if let activeJWS {
            await syncPlanWithServer(jwsRepresentation: activeJWS)
        } else if planDidChange {
            let familyId = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                .string(forKey: "activeFamilyId") ?? ""
            await syncPlanFromFirestore(uid: uid, familyId: familyId)
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
        let familyId = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
            .string(forKey: "activeFamilyId") ?? ""
        content.userInfo = [
            "type": "subscription_expiring",
            "familyId": familyId,
        ]
        
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: Self.expirationNotificationId,
            content:    content,
            trigger:    trigger
        )
        
        if await KBLocalNotificationBudget.shared.add(request, priority: .informational) {
            KBLog.app.kbInfo("SubscriptionManager: expiration notification scheduled for \(triggerDate)")
        }
    }
    
    private func cancelExpirationNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.expirationNotificationId])
        KBLog.app.kbDebug("SubscriptionManager: expiration notification cancelled")
    }
}
