//
//  KBStorageGate.swift
//  KidBox
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
    
    var title: String {
        switch self {
        case .quotaExceeded:  return "Spazio esaurito"
        case .wouldExceed:    return "Spazio insufficiente"
        }
    }
    
    var message: String {
        switch self {
        case .quotaExceeded(let used, let quota):
            return "La famiglia ha usato \(used.formattedFileSize) su \(quota.formattedFileSize). Passa a Pro per 5 GB."
        case .wouldExceed(let used, let quota, let needed):
            let free = quota - used
            return "Questo file richiede \(needed.formattedFileSize) ma hai solo \(free.formattedFileSize) liberi su \(quota.formattedFileSize). Passa a Pro per 5 GB."
        }
    }
}

// MARK: - Gate

final class KBStorageGate {
    
    static let shared = KBStorageGate()
    private init() {}
    
    /// Quota corrente per la famiglia.
    /// TODO: leggere dal piano utente quando il sistema di subscription sarà implementato.
    var currentQuota: Int64 { StorageUsageViewModel.quotaFree }
    
    /// Bytes usati aggiornati da Firebase (scritto da StorageUsageViewModel dopo ogni load).
    /// Se 0 → il gate usa il calcolo locale come fallback.
    var cachedUsedBytes: Int64 = 0
    
    // MARK: - Check
    
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
            primaryButton: .default(Text("Passa a Pro"), action: onUpgrade),
            secondaryButton: .cancel(Text("Annulla"))
        )
    }
    
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
        let chatMediaFallback: Int64 = 512 * 1024
        let visitPhotoEstimate: Int64 = 200 * 1024
        
        // Documenti (fileSize reale)
        let docDesc = FetchDescriptor<KBDocument>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )
        let docBytes: Int64 = ((try? modelContext.fetch(docDesc)) ?? [])
            .reduce(0) { $0 + $1.fileSize }
        
        // Chat media (fileSize reale o fallback per messaggi vecchi)
        var chatDesc = FetchDescriptor<KBChatMessage>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false && $0.mediaStoragePath != nil }
        )
        chatDesc.fetchLimit = 100_000
        let chatBytes: Int64 = ((try? modelContext.fetch(chatDesc)) ?? [])
            .reduce(0) { acc, msg in acc + (msg.mediaFileSize ?? chatMediaFallback) }
        
        // Foto album condiviso (fileSize reale)
        let photoDesc = FetchDescriptor<KBFamilyPhoto>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )
        let photoBytes: Int64 = ((try? modelContext.fetch(photoDesc)) ?? [])
            .reduce(0) { $0 + $1.fileSize }
        
        // Foto visite pediatriche (stima 200KB/foto)
        var visitDesc = FetchDescriptor<KBMedicalVisit>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )
        visitDesc.fetchLimit = 100_000
        let visitPhotoBytes: Int64 = ((try? modelContext.fetch(visitDesc)) ?? [])
            .reduce(0) { acc, v in acc + Int64(v.photoURLs.count) * visitPhotoEstimate }
        
        return docBytes + chatBytes + photoBytes + visitPhotoBytes
    }
}

// MARK: - View modifier

private struct StorageGatedModifier: ViewModifier {
    let bytes: Int64
    let modelContext: ModelContext
    let familyId: String
    let onAllowed: () -> Void
    
    @State private var blockedReason: KBStorageBlockReason?
    
    func body(content: Content) -> some View {
        content
            .onTapGesture { checkAndProceed() }
            .alert(item: Binding(
                get: { blockedReason.map { BlockedWrapper(reason: $0) } },
                set: { blockedReason = $0?.reason }
            )) { wrapper in
                KBStorageGate.blockedAlert(reason: wrapper.reason) {
                    // TODO: navigare alla paywall
                    blockedReason = nil
                }
            }
    }
    
    private func checkAndProceed() {
        let result = KBStorageGate.shared.canUpload(
            bytes: bytes, modelContext: modelContext, familyId: familyId
        )
        switch result {
        case .allowed:         onAllowed()
        case .blocked(let r):  blockedReason = r
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
