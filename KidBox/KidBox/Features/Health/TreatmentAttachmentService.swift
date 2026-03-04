//
//  TreatmentAttachmentService.swift
//  KidBox
//
//  Ascolta KBEventBus per .treatmentAttachmentPending
//  e crea KBDocument in Documenti > Salute > Referti.
//
//  INTEGRAZIONE:
//  - Chiama TreatmentAttachmentService.shared.start(modelContext:)
//    una sola volta all'avvio app (KidBoxApp.swift o SyncCenter.startAll)
//  - Il wizard emette KBEventBus.shared.emit(.treatmentAttachmentPending(...))
//    e fa subito dismiss() — nessuna dipendenza diretta
//
//  DA CANCELLARE rispetto all'implementazione precedente:
//  - Il Task { for url in urls { await TreatmentAttachmentService.shared.upload(...) } dismiss() }
//    nel save() del wizard
//  - Qualsiasi chiamata diretta a TreatmentAttachmentService.shared.upload() dall'esterno

import Combine
import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseStorage
import QuickLook

// MARK: - Tag

enum TreatmentAttachmentTag {
    static func make(_ treatmentId: String) -> String { "treatment:\(treatmentId)" }
    static func matches(_ doc: KBDocument, treatmentId: String) -> Bool {
        doc.notes == make(treatmentId) && !doc.isDeleted
    }
}

// MARK: - Service (listener)

@MainActor
final class TreatmentAttachmentService {
    
    static let shared = TreatmentAttachmentService()
    private init() {}
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: Start — chiama una volta sola all'avvio
    
    func start(modelContext: ModelContext) {
        KBEventBus.shared.stream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (event: KBAppEvent) in
                guard let self else { return }
                switch event {
                case .treatmentAttachmentPending(let urls, let treatmentId, let familyId, let childId):
                    Task {
                        for url in urls {
                            await _ = self.upload(
                                url: url,
                                treatmentId: treatmentId,
                                familyId: familyId,
                                childId: childId,
                                modelContext: modelContext
                            )
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Cartelle Salute / Referti
    
    func ensureHealthFolders(
        familyId: String,
        modelContext: ModelContext
    ) -> (salute: KBDocumentCategory, referti: KBDocumentCategory) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let fid = familyId
        
        let desc = FetchDescriptor<KBDocumentCategory>(
            predicate: #Predicate<KBDocumentCategory> {
                $0.familyId == fid && $0.isDeleted == false
            }
        )
        let all = (try? modelContext.fetch(desc)) ?? []
        
        // "Salute" root
        let salute: KBDocumentCategory
        if let existing = all.first(where: {
            ($0.parentId == nil || $0.parentId == "") && $0.title == "Salute"
        }) {
            salute = existing
        } else {
            let nextOrder = (all
                .filter { $0.parentId == nil || $0.parentId == "" }
                .map(\.sortOrder).max() ?? 0) + 1
            let f = KBDocumentCategory(
                familyId: familyId, title: "Salute",
                sortOrder: nextOrder, parentId: nil,
                updatedBy: uid, createdAt: now, updatedAt: now, isDeleted: false
            )
            f.syncState = .pendingUpsert
            modelContext.insert(f)
            try? modelContext.save()
            SyncCenter.shared.enqueueDocumentCategoryUpsert(
                categoryId: f.id, familyId: familyId, modelContext: modelContext)
            salute = f
        }
        
        // "Referti" figlia di Salute
        // Cerca per parentId esatto OPPURE per titolo tra tutti i figli di qualsiasi "Salute"
        // (gestisce il caso account B dove Salute ha ID diverso da account A)
        let referti: KBDocumentCategory
        let sid = salute.id
        let saluteIds = Set(all.filter { $0.title == "Salute" }.map { $0.id })
        if let existing = all.first(where: {
            $0.title == "Referti" &&
            ($0.parentId == sid || saluteIds.contains($0.parentId ?? ""))
        }) {
            // Riusa — se parentId punta a Salute diversa, non importa: il contenuto è lo stesso
            referti = existing
        } else {
            let nextOrder = (all
                .filter { $0.parentId == sid }
                .map(\.sortOrder).max() ?? 0) + 1
            let f = KBDocumentCategory(
                familyId: familyId, title: "Referti",
                sortOrder: nextOrder, parentId: sid,
                updatedBy: uid, createdAt: now, updatedAt: now, isDeleted: false
            )
            f.syncState = .pendingUpsert
            modelContext.insert(f)
            try? modelContext.save()
            SyncCenter.shared.enqueueDocumentCategoryUpsert(
                categoryId: f.id, familyId: familyId, modelContext: modelContext)
            referti = f
        }
        
        return (salute, referti)
    }
    
    // MARK: - Upload (interno — chiamato solo dal listener)
    
    func upload(
        url: URL,
        treatmentId: String,
        familyId: String,
        childId: String,
        modelContext: ModelContext
    ) async -> KBDocument? {
        let okScope = url.startAccessingSecurityScopedResource()
        defer { if okScope { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        
        let uid         = Auth.auth().currentUser?.uid ?? "local"
        let now         = Date()
        let docId       = UUID().uuidString
        let fileName    = url.lastPathComponent
        let ext         = url.pathExtension.lowercased()
        let mime        = mimeType(for: ext)
        let title       = url.deletingPathExtension().lastPathComponent
        let storagePath = "families/\(familyId)/treatment-attachments/\(treatmentId)/\(docId)/\(fileName).kbenc"
        
        // Cartelle Salute/Referti (crea se non esistono)
        let (_, referti) = ensureHealthFolders(familyId: familyId, modelContext: modelContext)
        
        // Cache locale
        guard let localRelPath = try? DocumentLocalCache.write(
            familyId: familyId, docId: docId, fileName: fileName, data: data
        ) else { return nil }
        
        // KBDocument in cartella Referti
        let doc = KBDocument(
            id: docId,
            familyId: familyId,
            childId: childId,
            categoryId: referti.id,
            title: title,
            fileName: fileName,
            mimeType: mime,
            fileSize: Int64(data.count),
            storagePath: storagePath,
            downloadURL: nil,
            notes: TreatmentAttachmentTag.make(treatmentId),
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        doc.localPath = localRelPath
        doc.syncState = .pendingUpsert
        
        modelContext.insert(doc)
        try? modelContext.save()
        
        // Accoda sync Firestore metadata
        SyncCenter.shared.enqueueDocumentUpsert(
            documentId: doc.id, familyId: familyId, modelContext: modelContext)
        
        // Upload Firebase Storage — path già costruito, non passa per DocumentStorageService
        Task.detached {
            do {
                guard let encrypted = try? await DocumentCryptoService.encrypt(
                    data, familyId: familyId, userId: uid) else { return }
                let ref = Storage.storage().reference(withPath: storagePath)
                let metadata = StorageMetadata()
                metadata.contentType = "application/octet-stream"
                metadata.customMetadata = [
                    "kb_encrypted": "1",
                    "kb_alg":       "AES-GCM",
                    "kb_orig_mime": mime,
                    "kb_orig_name": fileName
                ]
                _ = try await ref.putDataAsync(encrypted, metadata: metadata)
                let downloadURL = try await ref.downloadURL().absoluteString
                await MainActor.run {
                    doc.downloadURL   = downloadURL
                    doc.syncState     = .synced
                    doc.updatedAt     = Date()
                    doc.updatedBy     = uid
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    doc.syncState     = .error
                    doc.lastSyncError = error.localizedDescription
                    try? modelContext.save()
                }
            }
        }
        
        return doc
    }
    
    
    // MARK: - Download remoto (auto, account B)
    
    /// Scarica e decripta un allegato arrivato da Firestore sull'account B.
    /// Chiamato automaticamente da applyDocumentInbound quando localPath è nil.
    func downloadRemoteAttachment(
        docId:        String,
        familyId:     String,
        storagePath:  String,
        fileName:     String,
        modelContext: ModelContext
    ) async {
        guard !storagePath.isEmpty else { return }
        
        KBLog.sync.kbDebug("downloadRemoteAttachment start docId=\(docId)")
        
        do {
            let ext = (fileName as NSString).pathExtension
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext.isEmpty ? "tmp" : ext)
            
            let ref  = Storage.storage().reference(withPath: storagePath)
            let task = ref.write(toFile: tmp)
            
            let tmpURL: URL = try await withCheckedThrowingContinuation { cont in
                var done = false
                task.observe(.success) { _ in
                    guard !done else { return }; done = true
                    cont.resume(returning: tmp)
                }
                task.observe(.failure) { snap in
                    guard !done else { return }; done = true
                    cont.resume(throwing: snap.error ?? NSError(
                        domain: "KidBox", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Download fallito"]))
                }
            }
            
            let encrypted = try Data(contentsOf: tmpURL)
            let userId    = Auth.auth().currentUser?.uid ?? "local"
            let decrypted = try DocumentCryptoService.decrypt(
                encrypted, familyId: familyId, userId: userId)
            
            let rel = try DocumentLocalCache.write(
                familyId: familyId, docId: docId,
                fileName: fileName.isEmpty ? docId : fileName,
                data: decrypted
            )
            
            try? FileManager.default.removeItem(at: tmpURL)
            
            // Aggiorna localPath nel KBDocument
            await MainActor.run {
                let did = docId
                let desc = FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })
                if let doc = try? modelContext.fetch(desc).first {
                    doc.localPath = rel
                    try? modelContext.save()
                    KBLog.sync.kbDebug("downloadRemoteAttachment saved localPath docId=\(docId)")
                }
            }
            
        } catch {
            KBLog.sync.kbError("downloadRemoteAttachment failed docId=\(docId): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Delete (soft)
    
    func delete(_ doc: KBDocument, modelContext: ModelContext) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        doc.isDeleted = true
        doc.updatedAt = Date()
        doc.updatedBy = uid
        try? modelContext.save()
        SyncCenter.shared.enqueueDocumentUpsert(
            documentId: doc.id, familyId: doc.familyId, modelContext: modelContext)
        let path = doc.storagePath
        Task.detached {
            try? await Storage.storage().reference(withPath: path).delete()
        }
    }
    
    // MARK: - Fetch allegati
    
    func fetchAttachments(
        treatmentId: String,
        familyId: String,
        modelContext: ModelContext
    ) -> [KBDocument] {
        let fid = familyId
        let desc = FetchDescriptor<KBDocument>(
            predicate: #Predicate<KBDocument> {
                $0.familyId == fid && $0.isDeleted == false
            },
            sortBy: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(desc)) ?? []
        return all.filter { TreatmentAttachmentTag.matches($0, treatmentId: treatmentId) }
    }
    
    // MARK: - Open / Preview
    
    func open(
        doc: KBDocument,
        modelContext: ModelContext,
        onURL:        @escaping (URL) -> Void,
        onError:      @escaping (String) -> Void,
        onKeyMissing: @escaping () -> Void
    ) {
        let userId = Auth.auth().currentUser?.uid ?? "local"
        
        guard FamilyKeychainStore.loadFamilyKey(familyId: doc.familyId, userId: userId) != nil else {
            onKeyMissing(); return
        }
        
        // Cache locale
        if let localPath = doc.localPath, !localPath.isEmpty,
           DocumentLocalCache.exists(localPath: localPath) != nil {
            do {
                let plaintext = try DocumentLocalCache.readEncrypted(localPath: localPath)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(doc.id)_\(doc.fileName)")
                try plaintext.write(to: tempURL, options: .atomic)
                onURL(tempURL)
            } catch {
                isCryptoKeyError(error) ? onKeyMissing() : onError("Apertura fallita: \(error.localizedDescription)")
            }
            return
        }
        
        // Download da Firebase
        Task {
            do {
                let url = try await downloadAndDecrypt(doc: doc, modelContext: modelContext)
                onURL(url)
            } catch {
                isCryptoKeyError(error) ? onKeyMissing() : onError("Download fallito: \(error.localizedDescription)")
            }
        }
    }
    
    private func downloadAndDecrypt(doc: KBDocument, modelContext: ModelContext) async throws -> URL {
        guard !doc.storagePath.isEmpty else {
            throw NSError(domain: "KidBox", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "storagePath vuoto"])
        }
        let ext = (doc.fileName as NSString).pathExtension
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "tmp" : ext)
        
        let ref  = Storage.storage().reference(withPath: doc.storagePath)
        let task = ref.write(toFile: tmp)
        
        let tmpURL: URL = try await withCheckedThrowingContinuation { cont in
            var done = false
            task.observe(.success) { _ in guard !done else { return }; done = true; cont.resume(returning: tmp) }
            task.observe(.failure) { snap in
                guard !done else { return }; done = true
                cont.resume(throwing: snap.error ?? NSError(domain: "KidBox", code: -3,
                                                            userInfo: [NSLocalizedDescriptionKey: "Download fallito"]))
            }
        }
        
        let encrypted = try Data(contentsOf: tmpURL)
        let decrypted = try DocumentCryptoService.decrypt(
            encrypted, familyId: doc.familyId,
            userId: Auth.auth().currentUser?.uid ?? "local"
        )
        let rel = try DocumentLocalCache.write(
            familyId: doc.familyId, docId: doc.id,
            fileName: doc.fileName.isEmpty ? doc.id : doc.fileName,
            data: decrypted
        )
        doc.localPath = rel
        try? modelContext.save()
        try? FileManager.default.removeItem(at: tmpURL)
        return try DocumentLocalCache.resolve(localPath: rel)
    }
    
    // MARK: - Helpers
    
    private func mimeType(for ext: String) -> String {
        switch ext {
        case "pdf":             return "application/pdf"
        case "jpg", "jpeg":     return "image/jpeg"
        case "png":             return "image/png"
        case "heic":            return "image/heic"
        case "doc", "docx":     return "application/msword"
        case "xls", "xlsx":     return "application/vnd.ms-excel"
        default:                return "application/octet-stream"
        }
    }
    
    private func isCryptoKeyError(_ error: Error) -> Bool {
        let desc = error.localizedDescription.lowercased()
        if desc.contains("cryptokit") { return true }
        return (error as NSError).domain == "CryptoKit.CryptoKitError"
    }
}

// MARK: - TreatmentAttachmentPicker (Wizard step 3)

struct TreatmentAttachmentPicker: View {
    
    @Binding var pendingURLs: [URL]
    private let tint = Color(red: 0.6, green: 0.45, blue: 0.85)
    @State private var showImporter = false
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                
                Label("Allegati", systemImage: "paperclip")
                    .font(.subheadline.bold()).foregroundStyle(tint)
                
                if !pendingURLs.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(pendingURLs, id: \.absoluteString) { url in
                            HStack(spacing: 8) {
                                Image(systemName: fileIcon(url.pathExtension.lowercased()))
                                    .foregroundStyle(tint)
                                Text(url.lastPathComponent)
                                    .font(.caption).lineLimit(1)
                                Spacer()
                                Button {
                                    pendingURLs.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.06)))
                        }
                    }
                }
                
                Button { showImporter = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(tint)
                        Text("Aggiungi documento").font(.subheadline).foregroundStyle(tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.06)))
                }
                .buttonStyle(.plain)
                
                Text("Visibili anche in Documenti › Salute › Referti")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if let urls = try? result.get() { pendingURLs.append(contentsOf: urls) }
        }
    }
    
    private func fileIcon(_ ext: String) -> String {
        switch ext {
        case "pdf":                      return "doc.fill"
        case "jpg","jpeg","png","heic":  return "photo.fill"
        case "doc","docx":               return "doc.text.fill"
        case "xls","xlsx":               return "tablecells.fill"
        default:                         return "paperclip"
        }
    }
}

// MARK: - TreatmentAttachmentsSection (TreatmentDetailView)

struct TreatmentAttachmentsSection: View {
    
    let treatment: KBTreatment
    @Environment(\.modelContext) private var modelContext
    
    // ✅ @Query invece di @State manuale: SwiftData notifica automaticamente
    // ogni cambio (insert, isDeleted=true, sync remoto) senza reload() manuale.
    @Query private var attachments: [KBDocument]
    
    @State private var isUploading   = false
    @State private var showImporter  = false
    @State private var previewURL:   URL? = nil
    @State private var showKeyAlert  = false
    @State private var errorText:    String? = nil
    
    private let tint    = Color(red: 0.6, green: 0.45, blue: 0.85)
    private let service = TreatmentAttachmentService.shared
    
    init(treatment: KBTreatment) {
        self.treatment = treatment
        let fid = treatment.familyId
        let tag = TreatmentAttachmentTag.make(treatment.id)
        _attachments = Query(
            filter: #Predicate<KBDocument> {
                $0.familyId == fid &&
                $0.isDeleted == false &&
                $0.notes == tag
            },
            sort: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            HStack {
                Label("Allegati", systemImage: "paperclip")
                    .font(.subheadline.bold()).foregroundStyle(tint)
                Spacer()
                if isUploading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button { showImporter = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(tint).font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if let err = errorText {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            
            if attachments.isEmpty {
                Text("Nessun allegato")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(attachments) { doc in attachmentRow(doc) }
                }
            }
            
            Text("Visibili anche in Documenti › Salute › Referti")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
        // @Query si aggiorna da sola — nessun onAppear/reload necessario
        // Ascoltiamo il bus solo per aggiornare isUploading
        .onReceive(KBEventBus.shared.stream) { (event: KBAppEvent) in
            if case .treatmentAttachmentPending(_, let tid, _, _) = event,
               tid == treatment.id {
                isUploading = true
                // Nascondi spinner dopo 3s (upload in background)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isUploading = false }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else { return }
            // Upload direttamente da Detail (non passa dal wizard)
            KBEventBus.shared.emit(KBAppEvent.treatmentAttachmentPending(
                urls: urls,
                treatmentId: treatment.id,
                familyId: treatment.familyId,
                childId: treatment.childId
            ))
            // @Query si aggiorna da sola quando il KBDocument viene inserito
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let url = previewURL {
                QuickLookPreview(urls: [url], initialIndex: 0)
            }
        }
        .alert("Chiave mancante", isPresented: $showKeyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Chiave di crittografia non trovata. Verifica le impostazioni famiglia.")
        }
    }
    
    private func attachmentRow(_ doc: KBDocument) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: mimeIcon(doc.mimeType))
                    .foregroundStyle(tint).font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(sizeLabel(doc.fileSize)).font(.caption2).foregroundStyle(.secondary)
                    if doc.syncState == .pendingUpsert {
                        Image(systemName: "arrow.up.circle").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button {
                errorText = nil
                service.open(
                    doc: doc, modelContext: modelContext,
                    onURL:        { previewURL = $0 },
                    onError:      { errorText = $0 },
                    onKeyMissing: { showKeyAlert = true }
                )
            } label: {
                Image(systemName: "eye.fill").foregroundStyle(tint).font(.subheadline)
            }
            .buttonStyle(.plain)
            
            Button {
                service.delete(doc, modelContext: modelContext)
                // @Query reagisce automaticamente all'isDeleted=true
            } label: {
                Image(systemName: "trash").foregroundStyle(.red).font(.subheadline)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }
    
    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf")    { return "doc.fill" }
        if mime.contains("image")  { return "photo.fill" }
        if mime.contains("word")   { return "doc.text.fill" }
        if mime.contains("excel") || mime.contains("spreadsheet") { return "tablecells.fill" }
        return "paperclip"
    }
    
    private func sizeLabel(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
