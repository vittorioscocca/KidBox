//
//  KBStorageGateLite.swift
//  KidBox
//
//  Created by vscocca on 24/03/26.
//

//
//  KBStorageGateLite.swift
//  KidBox — target: Main App + Share Extension
//
//  Versione leggera e senza dipendenze di KBStorageGate.
//  Nessun import SwiftData, nessun singleton dell'app principale:
//  legge tutto da UserDefaults (App Group), scritto da
//  StorageUsageViewModel.persistUsedBytesToAppGroup() dopo ogni sync.
//
//  Chiavi UserDefaults attese (App Group):
//    "storageUsedBytes_<familyId>"  → Int64   — byte usati su Storage
//    "storageQuotaBytes_<familyId>" → Int64   — quota del piano corrente
//
//  Se "storageUsedBytes" non è ancora disponibile → 0 (permissivo al primo avvio).
//  Se "storageQuotaBytes" non è ancora disponibile → FREE_QUOTA (200 MB, conservativo).
//
//  UTILIZZO dalla Share Extension:
//
//      switch KBStorageGateLite.canUpload(bytes: fileSize,
//                                         appGroupId: appGroupId,
//                                         familyId: familyId) {
//      case .allowed:
//          // procedi con l'upload
//      case .blocked(let title, let message):
//          errorMessage = "\(title): \(message)"
//      }

import Foundation

// MARK: - Result

enum KBStorageGateLiteResult {
    case allowed
    case blocked(title: String, message: String)
}

// MARK: - Gate

enum KBStorageGateLite {
    
    /// Quota di fallback se l'App Group non ha ancora la chiave.
    /// Allineata con StorageUsageViewModel.quotaFree.
    private static let fallbackQuota: Int64 = 200 * 1024 * 1024   // 200 MB
    
    // MARK: - Controllo storage
    
    /// Controlla se è possibile caricare un file di `bytes` byte.
    /// Passare `bytes: 0` per verificare solo se la quota è già esaurita.
    static func canUpload(
        bytes: Int64 = 0,
        appGroupId: String,
        familyId: String
    ) -> KBStorageGateLiteResult {
        
        let defaults = UserDefaults(suiteName: appGroupId)
        
        let used: Int64  = defaults?.object(forKey: "storageUsedBytes_\(familyId)")  as? Int64 ?? 0
        let quota: Int64 = (defaults?.object(forKey: "storageQuotaBytes_\(familyId)") as? Int64)
            .flatMap { $0 > 0 ? $0 : nil } ?? fallbackQuota
        
        if used >= quota {
            return .blocked(
                title: "Spazio esaurito",
                message: "La famiglia ha usato \(used.liteFormattedFileSize) su \(quota.liteFormattedFileSize). Passa a Pro per 5 GB."
            )
        }
        if bytes > 0, (used + bytes) > quota {
            let free = quota - used
            return .blocked(
                title: "Spazio insufficiente",
                message: "Questo file richiede \(bytes.liteFormattedFileSize) ma hai solo \(free.liteFormattedFileSize) liberi su \(quota.liteFormattedFileSize). Passa a Pro per 5 GB."
            )
        }
        return .allowed
    }
}

// MARK: - Int64 formatting (self-contained, nessuna dipendenza da altri file)

extension Int64 {
    /// Versione locale per KBStorageGateLite — non dipende da StorageUsageViewModel.
    var liteFormattedFileSize: String {
        let kb = Double(self) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}
