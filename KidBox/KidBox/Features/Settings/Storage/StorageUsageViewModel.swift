//
//  StorageUsageViewModel.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseFunctions
import Combine

// MARK: - App Section

struct KBStorageSection: Identifiable {
    let id: String
    let name: String
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
    
    var freeBytes: Int64     { max(0, Self.totalQuotaBytes - usedBytes) }
    var usedFraction: Double { Double(usedBytes) / Double(Self.totalQuotaBytes) }
    var isNearLimit: Bool    { usedFraction >= 0.8 }
    var isOverLimit: Bool    { usedBytes >= Self.totalQuotaBytes }
    
    // MARK: - Load
    //
    // Fonte di verità: Firebase (stats/storage aggiornato dalle Cloud Functions).
    // Fallback locale se Firebase non risponde.
    
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
                        KBStorageGate.shared.cachedUsedBytes = Int64(remoteBytes)
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
    
    private func mergedSections(remote: [KBStorageSection], local: [KBStorageSection]) -> [KBStorageSection] {
        // Tutte le sezioni possibili, in ordine
        let allIds = ["photos", "documents", "chat", "salute", "expenses", "notes", "calendar", "todo"]
        
        let remoteMap = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let localMap  = Dictionary(uniqueKeysWithValues: local.map  { ($0.id, $0) })
        
        return allIds.compactMap { id -> KBStorageSection? in
            let r = remoteMap[id]
            let l = localMap[id]
            
            let bytes       = (r?.bytes ?? 0) > 0 ? (r!.bytes) : (l?.bytes ?? 0)
            let recordCount = l?.recordCount ?? r?.recordCount ?? 0
            
            guard bytes > 0 else { return nil }
            
            // Usa i metadati (nome, icona, colore) dalla versione remota se presente,
            // altrimenti dalla locale
            let source = r ?? l!
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
        
        // Documenti
        let docCount     = fetchCount(modelContext: modelContext, predicate: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false })
        let docFileBytes = fetchSum(modelContext: modelContext,   predicate: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false }, value: { $0.fileSize })
        
        // Chat media
        let chatMessages = fetchAll(modelContext: modelContext, predicate: #Predicate<KBChatMessage> {
            $0.familyId == fid && $0.isDeleted == false && $0.mediaStoragePath != nil
        })
        let chatBytes: Int64 = chatMessages.reduce(0) { acc, msg in
            acc + (msg.mediaFileSize ?? Self.chatMediaFallbackBytes)
        }
        
        // Foto album
        let photoBytes = fetchSum(modelContext: modelContext,
                                  predicate: #Predicate<KBFamilyPhoto> { $0.familyId == fid && $0.isDeleted == false },
                                  value: { $0.fileSize })
        let photoCount = fetchCount(modelContext: modelContext,
                                    predicate: #Predicate<KBFamilyPhoto> { $0.familyId == fid && $0.isDeleted == false })
        
        // Salute: foto visite
        let visits = fetchAll(modelContext: modelContext, predicate: #Predicate<KBMedicalVisit> {
            $0.familyId == fid && $0.isDeleted == false
        })
        let visitPhotoCount = visits.reduce(0) { $0 + $1.photoURLs.count }
        let visitPhotoBytes = Int64(visitPhotoCount) * Self.visitPhotoEstimateBytes
        let visitCount     = visits.count
        let examCount      = fetchCount(modelContext: modelContext, predicate: #Predicate<KBMedicalExam>  { $0.familyId == fid && $0.isDeleted == false })
        let treatmentCount = fetchCount(modelContext: modelContext, predicate: #Predicate<KBTreatment>    { $0.familyId == fid && $0.isDeleted == false })
        let vaccineCount   = fetchCount(modelContext: modelContext, predicate: #Predicate<KBVaccine>      { $0.familyId == fid && $0.isDeleted == false })
        
        let noteCount  = fetchCount(modelContext: modelContext, predicate: #Predicate<KBNote>          { $0.familyId == fid && $0.isDeleted == false })
        let calCount   = fetchCount(modelContext: modelContext, predicate: #Predicate<KBCalendarEvent> { $0.familyId == fid && $0.isDeleted == false })
        let todoCount  = fetchCount(modelContext: modelContext, predicate: #Predicate<KBTodoItem>      { $0.familyId == fid && $0.isDeleted == false })
        let expCount   = fetchCount(modelContext: modelContext, predicate: #Predicate<KBExpense>       { $0.familyId == fid && $0.isDeleted == false })
        
        // Note/calendario/todo/spese occupano solo Firestore (niente file su Storage)
        // ma li includiamo come stima Firestore record overhead (1KB/record)
        // così appaiono nella UI anche prima che Firebase li tracci in stats/storage.
        let noteBytes  = Int64(noteCount)  * 3 * 1024  // 3KB/nota (HTML body)
        let calBytes   = Int64(calCount)   * 1024
        let todoBytes  = Int64(todoCount)  * 1024
        let expBytes   = Int64(expCount)   * 1024
        
        return [
            KBStorageSection(id: "photos",    name: "Foto e video",  icon: "photo.on.rectangle.angled",         color: "FF6B9D", bytes: photoBytes,      recordCount: photoCount),
            KBStorageSection(id: "documents", name: "Documenti",     icon: "doc.fill",                          color: "5B8FDE", bytes: docFileBytes,    recordCount: docCount),
            KBStorageSection(id: "chat",      name: "Chat",           icon: "bubble.left.and.bubble.right.fill", color: "34C759", bytes: chatBytes,       recordCount: chatMessages.count),
            KBStorageSection(id: "salute",    name: "Salute",         icon: "stethoscope",                       color: "FF6B6B", bytes: visitPhotoBytes, recordCount: visitCount + examCount + treatmentCount + vaccineCount),
            KBStorageSection(id: "expenses",  name: "Spese",          icon: "eurosign.circle.fill",              color: "FF9500", bytes: expBytes,        recordCount: expCount),
            KBStorageSection(id: "notes",     name: "Note",           icon: "note.text",                         color: "FF9F0A", bytes: noteBytes,       recordCount: noteCount),
            KBStorageSection(id: "calendar",  name: "Calendario",     icon: "calendar",                          color: "BF5AF2", bytes: calBytes,        recordCount: calCount),
            KBStorageSection(id: "todo",      name: "Liste & Todo",   icon: "checklist",                         color: "30B0C7", bytes: todoBytes,       recordCount: todoCount),
        ].filter { $0.bytes > 0 }
    }
    
    // MARK: - Fallback locale usato da KBStorageGate (quando cachedUsedBytes == 0)
    
    func localUsedBytes(modelContext: ModelContext, familyId: String) -> Int64 {
        let fid = familyId
        
        // Documenti (fileSize reale)
        let docBytes: Int64 = fetchSum(modelContext: modelContext,
                                       predicate: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
                                       value: { $0.fileSize })
        
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
        
        return docBytes + chatBytes + photoBytes + visitPhotoBytes
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
