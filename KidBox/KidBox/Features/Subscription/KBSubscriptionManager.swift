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
    
    var monthlyPrice: String {
        switch self {
        case .free: return "Gratis"
        case .pro:  return "€4,99/mese"
        case .max:  return "€9,99/mese"
        }
    }
    
    var storageQuota: Int64 {
        switch self {
        case .free: return 200  * 1024 * 1024        // 200 MB
        case .pro:  return 5    * 1024 * 1024 * 1024 // 5 GB
        case .max:  return 20   * 1024 * 1024 * 1024 // 20 GB
        }
    }
    
    /// Messaggi AI al giorno per membro
    var aiDailyLimit: Int {
        switch self {
        case .free: return 0
        case .pro:  return 20
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
    
    var badge: String {
        switch self {
        case .free: return ""
        case .pro:  return "Più popolare"
        case .max:  return "Migliore"
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
    
    func loadPlan() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            let raw  = snap.data()?["plan"] as? String ?? "free"
            currentPlan = KBPlan(rawValue: raw) ?? .free
            KBLog.app.kbInfo("SubscriptionManager: plan loaded plan=\(currentPlan.rawValue)")
        } catch {
            KBLog.app.kbError("SubscriptionManager: loadPlan failed \(error.localizedDescription)")
        }
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
        } catch {
            purchaseError = "Ripristino non riuscito: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Product for plan
    
    func storeProduct(for plan: KBPlan) -> Product? {
        guard let pid = plan.productId else { return nil }
        return products.first(where: { $0.id == pid })
    }
    
    // MARK: - Private helpers
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):   return value
        case .unverified(_, let e):  throw e
        }
    }
    
    /// Scrive il piano aggiornato su Firestore (users/{uid}.plan).
    /// In produzione sostituire con una Cloud Function che verifica il receipt lato server.
    private func updatePlanOnServer(plan: KBPlan, transactionId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).setData(
                ["plan": plan.rawValue, "planUpdatedAt": FieldValue.serverTimestamp()],
                merge: true
            )
            currentPlan = plan
            KBLog.app.kbInfo("SubscriptionManager: plan updated to \(plan.rawValue) txId=\(transactionId)")
        } catch {
            purchaseError = "Piano acquistato ma aggiornamento profilo fallito. Contatta il supporto."
            KBLog.app.kbError("SubscriptionManager: updatePlan failed \(error.localizedDescription)")
        }
    }
    
    /// Listener per transazioni completate anche fuori dall'app (rinnovi, acquisti web).
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
            }
        }
    }
}
