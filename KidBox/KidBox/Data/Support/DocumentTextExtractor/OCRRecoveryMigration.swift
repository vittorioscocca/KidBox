import Foundation
import SwiftData
import FirebaseAuth

@MainActor
enum OCRRecoveryMigration {
    private static let migrationKey = "kb_health_ocr_recovery_v1_done"

    static func runIfNeeded(modelContext: ModelContext) async {
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        let descriptor = FetchDescriptor<KBDocument>(
            predicate: #Predicate<KBDocument> { $0.isDeleted == false }
        )
        let allDocuments = (try? modelContext.fetch(descriptor)) ?? []
        let candidates = allDocuments.filter { doc in
            guard isHealthDocument(doc) else { return false }
            return doc.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }

        KBLog.storage.kbInfo("OCR recovery migration v1 start candidates=\(candidates.count)")
        if candidates.isEmpty {
            UserDefaults.standard.set(true, forKey: migrationKey)
            KBLog.storage.kbInfo("OCR recovery migration v1 completed (no candidates)")
            return
        }

        let userId = Auth.auth().currentUser?.uid ?? "local"
        for document in candidates {
            if document.localFileURL != nil {
                DocumentTextExtractionCoordinator.shared.enqueueExtraction(
                    for: document,
                    updatedBy: userId,
                    modelContext: modelContext
                )
                continue
            }

            guard !document.storagePath.isEmpty else { continue }
            await TreatmentAttachmentService.shared.downloadRemoteAttachment(
                docId: document.id,
                familyId: document.familyId,
                storagePath: document.storagePath,
                fileName: document.fileName,
                notes: document.notes,
                modelContext: modelContext
            )
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
        KBLog.storage.kbInfo("OCR recovery migration v1 completed")
    }

    private static func isHealthDocument(_ document: KBDocument) -> Bool {
        let tag = document.notes?.lowercased() ?? ""
        return tag.hasPrefix("visit:") || tag.hasPrefix("exam:") || tag.hasPrefix("treatment:")
    }
}
