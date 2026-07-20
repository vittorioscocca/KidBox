//
//  KBStorageGate.swift
//  KidBox — target: Main App only
//
//  Servizio centralizzato che controlla se la famiglia ha spazio disponibile
//  prima di eseguire qualsiasi upload su Firebase Storage.
//
//  UTILIZZO — prima di ogni upload (documenti, chat media, foto):
//
//      switch KBStorageGate.shared.canUpload(bytes: fileSize, modelContext: ctx, familyId: fid) {
//      case .allowed:
//          // procedi con l'upload
//      case .blocked(let reason):
//          // mostra l'alert
//      }
//
//  OPPURE usa il modifier direttamente sul pulsante:
//
//      Button("Allega referto") { }
//          .storageGated(bytes: fileSize, modelContext: ctx, familyId: fid) {
//              showPicker = true
//          }
//
//  NOTE:
//  - Il calcolo è sincrono e lato client (stima da SwiftData locale).
//  - La Share Extension usa KBStorageGateLite (nessuna dipendenza SwiftData).
//    I dati vengono scritti nell'App Group da StorageUsageViewModel
//    .persistUsedBytesToAppGroup() dopo ogni sync con Firebase.
//  - Quando sarà implementato il sistema di subscription, sostituire
//    `currentQuota` con la quota letta dal piano utente.

import Foundation
import SwiftData
import SwiftUI

// MARK: - Result

enum KBStorageGateResult {
    case allowed
    case blocked(KBStorageBlockReason)
}

enum KBStorageBlockReason {
    case quotaExceeded(used: Int64, quota: Int64)
    case wouldExceed(used: Int64, quota: Int64, needed: Int64)
    
    var title: LocalizedStringKey {
        switch self {
        case .quotaExceeded: return "Spazio esaurito"
        case .wouldExceed:   return "Spazio insufficiente"
        }
    }

    /// Testo già risolto per il locale corrente — usato sia in UI (Text(reason.message))
    /// sia nei log, quindi resta `String` e passa da NSLocalizedString invece che da LocalizedStringKey.
    var message: String {
        switch self {
        case .quotaExceeded(let used, let quota):
            let format = NSLocalizedString("La famiglia ha usato %@ su %@. Passa a Pro per 5 GB.", comment: "Storage quota exceeded message")
            return String(format: format, used.formattedFileSize, quota.formattedFileSize)
        case .wouldExceed(let used, let quota, let needed):
            let free = quota - used
            let format = NSLocalizedString("Questo file richiede %@ ma hai solo %@ liberi su %@. Passa a Pro per 5 GB.", comment: "Storage would exceed quota message")
            return String(format: format, needed.formattedFileSize, free.formattedFileSize, quota.formattedFileSize)
        }
    }
}

// MARK: - Gate

final class KBStorageGate {
    
    static let shared = KBStorageGate()
    private init() {}
    
    /// Quota corrente per la famiglia — letta dal piano utente.
    var currentQuota: Int64 { KBSubscriptionManager.shared.currentPlan.storageQuota }
    
    /// Bytes usati aggiornati da Firebase (scritto da StorageUsageViewModel dopo ogni load).
    /// Se 0 → il gate usa il calcolo locale come fallback.
    var cachedUsedBytes: Int64 = 0
    
    // MARK: - Check (App — richiede ModelContext)
    
    /// Controlla se è possibile caricare un file di `bytes` byte.
    /// Passare `bytes: 0` per verificare solo se il limite è già superato.
    func canUpload(bytes: Int64 = 0, modelContext: ModelContext, familyId: String) -> KBStorageGateResult {
        let used = cachedUsedBytes > 0
        ? cachedUsedBytes
        : calculateUsedBytes(modelContext: modelContext, familyId: familyId)
        let quota = currentQuota
        
        if used >= quota {
            return .blocked(.quotaExceeded(used: used, quota: quota))
        }
        if bytes > 0 && (used + bytes) > quota {
            return .blocked(.wouldExceed(used: used, quota: quota, needed: bytes))
        }
        return .allowed
    }
    
    // MARK: - Alert helper
    
    static func blockedAlert(reason: KBStorageBlockReason, onUpgrade: @escaping () -> Void) -> Alert {
        Alert(
            title: Text(reason.title),
            message: Text(reason.message),
            primaryButton: .default(Text("Upgrade"), action: onUpgrade),
            secondaryButton: .cancel(Text("Annulla"))
        )
    }
    
    // MARK: - AI check
    
    /// nil = ok, altrimenti il motivo del blocco.
    func canUseAI() -> KBAIBlockReason? {
        guard KBSubscriptionManager.shared.currentPlan.includesAI else { return .planNotIncludesAI }
        guard AISettings.shared.consentGiven else { return .consentNotGiven }
        return nil
    }
    
    var isAIAvailable: Bool { canUseAI() == nil }
    
    // MARK: - Calcolo locale
    //
    // Allineato con StorageUsageViewModel.localUsedBytes.
    // Conta solo ciò che occupa realmente Firebase Storage:
    //
    // • Documenti       → fileSize reale da KBDocument
    // • Chat media      → mediaFileSize reale (se disponibile) o 512KB fallback
    // • Foto album      → fileSize reale da KBFamilyPhoto
    // • Foto visite     → KBMedicalVisit.photoURLs, stima 200KB/foto
    // • Expense         → attachedDocumentId punta a KBDocument (già contato).
    //                     receiptThumbnailData è locale SwiftData → non contato.
    // • Esami/cure/vac  → nessun allegato su Storage → non contati
    
    func calculateUsedBytes(modelContext: ModelContext, familyId: String) -> Int64 {
        let fid = familyId
        let chatMediaFallback: Int64  = 512 * 1024
        let visitPhotoEstimate: Int64 = 200 * 1024
        
        let docDesc = FetchDescriptor<KBDocument>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )
        let docBytes: Int64 = ((try? modelContext.fetch(docDesc)) ?? [])
            .reduce(0) { $0 + $1.fileSize }
        
        var chatDesc = FetchDescriptor<KBChatMessage>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false && $0.mediaStoragePath != nil }
        )
        chatDesc.fetchLimit = 100_000
        let chatBytes: Int64 = ((try? modelContext.fetch(chatDesc)) ?? [])
            .reduce(0) { acc, msg in acc + (msg.mediaFileSize ?? chatMediaFallback) }
        
        let photoDesc = FetchDescriptor<KBFamilyPhoto>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )
        let photoBytes: Int64 = ((try? modelContext.fetch(photoDesc)) ?? [])
            .reduce(0) { $0 + $1.fileSize }
        
        var visitDesc = FetchDescriptor<KBMedicalVisit>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )
        visitDesc.fetchLimit = 100_000
        let visitPhotoBytes: Int64 = ((try? modelContext.fetch(visitDesc)) ?? [])
            .reduce(0) { acc, v in acc + Int64(v.photoURLs.count) * visitPhotoEstimate }
        
        return docBytes + chatBytes + photoBytes + visitPhotoBytes
    }
}

// MARK: - View modifier (Storage)

private struct StorageGatedModifier: ViewModifier {
    let bytes: Int64
    let modelContext: ModelContext
    let familyId: String
    let onAllowed: () -> Void
    
    @State private var blockedReason: KBStorageBlockReason?
    @State private var showUpgrade = false
    
    func body(content: Content) -> some View {
        content
            .onTapGesture { checkAndProceed() }
            .alert(item: Binding(
                get: { blockedReason.map { BlockedWrapper(reason: $0) } },
                set: { blockedReason = $0?.reason }
            )) { wrapper in
                KBStorageGate.blockedAlert(reason: wrapper.reason) {
                    showUpgrade = true
                    blockedReason = nil
                }
            }
            .sheet(isPresented: $showUpgrade) {
                UpgradeSheetView()
                    .environmentObject(KBSubscriptionManager.shared)
            }
    }
    
    private func checkAndProceed() {
        let result = KBStorageGate.shared.canUpload(
            bytes: bytes, modelContext: modelContext, familyId: familyId
        )
        switch result {
        case .allowed:        onAllowed()
        case .blocked(let r): blockedReason = r
        }
    }
}

private struct BlockedWrapper: Identifiable {
    let id = UUID()
    let reason: KBStorageBlockReason
}

extension View {
    /// Intercetta il tap e blocca l'azione se lo storage è esaurito.
    /// Se `bytes` è 0 verifica solo che il limite non sia già superato.
    func storageGated(
        bytes: Int64 = 0,
        modelContext: ModelContext,
        familyId: String,
        onAllowed: @escaping () -> Void
    ) -> some View {
        modifier(StorageGatedModifier(
            bytes: bytes,
            modelContext: modelContext,
            familyId: familyId,
            onAllowed: onAllowed
        ))
    }
}

// MARK: - AI Block Reason

enum KBAIBlockReason: Equatable {
    case planNotIncludesAI
    case consentNotGiven
    
    var title: LocalizedStringKey {
        switch self {
        case .planNotIncludesAI: return "Funzione AI non disponibile"
        case .consentNotGiven:   return "Consenso richiesto"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .planNotIncludesAI:
            return "L'assistente AI è incluso nei piani Pro e Max. Passa a Pro per 20 messaggi al giorno per membro."
        case .consentNotGiven:
            return "Per usare l'AI devi prima accettare le condizioni d'uso in Impostazioni → Assistente AI."
        }
    }
}

// MARK: - AI View Modifier

private struct AIGatedModifier: ViewModifier {
    let onAllowed: () -> Void
    
    @State private var blockedReason: KBAIBlockReason?
    @State private var showUpgrade = false
    
    func body(content: Content) -> some View {
        content
            .onTapGesture { checkAndProceed() }
            .alert(item: Binding(
                get: { blockedReason.map { AIBlockedWrapper(reason: $0) } },
                set: { blockedReason = $0?.reason }
            )) { wrapper in
                Alert(
                    title: Text(wrapper.reason.title),
                    message: Text(wrapper.reason.message),
                    primaryButton: .default(
                        Text(wrapper.reason == .planNotIncludesAI ? "Upgrade" : "OK")
                    ) {
                        if wrapper.reason == .planNotIncludesAI { showUpgrade = true }
                        blockedReason = nil
                    },
                    secondaryButton: .cancel(Text("Annulla"))
                )
            }
            .sheet(isPresented: $showUpgrade) {
                UpgradeSheetView()
                    .environmentObject(KBSubscriptionManager.shared)
            }
    }
    
    private func checkAndProceed() {
        if let reason = KBStorageGate.shared.canUseAI() {
            blockedReason = reason
        } else {
            onAllowed()
        }
    }
}

private struct AIBlockedWrapper: Identifiable {
    let id = UUID()
    let reason: KBAIBlockReason
}

extension View {
    /// Intercetta il tap e blocca se il piano non include l'AI o manca il consenso.
    func aiGated(onAllowed: @escaping () -> Void) -> some View {
        modifier(AIGatedModifier(onAllowed: onAllowed))
    }
}
