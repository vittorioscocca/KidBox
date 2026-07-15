//
//  ExpenseAttachmentService.swift
//  KidBox
//
//  Gestisce gli allegati (ricevute, PDF, foto) delle spese di famiglia.

import Combine
import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseStorage
import QuickLook

// MARK: - Tag

enum ExpenseAttachmentTag {
    static func make(_ expenseId: String) -> String { "expense:\(expenseId)" }
    
    static func matches(_ doc: KBDocument, expenseId: String) -> Bool {
        doc.notes == make(expenseId) && !doc.isDeleted
    }
}

// MARK: - Service

@MainActor
final class ExpenseAttachmentService {
    
    static let shared = ExpenseAttachmentService()
    private init() {}
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - ID deterministici
    //
    // Gli ID sono deterministici per evitare duplicati su device diversi.
    // Se due device chiamano ensureExpensesFolder contemporaneamente, troveranno
    // (o creeranno) esattamente la stessa cartella con lo stesso ID —
    // nessuna duplicazione in SwiftData né su Firestore.
    
    /// ID fisso della root "Spese" per questa famiglia.
    /// Formato: "exp-root-<familyId>"
    private static func speseRootId(familyId: String) -> String {
        "exp-root-\(familyId)"
    }
    
    /// ID fisso della sottocartella per una singola spesa.
    /// Formato: "exp-cat-<expenseId>"
    private static func speseSubfolderId(expenseId: String) -> String {
        "exp-cat-\(expenseId)"
    }
    
    // MARK: - Start (KBEventBus listener)
    
    func start(modelContext: ModelContext) {
        KBLog.storage.kbInfo("ExpenseAttachmentService start")
        
        KBEventBus.shared.stream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (event: KBAppEvent) in
                guard let self else { return }
                
                switch event {
                case .expenseAttachmentPending(let urls, let expenseId, let expenseTitle, let familyId):
                    KBLog.storage.kbInfo("Received expenseAttachmentPending event expenseId=\(expenseId) familyId=\(familyId) urls=\(urls.count)")
                    
                    Task {
                        for url in urls {
                            KBLog.storage.kbDebug("Processing pending expense attachment url=\(url.lastPathComponent)")
                            await _ = self.upload(
                                url: url,
                                expenseId: expenseId,
                                expenseTitle: expenseTitle,
                                familyId: familyId,
                                modelContext: modelContext
                            )
                        }
                    }
                    
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Ensure "Spese" folder hierarchy in Documents
    
    /// Crea (o recupera) SOLO la cartella root "Spese" (parentId = nil).
    ///
    /// L'ID è deterministico ("exp-root-<familyId>") — idempotente su tutti i device.
    /// Chiamato da SyncCenter.startExpensesRealtime per garantire che la
    /// cartella esista sul dispositivo ricevente prima che arrivino allegati inbound.
    @discardableResult
    func ensureExpensesRootFolder(
        familyId: String,
        modelContext: ModelContext
    ) -> KBDocumentCategory {
        let uid    = Auth.auth().currentUser?.uid ?? "local"
        let rootId = Self.speseRootId(familyId: familyId)
        let rid    = rootId   // copia locale per #Predicate
        
        // Cerca per ID deterministico — non per titolo+parentId per evitare
        // falsi negativi se la cartella esiste già con questo ID ma non è
        // ancora visibile tramite la query generica.
        let desc = FetchDescriptor<KBDocumentCategory>(
            predicate: #Predicate { $0.id == rid && $0.isDeleted == false }
        )
        if let existing = (try? modelContext.fetch(desc))?.first {
            KBLog.storage.kbDebug("📁 [expenses][folder] root already exists catId=\(existing.id)")
            return existing
        }
        
        let speseFolder = KBDocumentCategory(
            id: rootId,          // ← ID deterministico, mai duplicato
            familyId: familyId,
            title: "Spese",
            sortOrder: 99,
            parentId: nil,
            updatedBy: uid
        )
        modelContext.insert(speseFolder)
        try? modelContext.save()
        SyncCenter.shared.enqueueDocumentCategoryUpsert(
            categoryId: speseFolder.id,
            familyId: familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        KBLog.storage.kbInfo("📁 [expenses][folder] root created catId=\(speseFolder.id) familyId=\(familyId)")
        return speseFolder
    }
    
    /// Crea (o recupera) la gerarchia:
    ///   📁 Spese                    ← root, id = "exp-root-<familyId>"
    ///     📁 <titolo spesa>         ← sottocartella, id = "exp-cat-<expenseId>"
    ///
    /// Entrambi gli ID sono deterministici → idempotente su tutti i device,
    /// nessuna duplicazione anche se chiamato più volte o da device diversi.
    ///
    /// Se `expenseId` è vuoto, crea/restituisce solo la root "Spese".
    @discardableResult
    func ensureExpensesFolder(
        familyId: String,
        expenseId: String,
        expenseTitle: String,
        modelContext: ModelContext
    ) -> KBDocumentCategory {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        
        // ── 1. Root "Spese" — ID deterministico ─────────────────────────────
        let speseFolder = ensureExpensesRootFolder(familyId: familyId, modelContext: modelContext)
        
        // ── Early return se expenseId è vuoto ───────────────────────────────
        // Questo path viene usato da SyncCenter.startExpensesRealtime per
        // pre-creare la cartella "Spese" senza una spesa specifica.
        guard !expenseId.isEmpty else {
            KBLog.storage.kbDebug("📁 [expenses][folder] expenseId empty → returning root only catId=\(speseFolder.id)")
            return speseFolder
        }
        
        // ── 2. Sottocartella per la singola spesa — ID deterministico ────────
        let subFolderId = Self.speseSubfolderId(expenseId: expenseId)
        let subId       = subFolderId   // copia locale per #Predicate
        
        let subDesc = FetchDescriptor<KBDocumentCategory>(
            predicate: #Predicate { $0.id == subId && $0.isDeleted == false }
        )
        if let existing = (try? modelContext.fetch(subDesc))?.first {
            KBLog.storage.kbDebug("📁 [expenses][folder] subfolder already exists catId=\(existing.id) expenseId=\(expenseId)")
            return existing
        }
        
        let safeName = expenseTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "Spesa"
        : expenseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let subFolder = KBDocumentCategory(
            id: subFolderId,
            familyId: familyId,
            title: safeName,
            sortOrder: 0,
            parentId: speseFolder.id,   // ← parentId deterministico
            updatedBy: uid
        )
        modelContext.insert(subFolder)
        try? modelContext.save()
        SyncCenter.shared.enqueueDocumentCategoryUpsert(
            categoryId: subFolder.id,
            familyId: familyId,
            modelContext: modelContext
        )
        // Flush dopo la subfolder (la root è già stata flushata da ensureExpensesRootFolder)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        KBLog.storage.kbInfo("📁 [expenses][folder] subfolder created catId=\(subFolder.id) expenseId=\(expenseId)")
        return subFolder
    }
    
    // MARK: - Upload
    
    func upload(
        url: URL,
        expenseId: String,
        expenseTitle: String,
        familyId: String,
        modelContext: ModelContext
    ) async -> KBDocument? {
        KBLog.storage.kbInfo("Upload start expenseId=\(expenseId) familyId=\(familyId) file=\(url.lastPathComponent)")
        
        let okScope = url.startAccessingSecurityScopedResource()
        defer {
            if okScope {
                url.stopAccessingSecurityScopedResource()
                KBLog.storage.kbDebug("Stopped security scoped access file=\(url.lastPathComponent)")
            }
        }
        
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            KBLog.storage.kbError("Upload aborted: unable to read data or empty file file=\(url.lastPathComponent)")
            return nil
        }
        
        KBLog.storage.kbDebug("Loaded local file bytes=\(data.count) file=\(url.lastPathComponent)")
        
        let uid         = Auth.auth().currentUser?.uid ?? "local"
        let now         = Date()
        let docId       = UUID().uuidString
        let originalFileName = url.lastPathComponent
        let ext         = url.pathExtension.lowercased()
        let originalMime = mimeType(for: ext)
        let title       = url.deletingPathExtension().lastPathComponent

        // Comprimi le immagini ad alta risoluzione prima di cifrare/caricare.
        let compressed = DocumentImageCompressor.compressIfNeeded(
            data: data, fileName: originalFileName, mimeType: originalMime)
        let uploadData  = compressed.data
        let fileName    = compressed.fileName
        let mime        = compressed.mimeType

        // Il path di Storage usa "documents" — le Security Rules concedono
        // accesso solo a families/{fid}/documents/...
        let storagePath = "families/\(familyId)/documents/\(docId)/\(fileName).kbenc"
        
        KBLog.storage.kbDebug("Resolved attachment metadata docId=\(docId) mime=\(mime) storagePath=\(storagePath)")
        
        let expensesFolder = ensureExpensesFolder(
            familyId: familyId,
            expenseId: expenseId,
            expenseTitle: expenseTitle,
            modelContext: modelContext
        )
        
        // Encrypt before writing to local cache.
        guard let encrypted = try? DocumentCryptoService.encrypt(uploadData, familyId: familyId, userId: uid) else {
            KBLog.storage.kbError("Encrypt failed docId=\(docId) file=\(fileName)")
            return nil
        }
        guard let localRelPath = try? DocumentLocalCache.write(
            familyId: familyId,
            docId: docId,
            fileName: fileName,
            data: encrypted
        ) else {
            KBLog.storage.kbError("Failed writing local cache docId=\(docId) file=\(fileName)")
            return nil
        }
        
        KBLog.storage.kbDebug("Local cache write OK docId=\(docId) localRelPath=\(localRelPath)")
        
        let doc = KBDocument(
            id: docId,
            familyId: familyId,
            childId: nil,
            categoryId: expensesFolder.id,
            title: title,
            fileName: fileName,
            mimeType: mime,
            fileSize: Int64(uploadData.count),
            storagePath: storagePath,
            downloadURL: nil,
            notes: ExpenseAttachmentTag.make(expenseId),
            createdBy: uid.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        
        doc.localPath = localRelPath
        doc.syncState = .pendingUpsert
        
        modelContext.insert(doc)
        
        do {
            try modelContext.save()
            KBLog.persistence.kbInfo("Inserted and saved expense attachment docId=\(doc.id) title=\(doc.title)")
        } catch {
            KBLog.persistence.kbError("Failed saving expense attachment docId=\(doc.id): \(error.localizedDescription)")
        }
        
        updateExpenseAttachmentRef(expenseId: expenseId, docId: docId, modelContext: modelContext)
        
        KBLog.storage.kbInfo("Enqueue text extraction docId=\(doc.id)")
        DocumentTextExtractionCoordinator.shared.enqueueExtraction(
            for: doc,
            updatedBy: uid,
            modelContext: modelContext
        )
        
        KBLog.sync.kbInfo("Enqueue document upsert docId=\(doc.id) familyId=\(familyId)")
        SyncCenter.shared.enqueueDocumentUpsert(
            documentId: doc.id,
            familyId: familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("Flush global requested after attachment insert docId=\(doc.id)")
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        // Upload remoto cifrato in background (reusa encrypted già calcolato sopra).
        Task.detached {
            await KBLog.storage.kbInfo("Remote encrypted upload start docId=\(docId) file=\(fileName)")
            
            do {
                await KBLog.crypto.kbDebug("Encryption ready docId=\(docId) encryptedBytes=\(encrypted.count)")
                
                let ref      = Storage.storage().reference(withPath: storagePath)
                let metadata = StorageMetadata()
                metadata.contentType = "application/octet-stream"
                metadata.customMetadata = [
                    "kb_encrypted": "1",
                    "kb_alg":       "AES-GCM",
                    "kb_orig_mime": mime,
                    "kb_orig_name": fileName
                ]
                
                _ = try await ref.putDataAsync(encrypted, metadata: metadata)
                await KBLog.storage.kbInfo("Remote upload completed docId=\(docId)")
                
                let downloadURL = try await ref.downloadURL().absoluteString
                await KBLog.storage.kbDebug("Download URL fetched docId=\(docId)")
                
                await MainActor.run {
                    doc.downloadURL = downloadURL
                    doc.syncState   = .synced
                    doc.updatedAt   = Date()
                    doc.updatedBy   = uid
                    
                    do {
                        try modelContext.save()
                        KBLog.persistence.kbInfo("Attachment marked synced docId=\(doc.id)")
                    } catch {
                        KBLog.persistence.kbError("Failed saving synced attachment docId=\(doc.id): \(error.localizedDescription)")
                    }
                    
                    SyncCenter.shared.enqueueDocumentUpsert(
                        documentId: doc.id,
                        familyId: familyId,
                        modelContext: modelContext
                    )
                    SyncCenter.shared.flushGlobal(modelContext: modelContext)
                }
            } catch {
                await KBLog.storage.kbError("Remote upload failed docId=\(docId): \(error.localizedDescription)")
                
                await MainActor.run {
                    doc.syncState     = .error
                    doc.lastSyncError = error.localizedDescription
                    
                    do {
                        try modelContext.save()
                        KBLog.persistence.kbError("Attachment marked error docId=\(doc.id)")
                    } catch {
                        KBLog.persistence.kbError("Failed saving upload error state docId=\(doc.id): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        KBLog.storage.kbInfo("Upload pipeline completed locally docId=\(doc.id)")
        return doc
    }
    
    // MARK: - Delete
    
    func delete(_ doc: KBDocument, expenseId: String, modelContext: ModelContext) {
        KBLog.storage.kbInfo("Delete expense attachment requested docId=\(doc.id) fileName=\(doc.fileName)")
        
        let path  = doc.storagePath
        let local = doc.localPath
        
        if let lp = local, !lp.isEmpty {
            KBLog.storage.kbDebug("Deleting local cached file localPath=\(lp)")
            DocumentLocalCache.deleteFile(localPath: lp)
        } else {
            KBLog.storage.kbDebug("No local cached file to delete docId=\(doc.id)")
        }
        
        doc.localPath = nil
        
        clearExpenseAttachmentRef(expenseId: expenseId, docId: doc.id, modelContext: modelContext)
        
        KBLog.sync.kbInfo("Enqueue document delete docId=\(doc.id) familyId=\(doc.familyId)")
        SyncCenter.shared.enqueueDocumentDelete(
            documentId: doc.id,
            familyId: doc.familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("Flush global requested after delete docId=\(doc.id)")
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        if !path.isEmpty {
            Task.detached {
                do {
                    await KBLog.storage.kbInfo("Deleting remote storage object path=\(path)")
                    try await Storage.storage().reference(withPath: path).delete()
                    await KBLog.storage.kbInfo("Remote storage delete OK path=\(path)")
                } catch {
                    await KBLog.storage.kbError("Storage delete failed path=\(path) err=\(error.localizedDescription)")
                }
            }
        } else {
            KBLog.storage.kbDebug("No remote storage path to delete docId=\(doc.id)")
        }
    }
    
    // MARK: - Fetch
    
    func fetchAttachments(
        expenseId: String,
        familyId: String,
        modelContext: ModelContext
    ) -> [KBDocument] {
        KBLog.storage.kbDebug("Fetch expense attachments expenseId=\(expenseId) familyId=\(familyId)")
        
        let fid  = familyId
        let desc = FetchDescriptor<KBDocument>(
            predicate: #Predicate<KBDocument> {
                $0.familyId == fid && $0.isDeleted == false
            },
            sortBy: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
        
        let all      = (try? modelContext.fetch(desc)) ?? []
        let filtered = all.filter { ExpenseAttachmentTag.matches($0, expenseId: expenseId) }
        
        KBLog.storage.kbInfo("Fetched expense attachments total=\(all.count) filtered=\(filtered.count) expenseId=\(expenseId)")
        return filtered
    }
    
    // MARK: - Open
    
    func open(
        doc: KBDocument,
        modelContext: ModelContext,
        onURL: @escaping (URL) -> Void,
        onError: @escaping (String) -> Void,
        onKeyMissing: @escaping () -> Void
    ) {
        KBLog.storage.kbInfo("Open expense attachment requested docId=\(doc.id) fileName=\(doc.fileName)")
        
        TreatmentAttachmentService.shared.open(
            doc: doc,
            modelContext: modelContext,
            onURL: { url in
                KBLog.storage.kbInfo("Open expense attachment success docId=\(doc.id) url=\(url.lastPathComponent)")
                onURL(url)
            },
            onError: { error in
                KBLog.storage.kbError("Open expense attachment failed docId=\(doc.id): \(error)")
                onError(error)
            },
            onKeyMissing: {
                KBLog.crypto.kbError("Open expense attachment failed: key missing docId=\(doc.id)")
                onKeyMissing()
            }
        )
    }
    
    // MARK: - Download remoto (sync da altri dispositivi)
    
    func downloadRemoteAttachment(
        docId: String,
        familyId: String,
        storagePath: String,
        fileName: String,
        notes: String? = nil,
        modelContext: ModelContext
    ) async {
        KBLog.storage.kbInfo("Download remote expense attachment docId=\(docId) familyId=\(familyId) fileName=\(fileName)")
        
        await TreatmentAttachmentService.shared.downloadRemoteAttachment(
            docId: docId,
            familyId: familyId,
            storagePath: storagePath,
            fileName: fileName,
            notes: notes,
            modelContext: modelContext
        )
    }
    
    // MARK: - Private helpers
    
    private func updateExpenseAttachmentRef(
        expenseId: String,
        docId: String,
        modelContext: ModelContext
    ) {
        let eid  = expenseId
        let desc = FetchDescriptor<KBExpense>(
            predicate: #Predicate { $0.id == eid && $0.isDeleted == false }
        )
        guard let expense = (try? modelContext.fetch(desc))?.first else {
            KBLog.persistence.kbError("updateExpenseAttachmentRef: expense not found expenseId=\(expenseId)")
            return
        }
        expense.attachedDocumentId = docId
        expense.updatedAt          = Date()
        try? modelContext.save()
        
        SyncCenter.shared.enqueueExpenseUpsert(
            expenseId: expenseId,
            familyId: expense.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        KBLog.persistence.kbDebug("updateExpenseAttachmentRef OK + enqueued sync expenseId=\(expenseId) docId=\(docId)")
    }
    
    private func clearExpenseAttachmentRef(
        expenseId: String,
        docId: String,
        modelContext: ModelContext
    ) {
        let eid  = expenseId
        let desc = FetchDescriptor<KBExpense>(
            predicate: #Predicate { $0.id == eid && $0.isDeleted == false }
        )
        guard let expense = (try? modelContext.fetch(desc))?.first,
              expense.attachedDocumentId == docId else { return }
        expense.attachedDocumentId = nil
        expense.updatedAt          = Date()
        try? modelContext.save()
        
        SyncCenter.shared.enqueueExpenseUpsert(
            expenseId: expenseId,
            familyId: expense.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        KBLog.persistence.kbDebug("clearExpenseAttachmentRef OK + enqueued sync expenseId=\(expenseId)")
    }
    
    private func mimeType(for ext: String) -> String {
        let resolved: String
        switch ext {
        case "pdf":               resolved = "application/pdf"
        case "jpg", "jpeg":       resolved = "image/jpeg"
        case "png":               resolved = "image/png"
        case "heic":              resolved = "image/heic"
        case "doc", "docx":       resolved = "application/msword"
        case "xls", "xlsx":       resolved = "application/vnd.ms-excel"
        default:                  resolved = "application/octet-stream"
        }
        KBLog.storage.kbDebug("Resolved mimeType ext=\(ext) -> \(resolved)")
        return resolved
    }
}

// MARK: - KBAppEvent extension
//
// Aggiungi questo case all'enum KBAppEvent esistente nel progetto:
//
//   case expenseAttachmentPending(urls: [URL], expenseId: String, expenseTitle: String, familyId: String)
//

// MARK: - ExpenseAttachmentsSection

/// View embedded nel form AddEditExpenseView e nella ExpenseDetailView.
/// Gestisce la visualizzazione, aggiunta e rimozione degli allegati di una spesa,
/// con lo stesso comportamento di VisitAttachmentsSection.
struct ExpenseAttachmentsSection: View {
    
    let expense: KBExpense
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    @Query private var attachments: [KBDocument]
    
    @State private var isUploading     = false
    @State private var showSourcePicker = false
    @State private var showImporter    = false
    @State private var showGallery     = false
    @State private var showCamera      = false
    @State private var showKidBoxPicker = false
    @State private var previewURL: URL? = nil
    @State private var showKeyAlert    = false
    @State private var showStorageUpgrade = false
    @State private var errorText: String? = nil
    
    private let tint    = Color.accentColor
    private let service = ExpenseAttachmentService.shared
    
    init(expense: KBExpense) {
        self.expense = expense
        let fid = expense.familyId
        _attachments = Query(
            filter: #Predicate<KBDocument> {
                $0.familyId == fid && $0.isDeleted == false
            },
            sort: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
    }
    
    private var expenseAttachments: [KBDocument] {
        let tag = ExpenseAttachmentTag.make(expense.id)
        return attachments.filter { $0.notes == tag }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Header
            HStack {
                Label("Allegati", systemImage: "paperclip")
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
                
                Spacer()
                
                if isUploading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button {
                        KBLog.ui.kbDebug("Show attachment source picker expenseId=\(expense.id)")
                        checkUploadAllowed(modelContext: modelContext, familyId: expense.familyId, showUpgrade: $showStorageUpgrade) {
                            showSourcePicker = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(tint)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if let err = errorText {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            // Lista allegati
            if expenseAttachments.isEmpty {
                Text("Nessun allegato")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(expenseAttachments) { attachmentRow($0) }
                }
            }
            
            Text("Visibili anche in Documenti › Spese")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
        )
        // Source picker sheet
        .sheet(isPresented: $showSourcePicker) {
            AttachmentSourcePickerSheet(
                tint: Color.accentColor,
                onCamera: {
                    KBLog.ui.kbInfo("Attachment source: camera expenseId=\(expense.id)")
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCamera = true }
                },
                onGallery: {
                    KBLog.ui.kbInfo("Attachment source: gallery expenseId=\(expense.id)")
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showGallery = true }
                },
                onDocument: {
                    KBLog.ui.kbInfo("Attachment source: document importer expenseId=\(expense.id)")
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showImporter = true }
                },
                onKidBoxDocument: {
                    KBLog.ui.kbInfo("Attachment source: kidbox documents expenseId=\(expense.id)")
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showKidBoxPicker = true }
                }
            )
        }
        .sheet(isPresented: $showKidBoxPicker) {
            KidBoxDocumentPickerSheet(familyId: expense.familyId) { url in
                emitUpload(urls: [url])
            }
        }
        // Gallery
        .sheet(isPresented: $showGallery) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                KBLog.ui.kbInfo("Gallery image picked expenseId=\(expense.id)")
                if let url = saveImageToTemp(image) { emitUpload(urls: [url]) }
            }
        }
        // Camera
        .sheet(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in
                KBLog.ui.kbInfo("Camera image picked expenseId=\(expense.id)")
                if let url = saveImageToTemp(image) { emitUpload(urls: [url]) }
            }
        }
        // File importer
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else {
                KBLog.ui.kbError("File importer failed expenseId=\(expense.id)")
                return
            }
            KBLog.ui.kbInfo("File importer returned urls=\(urls.count) expenseId=\(expense.id)")
            emitUpload(urls: urls)
        }
        // QuickLook preview
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let url = previewURL {
                QuickLookPreview(urls: [url], initialIndex: 0)
            }
        }
        // Key missing alert
        .alert("Chiave mancante", isPresented: $showKeyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Chiave di crittografia non trovata. Verifica le impostazioni famiglia.")
        }
        .storageUpgradeSheet($showStorageUpgrade)
        // Spinner reset dopo evento
        .onReceive(KBEventBus.shared.stream) { (event: KBAppEvent) in
            if case .expenseAttachmentPending(_, let eid, _, _) = event, eid == expense.id {
                KBLog.ui.kbDebug("ExpenseAttachmentsSection received pending upload event expenseId=\(expense.id)")
                isUploading = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    isUploading = false
                    KBLog.ui.kbDebug("ExpenseAttachmentsSection upload spinner auto-hide expenseId=\(expense.id)")
                }
            }
        }
    }
    
    // MARK: - Row
    
    private func attachmentRow(_ doc: KBDocument) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: mimeIcon(doc.mimeType))
                    .foregroundStyle(tint)
                    .font(.subheadline)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title)
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(sizeLabel(doc.fileSize))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if doc.syncState == .pendingUpsert {
                        Image(systemName: "arrow.up.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 10) {
                // Apri
                Button {
                    KBLog.ui.kbInfo("Open expense attachment tapped docId=\(doc.id)")
                    errorText = nil
                    service.open(
                        doc: doc,
                        modelContext: modelContext,
                        onURL: { previewURL = $0 },
                        onError: { errorText = $0 },
                        onKeyMissing: { showKeyAlert = true }
                    )
                } label: {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(tint)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                
                // Elimina
                Button {
                    KBLog.ui.kbInfo("Delete expense attachment tapped docId=\(doc.id)")
                    service.delete(doc, expenseId: expense.id, modelContext: modelContext)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(KBTheme.inputBackground(colorScheme))
        )
    }
    
    // MARK: - Helpers
    
    private func emitUpload(urls: [URL]) {
        KBLog.ui.kbInfo("Emit expense attachment upload expenseId=\(expense.id) urls=\(urls.count)")
        isUploading = true
        KBEventBus.shared.emit(KBAppEvent.expenseAttachmentPending(
            urls: urls,
            expenseId: expense.id,
            expenseTitle: expense.title,
            familyId: expense.familyId
        ))
    }
    
    private func saveImageToTemp(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            KBLog.storage.kbError("saveImageToTemp failed: jpegData nil")
            return nil
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: url)
            KBLog.storage.kbDebug("Temporary image saved path=\(url.lastPathComponent) bytes=\(data.count)")
            return url
        } catch {
            KBLog.storage.kbError("saveImageToTemp write failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf")   { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        if mime.contains("word")  { return "doc.text.fill" }
        if mime.contains("excel") || mime.contains("spreadsheet") { return "tablecells.fill" }
        return "paperclip"
    }
    
    private func sizeLabel(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
