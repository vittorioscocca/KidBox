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
    
    private static let firestoreRecordBytes: Int64 = 1024
    
    // MARK: - Computed
    
    var freeBytes: Int64     { max(0, Self.totalQuotaBytes - usedBytes) }
    var usedFraction: Double { Double(usedBytes) / Double(Self.totalQuotaBytes) }
    var isNearLimit: Bool    { usedFraction >= 0.8 }
    var isOverLimit: Bool    { usedBytes >= Self.totalQuotaBytes }
    
    // MARK: - Load
    //
    // usedBytes → Firebase (fonte di verità unica, identica su tutti i device)
    // sections  → SwiftData locale (solo per breakdown visuale per sezione)
    
    // MARK: - Load
    
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
                    if let bytes = data["usedBytes"] as? Int {
                        usedBytes = Int64(bytes)
                        KBStorageGate.shared.cachedUsedBytes = usedBytes
                    }
                    if let rawSections = data["sections"] as? [String: Any] {
                        sections = buildSections(from: rawSections)
                    }
                }
            } catch {
                self.error = "Impossibile aggiornare lo spazio da Firebase."
                // Fallback locale se Firebase non risponde
                usedBytes = localUsedBytes(modelContext: modelContext, familyId: familyId)
                sections = buildSectionsFallback(modelContext: modelContext, familyId: familyId)
            }
        }
    }
    
    // MARK: - Build sections da Firebase
    
    private func buildSections(from raw: [String: Any]) -> [KBStorageSection] {
        func bytes(_ key: String) -> Int64 { Int64(raw[key] as? Int ?? 0) }
        
        return [
            KBStorageSection(id: "photos",    name: "Foto e video", icon: "photo.on.rectangle.angled",         color: "FF6B9D", bytes: bytes("photos"),   recordCount: 0),
            KBStorageSection(id: "documents", name: "Documenti",    icon: "doc.fill",                          color: "5B8FDE", bytes: bytes("documents"), recordCount: 0),
            KBStorageSection(id: "chat",      name: "Chat",          icon: "bubble.left.and.bubble.right.fill", color: "34C759", bytes: bytes("chat"),      recordCount: 0),
            KBStorageSection(id: "salute",    name: "Salute",        icon: "stethoscope",                       color: "FF6B6B", bytes: bytes("salute"),    recordCount: 0),
            KBStorageSection(id: "notes",     name: "Note",          icon: "note.text",                         color: "FF9F0A", bytes: bytes("notes"),     recordCount: 0),
            KBStorageSection(id: "calendar",  name: "Calendario",    icon: "calendar",                          color: "BF5AF2", bytes: bytes("calendar"),  recordCount: 0),
            KBStorageSection(id: "todo",      name: "Liste & Todo",  icon: "checklist",                         color: "30B0C7", bytes: bytes("todo"),      recordCount: 0),
        ].filter { $0.bytes > 0 }
    }
    
    // MARK: - Breakdown locale (visualizzazione per sezione)
    
    private func buildSectionsFallback(modelContext: ModelContext, familyId: String) -> [KBStorageSection] {
        let fid = familyId
        let kb  = Self.firestoreRecordBytes
        
        let docCount     = fetchCount(modelContext: modelContext, predicate: #Predicate<KBDocument>      { $0.familyId == fid && $0.isDeleted == false })
        let docFileBytes = fetchSum(modelContext: modelContext,   predicate: #Predicate<KBDocument>      { $0.familyId == fid && $0.isDeleted == false }, value: { $0.fileSize })
        let docBytes     = docFileBytes + Int64(docCount) * kb
        
        let chatCount      = fetchCount(modelContext: modelContext, predicate: #Predicate<KBChatMessage> { $0.familyId == fid && $0.isDeleted == false })
        let chatMediaCount = fetchCount(modelContext: modelContext, predicate: #Predicate<KBChatMessage> { $0.familyId == fid && $0.mediaStoragePath != nil })
        let chatBytes      = Int64(chatMediaCount) * 512 * 1024 + Int64(chatCount) * kb
        
        let visitCount     = fetchCount(modelContext: modelContext, predicate: #Predicate<KBMedicalVisit> { $0.familyId == fid && $0.isDeleted == false })
        let examCount      = fetchCount(modelContext: modelContext, predicate: #Predicate<KBMedicalExam>  { $0.familyId == fid && $0.isDeleted == false })
        let treatmentCount = fetchCount(modelContext: modelContext, predicate: #Predicate<KBTreatment>    { $0.familyId == fid && $0.isDeleted == false })
        let vaccineCount   = fetchCount(modelContext: modelContext, predicate: #Predicate<KBVaccine>      { $0.familyId == fid && $0.isDeleted == false })
        let saluteBytes    = Int64(visitCount + treatmentCount) * 2 * kb + Int64(examCount + vaccineCount) * kb
        
        let noteCount  = fetchCount(modelContext: modelContext, predicate: #Predicate<KBNote>          { $0.familyId == fid && $0.isDeleted == false })
        let calCount   = fetchCount(modelContext: modelContext, predicate: #Predicate<KBCalendarEvent> { $0.familyId == fid && $0.isDeleted == false })
        let todoCount  = fetchCount(modelContext: modelContext, predicate: #Predicate<KBTodoItem>      { $0.familyId == fid && $0.isDeleted == false })
        
        // Foto e video: usa fileSize reale salvato nel modello.
        // Per i video aggiunge anche i byte di durata stimati (1 MB/s) come overhead
        // rispetto alle immagini, in modo che il breakdown sia più preciso.
        let photoBytes = fetchSum(modelContext: modelContext,
                                  predicate: #Predicate<KBFamilyPhoto> { $0.familyId == fid && $0.isDeleted == false },
                                  value: { $0.fileSize })
        let photoCount = fetchCount(modelContext: modelContext,
                                    predicate: #Predicate<KBFamilyPhoto> { $0.familyId == fid && $0.isDeleted == false })
        
        return [
            KBStorageSection(id: "photos",    name: "Foto e video", icon: "photo.on.rectangle.angled",           color: "FF6B9D", bytes: photoBytes,                  recordCount: photoCount),
            KBStorageSection(id: "documents", name: "Documenti",    icon: "doc.fill",                            color: "5B8FDE", bytes: docBytes,                    recordCount: docCount),
            KBStorageSection(id: "chat",      name: "Chat",          icon: "bubble.left.and.bubble.right.fill",   color: "34C759", bytes: chatBytes,                   recordCount: chatCount),
            KBStorageSection(id: "salute",    name: "Salute",        icon: "stethoscope",                         color: "FF6B6B", bytes: saluteBytes,                 recordCount: visitCount + examCount + treatmentCount + vaccineCount),
            KBStorageSection(id: "notes",     name: "Note",          icon: "note.text",                           color: "FF9F0A", bytes: Int64(noteCount) * 3 * kb,   recordCount: noteCount),
            KBStorageSection(id: "calendar",  name: "Calendario",    icon: "calendar",                            color: "BF5AF2", bytes: Int64(calCount) * kb,        recordCount: calCount),
            KBStorageSection(id: "todo",      name: "Liste & Todo",  icon: "checklist",                           color: "30B0C7", bytes: Int64(todoCount) * kb,       recordCount: todoCount),
        ]
    }
    
    // MARK: - Fallback locale (se Firebase non risponde)
    
    func localUsedBytes(modelContext: ModelContext, familyId: String) -> Int64 {
        let fid = familyId
        let docBytes: Int64 = fetchSum(modelContext: modelContext,
                                       predicate: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
                                       value: { $0.fileSize })
        let chatMediaCount = fetchCount(modelContext: modelContext,
                                        predicate: #Predicate<KBChatMessage> { $0.familyId == fid && $0.mediaStoragePath != nil })
        // Foto e video: usa fileSize reale dal modello SwiftData
        let photoBytes: Int64 = fetchSum(modelContext: modelContext,
                                         predicate: #Predicate<KBFamilyPhoto> { $0.familyId == fid && $0.isDeleted == false },
                                         value: { $0.fileSize })
        return docBytes + Int64(chatMediaCount) * 512 * 1024 + photoBytes
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
