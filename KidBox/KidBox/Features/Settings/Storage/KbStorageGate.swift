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
        let used = KBStorageGate.shared.cachedUsedBytes > 0 ? KBStorageGate.shared.cachedUsedBytes : calculateUsedBytes(modelContext: modelContext, familyId: familyId)
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
    
    // MARK: - Calcolo locale (specchio di StorageUsageViewModel)
    
    func calculateUsedBytes(modelContext: ModelContext, familyId: String) -> Int64 {
        let fid = familyId
        let kb: Int64 = 1024
        
        let docBytes: Int64 = {
            let desc = FetchDescriptor<KBDocument>(
                predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
            )
            let docs = (try? modelContext.fetch(desc)) ?? []
            return docs.reduce(0) { $0 + $1.fileSize } + Int64(docs.count) * kb
        }()
        
        let chatBytes: Int64 = {
            var da = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false })
            da.fetchLimit = 100_000
            let total = (try? modelContext.fetchCount(da)) ?? 0
            let dm = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.familyId == fid && $0.mediaStoragePath != nil })
            let media = (try? modelContext.fetchCount(dm)) ?? 0
            return Int64(media) * 512 * kb + Int64(total) * kb
        }()
        
        let saluteBytes: Int64 = {
            var dv = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false })
            dv.fetchLimit = 100_000
            var de = FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false })
            de.fetchLimit = 100_000
            var dt = FetchDescriptor<KBTreatment>(predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false })
            dt.fetchLimit = 100_000
            var dvc = FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false })
            dvc.fetchLimit = 100_000
            let v  = (try? modelContext.fetchCount(dv))  ?? 0
            let e  = (try? modelContext.fetchCount(de))  ?? 0
            let t  = (try? modelContext.fetchCount(dt))  ?? 0
            let vc = (try? modelContext.fetchCount(dvc)) ?? 0
            return Int64(v + t) * 2 * kb + Int64(e + vc) * kb
        }()
        
        let noteBytes: Int64 = {
            var d = FetchDescriptor<KBNote>(predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false })
            d.fetchLimit = 100_000
            return Int64((try? modelContext.fetchCount(d)) ?? 0) * 3 * kb
        }()
        
        let calBytes: Int64 = {
            var d = FetchDescriptor<KBCalendarEvent>(predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false })
            d.fetchLimit = 100_000
            return Int64((try? modelContext.fetchCount(d)) ?? 0) * kb
        }()
        
        let todoBytes: Int64 = {
            var d = FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false })
            d.fetchLimit = 100_000
            return Int64((try? modelContext.fetchCount(d)) ?? 0) * kb
        }()
        
        // Foto e video: fileSize reale salvato in KBFamilyPhoto
        let photoBytes: Int64 = {
            let desc = FetchDescriptor<KBFamilyPhoto>(
                predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
            )
            let photos = (try? modelContext.fetch(desc)) ?? []
            return photos.reduce(0) { $0 + $1.fileSize }
        }()
        
        return docBytes + chatBytes + saluteBytes + noteBytes + calBytes + todoBytes + photoBytes
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
