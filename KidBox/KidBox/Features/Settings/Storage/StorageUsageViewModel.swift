//
//  StorageUsageViewModel.swift
//  KidBox
//

import Foundation
import SwiftUI
import SwiftData
import FirebaseFunctions
import Combine

// MARK: - App Section

struct KBStorageSection: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let icon: String
    let color: String
    let bytes: Int64
    let recordCount: Int
}

// MARK: - ViewModel

@MainActor
final class StorageUsageViewModel: ObservableObject {
    
    // MARK: - Published
    
    @Published var sections: [KBStorageSection] = []
    @Published var usedBytes: Int64 = 0
    @Published var isLoading = false
    @Published var error: String? = nil
    
    // MARK: - Constants
    
    static let quotaFree: Int64 = 200  * 1024 * 1024
    static let quotaPro:  Int64 = 5    * 1024 * 1024 * 1024
    static let quotaMax:  Int64 = 20   * 1024 * 1024 * 1024
    
    /// TODO: leggere dal piano utente quando subscription sarà implementato.
    static let totalQuotaBytes: Int64 = quotaFree
    
    /// Stima dimensione foto visita pediatrica su Storage (compressa, media mobile).
    private static let visitPhotoEstimateBytes: Int64 = 200 * 1024  // 200 KB
    
    /// Fallback per messaggi chat media senza mediaFileSize (messaggi precedenti al campo).
    private static let chatMediaFallbackBytes: Int64 = 512 * 1024   // 512 KB
    
    // MARK: - Computed
    
    /// Quota corrente in base al piano abbonamento — aggiornata dinamicamente.
    var currentQuota: Int64  { KBSubscriptionManager.shared.currentPlan.storageQuota }
    
    var freeBytes: Int64     { max(0, currentQuota - usedBytes) }
    var usedFraction: Double { Double(usedBytes) / Double(max(1, currentQuota)) }
    var isNearLimit: Bool    { usedFraction >= 0.8 }
    var isOverLimit: Bool    { usedBytes >= currentQuota }
    
    // MARK: - Load
    //
    // Fonte di verità: Firebase (stats/storage aggiornato dalle Cloud Functions).
    // Fallback locale se Firebase non risponde.
    
    // ── Prefetch silenzioso all'avvio ─────────────────────────────────────────
    //
    // Chiamato da AppCoordinator subito dopo il login/bootstrap.
    // Popola KBStorageGate.cachedUsedBytes e la quota in App Group usando
    // `currentPlan` già impostato dal flusso principale (non chiama loadPlan).
    //
    static func prefetchForGate(familyId: String) async {
        guard !familyId.isEmpty else { return }
        KBLog.app.kbInfo("StorageUsageViewModel.prefetchForGate familyId=\(familyId)")
        
        // Bytes usati da Firebase
        do {
            let functions = Functions.functions(region: "europe-west1")
            let result = try await functions.httpsCallable("getStorageUsage")
                .call(["familyId": familyId])
            
            if let data = result.data as? [String: Any],
               let remoteBytes = data["usedBytes"] as? Int {
                let bytes = Int64(remoteBytes)
                let quota = KBSubscriptionManager.shared.currentPlan.storageQuota
                
                await MainActor.run {
                    KBStorageGate.shared.cachedUsedBytes = bytes
                }
                
                // ── Aggiorna App Group per KBStorageGateLite (Share Extension) ──
                // KBStorageGateLite legge queste chiavi da UserDefaults App Group.
                // Vanno aggiornate ogni volta che il gate principale si aggiorna
                // così la Share Extension usa sempre dati freschi.
                let appGroupId = "group.it.vittorioscocca.kidbox"
                let defaults   = UserDefaults(suiteName: appGroupId)
                defaults?.set(bytes, forKey: "storageUsedBytes_\(familyId)")
                defaults?.set(quota, forKey: "storageQuotaBytes_\(familyId)")
                defaults?.synchronize()
                
                KBLog.app.kbInfo("StorageUsageViewModel.prefetchForGate: cachedUsedBytes=\(bytes) quota=\(quota) appGroup=OK")
            }
        } catch {
            KBLog.app.kbError("StorageUsageViewModel.prefetchForGate failed: \(error.localizedDescription)")
            // fallback silenzioso: il gate userà 0 e permetterà upload
            // (comportamento conservativo — meglio permettere che bloccare erroneamente)
        }
    }
    
    func load(modelContext: ModelContext, familyId: String) {
        guard !familyId.isEmpty else { return }
        isLoading = true
        error = nil
        
        Task { @MainActor in
            defer { isLoading = false }
            
            do {
                let functions = Functions.functions(region: "europe-west1")
                let result = try await functions.httpsCallable("getStorageUsage")
                    .call(["familyId": familyId])
                
                if let data = result.data as? [String: Any] {
                    if let remoteBytes = data["usedBytes"] as? Int {
                        let bytes = Int64(remoteBytes)
                        KBStorageGate.shared.cachedUsedBytes = bytes
                        
                        // Aggiorna App Group per KBStorageGateLite (Share Extension)
                        let quota    = KBSubscriptionManager.shared.currentPlan.storageQuota
                        let defaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
                        defaults?.set(bytes, forKey: "storageUsedBytes_\(familyId)")
                        defaults?.set(quota, forKey: "storageQuotaBytes_\(familyId)")
                        defaults?.synchronize()
                    }
                    if let rawSections = data["sections"] as? [String: Any] {
                        let remoteSections = buildSections(from: rawSections)
                        let localSections  = buildSectionsFallback(modelContext: modelContext, familyId: familyId)
                        sections = mergedSections(remote: remoteSections, local: localSections)
                        // ✅ usedBytes = somma delle sezioni mostrate, così il totale
                        // nella card è sempre coerente con il breakdown visuale.
                        // cachedUsedBytes rimane quello di Firebase (usato dal Gate per i check reali).
                        usedBytes = sections.reduce(0) { $0 + $1.bytes }
                    }
                }
            } catch {
                self.error = "Impossibile aggiornare lo spazio da Firebase."
                usedBytes = localUsedBytes(modelContext: modelContext, familyId: familyId)
                KBStorageGate.shared.cachedUsedBytes = usedBytes
                sections = buildSectionsFallback(modelContext: modelContext, familyId: familyId)
            }
        }
    }
    
    // MARK: - Merge remote + local
    //
    // Per ogni sezione: se Firebase ha bytes > 0 usa quelli (fonte di verità),
    // altrimenti usa la stima locale (evita che sezioni spariscano dalla UI
    // perché il campo non è ancora stato inizializzato su Firestore).
    // Il recordCount viene sempre dal locale (Firebase non lo traccia).
    
    // Sezioni per cui i BYTES vengono solo da Firebase Storage (mai stime locali).
    // Il recordCount invece viene sempre dal locale.
    private static let storageOnlySections: Set<String> = ["chat", "photos"]
    
    private func mergedSections(remote: [KBStorageSection], local: [KBStorageSection]) -> [KBStorageSection] {
        let allIds = ["photos", "documents", "wallet", "chat", "salute", "expenses", "notes", "calendar", "todo"]
        
        // Nota: buildSections filtra già { bytes > 0 }, quindi sezioni con 0 su Firebase
        // non sono nel remoteMap. Per questo usiamo la raw map da tutti gli id.
        let remoteMap = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let localMap  = Dictionary(uniqueKeysWithValues: local.map  { ($0.id, $0) })
        
        return allIds.compactMap { id -> KBStorageSection? in
            let r = remoteMap[id]
            let l = localMap[id]
            
            let bytes: Int64
            if Self.storageOnlySections.contains(id) {
                // Bytes: solo Firebase. Se 0 o assente → 0 (non inventare stime).
                bytes = r?.bytes ?? 0
            } else {
                // Bytes: Firebase se disponibile, altrimenti stima locale.
                bytes = (r?.bytes ?? 0) > 0 ? r!.bytes : (l?.bytes ?? 0)
            }
            
            // recordCount: sempre dal locale (Firebase non lo traccia)
            let recordCount = l?.recordCount ?? r?.recordCount ?? 0
            
            // Per chat e photos: mostra la sezione se ci sono elementi locali
            // anche quando Firebase ha ancora 0 (non ancora inizializzato).
            // In quel caso bytes sarà 0 ma il recordCount mostrerà quanti file ci sono,
            // invitando l'utente a premere "Init Storage" per allineare Firebase.
            if Self.storageOnlySections.contains(id) {
                guard bytes > 0 || recordCount > 0 else { return nil }
            } else {
                guard bytes > 0 else { return nil }
            }
            
            let source = r ?? l
            guard let source else { return nil }
            return KBStorageSection(
                id:          source.id,
                name:        source.name,
                icon:        source.icon,
                color:       source.color,
                bytes:       bytes,
                recordCount: recordCount
            )
        }
    }
    
    // MARK: - Build sections da Firebase
    
    private func buildSections(from raw: [String: Any]) -> [KBStorageSection] {
        func bytes(_ key: String) -> Int64 { Int64(raw[key] as? Int ?? 0) }
        
        return [
            KBStorageSection(id: "photos",    name: "Foto e video",  icon: "photo.on.rectangle.angled",         color: "FF6B9D", bytes: bytes("photos"),    recordCount: 0),
            KBStorageSection(id: "documents", name: "Documenti",     icon: "doc.fill",                          color: "5B8FDE", bytes: bytes("documents"), recordCount: 0),
            KBStorageSection(id: "wallet",    name: "Wallet",        icon: "wallet.pass.fill",                 color: "3E7BFA", bytes: bytes("wallet"),    recordCount: 0),
            KBStorageSection(id: "chat",      name: "Chat",           icon: "bubble.left.and.bubble.right.fill", color: "34C759", bytes: bytes("chat"),      recordCount: 0),
            KBStorageSection(id: "salute",    name: "Salute",         icon: "stethoscope",                       color: "FF6B6B", bytes: bytes("salute"),    recordCount: 0),
            KBStorageSection(id: "expenses",  name: "Spese",          icon: "eurosign.circle.fill",              color: "FF9500", bytes: bytes("expenses"),  recordCount: 0),
            KBStorageSection(id: "notes",     name: "Note",           icon: "note.text",                         color: "FF9F0A", bytes: bytes("notes"),     recordCount: 0),
            KBStorageSection(id: "calendar",  name: "Calendario",     icon: "calendar",                          color: "BF5AF2", bytes: bytes("calendar"),  recordCount: 0),
            KBStorageSection(id: "todo",      name: "Liste & Todo",   icon: "checklist",                         color: "30B0C7", bytes: bytes("todo"),      recordCount: 0),
        ].filter { $0.bytes > 0 }
    }
    
    // MARK: - Breakdown locale (fallback se Firebase non risponde)
    //
    // Cosa conta su Firebase Storage per sezione:
    //
    // chat      → solo file media (foto/video/audio/doc). mediaFileSize reale se disponibile,
    //             512KB fallback per messaggi precedenti. I testi non occupano Storage.
    //
    // documents → fileSize reale da KBDocument. Le spese con attachedDocumentId puntano
    //             a KBDocument → già contate qui, nessun doppio conteggio.
    //
    // wallet    → byte reali del PDF cifrato (`KBWalletTicket.pdfStorageBytes`).
    //
    // photos    → fileSize reale da KBFamilyPhoto (album condiviso).
    //
    // salute    → solo KBMedicalVisit.photoURLs (foto allegate alla visita).
    //             Stima 200KB/foto perché non c'è fileSize nel modello.
    //             KBMedicalExam, KBTreatment, KBVaccine non hanno allegati su Storage.
    //
    // expenses  → receiptThumbnailData è Data locale SwiftData (non su Storage).
    //             I documenti allegati sono in KBDocument, già in "documents".
    //             → nessun conteggio separato per expenses nel fallback locale.
    
    private func buildSectionsFallback(modelContext: ModelContext, familyId: String) -> [KBStorageSection] {
        let fid = familyId
        
        // Documenti (fileSize reale)
        let docCount     = fetchCount(modelContext: modelContext, predicate: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false })
        let docFileBytes = fetchSum(modelContext: modelContext,   predicate: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false }, value: { $0.fileSize })

        // Wallet (PDF cifrati su Storage, bytes reali quando disponibili)
        let walletCount = fetchCount(modelContext: modelContext, predicate: #Predicate<KBWalletTicket> {
            $0.familyId == fid && $0.isDeleted == false && $0.pdfStorageURL != nil
        })
        let walletBytes = fetchSum(modelContext: modelContext, predicate: #Predicate<KBWalletTicket> {
            $0.familyId == fid && $0.isDeleted == false
        }, value: { $0.pdfStorageBytes ?? 0 })
        
        // Chat: NON calcoliamo i bytes localmente — fonte di verità = Firebase.
        // Calcoliamo solo il recordCount per il contatore visuale nella UI.
        let chatMediaCount = fetchCount(modelContext: modelContext, predicate: #Predicate<KBChatMessage> {
            $0.familyId == fid && $0.isDeleted == false && $0.mediaStoragePath != nil
        })
        // chatBytes = 0: il merge usa sempre Firebase per questa sezione
        
        // Foto album: anche qui solo recordCount, i bytes vengono da Firebase
        let photoCount = fetchCount(modelContext: modelContext,
                                    predicate: #Predicate<KBFamilyPhoto> { $0.familyId == fid && $0.isDeleted == false })
        // photoBytes = 0: il merge usa sempre Firebase per questa sezione
        
        // Salute: foto visite (stima 200KB/foto, Firebase non traccia ancora questo)
        let visits = fetchAll(modelContext: modelContext, predicate: #Predicate<KBMedicalVisit> {
            $0.familyId == fid && $0.isDeleted == false
        })
        let visitPhotoCount = visits.reduce(0) { $0 + $1.photoURLs.count }
        let visitPhotoBytes = Int64(visitPhotoCount) * Self.visitPhotoEstimateBytes
        let visitCount     = visits.count
        let examCount      = fetchCount(modelContext: modelContext, predicate: #Predicate<KBMedicalExam>  { $0.familyId == fid && $0.isDeleted == false })
        let treatmentCount = fetchCount(modelContext: modelContext, predicate: #Predicate<KBTreatment>    { $0.familyId == fid && $0.isDeleted == false })
        let vaccineCount   = fetchCount(modelContext: modelContext, predicate: #Predicate<KBVaccine>      { $0.familyId == fid && $0.isDeleted == false })
        
        // Note/calendario/todo/spese: overhead Firestore (1KB/record)
        let noteCount  = fetchCount(modelContext: modelContext, predicate: #Predicate<KBNote>          { $0.familyId == fid && $0.isDeleted == false })
        let calCount   = fetchCount(modelContext: modelContext, predicate: #Predicate<KBCalendarEvent> { $0.familyId == fid && $0.isDeleted == false })
        let todoCount  = fetchCount(modelContext: modelContext, predicate: #Predicate<KBTodoItem>      { $0.familyId == fid && $0.isDeleted == false })
        let expCount   = fetchCount(modelContext: modelContext, predicate: #Predicate<KBExpense>       { $0.familyId == fid && $0.isDeleted == false })
        
        let noteBytes = Int64(noteCount)  * 3 * 1024
        let calBytes  = Int64(calCount)   * 1024
        let todoBytes = Int64(todoCount)  * 1024
        let expBytes  = Int64(expCount)   * 1024
        
        return [
            // chat e photos: bytes = 0 → il merge usa Firebase come fonte di verità
            KBStorageSection(id: "chat",      name: "Chat",           icon: "bubble.left.and.bubble.right.fill", color: "34C759", bytes: 0,              recordCount: chatMediaCount),
            KBStorageSection(id: "photos",    name: "Foto e video",   icon: "photo.on.rectangle.angled",         color: "FF6B9D", bytes: 0,              recordCount: photoCount),
            // documenti: fileSize reale locale (allineato con Firebase)
            KBStorageSection(id: "documents", name: "Documenti",      icon: "doc.fill",                          color: "5B8FDE", bytes: docFileBytes,   recordCount: docCount),
            // wallet: byte reali del PDF cifrato (se presenti)
            KBStorageSection(id: "wallet",    name: "Wallet",         icon: "wallet.pass.fill",                 color: "3E7BFA", bytes: walletBytes,    recordCount: walletCount),
            // salute: stima locale (Firebase non traccia ancora le foto visite)
            KBStorageSection(id: "salute",    name: "Salute",          icon: "stethoscope",                       color: "FF6B6B", bytes: visitPhotoBytes, recordCount: visitCount + examCount + treatmentCount + vaccineCount),
            // le seguenti: overhead Firestore
            KBStorageSection(id: "expenses",  name: "Spese",           icon: "eurosign.circle.fill",              color: "FF9500", bytes: expBytes,       recordCount: expCount),
            KBStorageSection(id: "notes",     name: "Note",            icon: "note.text",                         color: "FF9F0A", bytes: noteBytes,      recordCount: noteCount),
            KBStorageSection(id: "calendar",  name: "Calendario",      icon: "calendar",                          color: "BF5AF2", bytes: calBytes,       recordCount: calCount),
            KBStorageSection(id: "todo",      name: "Liste & Todo",    icon: "checklist",                         color: "30B0C7", bytes: todoBytes,       recordCount: todoCount),
        ]
        // NON filtrare qui: il merge decide quali mostrare in base a Firebase
    }
    
    // MARK: - Fallback locale usato da KBStorageGate (quando cachedUsedBytes == 0)
    
    func localUsedBytes(modelContext: ModelContext, familyId: String) -> Int64 {
        let fid = familyId
        
        // Documenti (fileSize reale)
        let docBytes: Int64 = fetchSum(modelContext: modelContext,
                                       predicate: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
                                       value: { $0.fileSize })

        // Wallet (PDF cifrati)
        let walletBytes: Int64 = fetchSum(modelContext: modelContext,
                                          predicate: #Predicate<KBWalletTicket> { $0.familyId == fid && $0.isDeleted == false },
                                          value: { $0.pdfStorageBytes ?? 0 })
        
        // Chat media (fileSize reale o fallback 512KB per messaggi vecchi)
        let chatMessages = fetchAll(modelContext: modelContext, predicate: #Predicate<KBChatMessage> {
            $0.familyId == fid && $0.isDeleted == false && $0.mediaStoragePath != nil
        })
        let chatBytes: Int64 = chatMessages.reduce(0) { acc, msg in
            acc + (msg.mediaFileSize ?? Self.chatMediaFallbackBytes)
        }
        
        // Foto album condiviso (fileSize reale)
        let photoBytes: Int64 = fetchSum(modelContext: modelContext,
                                         predicate: #Predicate<KBFamilyPhoto> { $0.familyId == fid && $0.isDeleted == false },
                                         value: { $0.fileSize })
        
        // Foto visite pediatriche (stima 200KB/foto)
        let visits = fetchAll(modelContext: modelContext, predicate: #Predicate<KBMedicalVisit> {
            $0.familyId == fid && $0.isDeleted == false
        })
        let visitPhotoBytes = Int64(visits.reduce(0) { $0 + $1.photoURLs.count }) * Self.visitPhotoEstimateBytes
        
        // Note/calendario/todo/spese — Firestore overhead (stima locale)
        let noteCount = fetchCount(modelContext: modelContext, predicate: #Predicate<KBNote>          { $0.familyId == fid && $0.isDeleted == false })
        let calCount  = fetchCount(modelContext: modelContext, predicate: #Predicate<KBCalendarEvent> { $0.familyId == fid && $0.isDeleted == false })
        let todoCount = fetchCount(modelContext: modelContext, predicate: #Predicate<KBTodoItem>      { $0.familyId == fid && $0.isDeleted == false })
        let expCount  = fetchCount(modelContext: modelContext, predicate: #Predicate<KBExpense>       { $0.familyId == fid && $0.isDeleted == false })
        
        return docBytes + walletBytes + chatBytes + photoBytes + visitPhotoBytes
        + Int64(noteCount) * 3 * 1024
        + Int64(calCount)  * 1024
        + Int64(todoCount) * 1024
        + Int64(expCount)  * 1024
    }
    
    // MARK: - SwiftData helpers
    
    private func fetchCount<M: PersistentModel>(modelContext: ModelContext, predicate: Predicate<M>) -> Int {
        var desc = FetchDescriptor<M>(predicate: predicate)
        desc.fetchLimit = 100_000
        return (try? modelContext.fetchCount(desc)) ?? 0
    }
    
    private func fetchSum<M: PersistentModel>(modelContext: ModelContext, predicate: Predicate<M>, value: (M) -> Int64) -> Int64 {
        let desc = FetchDescriptor<M>(predicate: predicate)
        return ((try? modelContext.fetch(desc)) ?? []).reduce(0) { $0 + value($1) }
    }
    
    private func fetchAll<M: PersistentModel>(modelContext: ModelContext, predicate: Predicate<M>) -> [M] {
        var desc = FetchDescriptor<M>(predicate: predicate)
        desc.fetchLimit = 100_000
        return (try? modelContext.fetch(desc)) ?? []
    }
}

// MARK: - Formatting

extension Int64 {
    var formattedFileSize: String {
        let kb = Double(self) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}
