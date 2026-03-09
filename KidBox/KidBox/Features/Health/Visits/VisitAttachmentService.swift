//
//  VisitAttachmentService.swift
//  KidBox
//

import Combine
import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseStorage
import QuickLook

// MARK: - Tag

enum VisitAttachmentTag {
    static func make(_ visitId: String) -> String { "visit:\(visitId)" }
    
    static func matches(_ doc: KBDocument, visitId: String) -> Bool {
        doc.notes == make(visitId) && !doc.isDeleted
    }
}

// MARK: - Service

@MainActor
final class VisitAttachmentService {
    
    static let shared = VisitAttachmentService()
    private init() {}
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Start
    
    func start(modelContext: ModelContext) {
        KBLog.storage.kbInfo("VisitAttachmentService start")
        
        KBEventBus.shared.stream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (event: KBAppEvent) in
                guard let self else { return }
                
                switch event {
                case .visitAttachmentPending(let urls, let visitId, let familyId, let childId):
                    KBLog.storage.kbInfo("Received visitAttachmentPending event visitId=\(visitId) familyId=\(familyId) childId=\(childId) urls=\(urls.count)")
                    
                    Task {
                        for url in urls {
                            KBLog.storage.kbDebug("Processing pending attachment url=\(url.lastPathComponent)")
                            await _ = self.upload(
                                url: url,
                                visitId: visitId,
                                familyId: familyId,
                                childId: childId,
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
    
    // MARK: - Cartelle Salute / Referti
    
    func ensureHealthFolders(
        familyId: String,
        modelContext: ModelContext
    ) -> (salute: KBDocumentCategory, referti: KBDocumentCategory) {
        KBLog.storage.kbDebug("Ensuring health folders familyId=\(familyId)")
        return TreatmentAttachmentService.shared.ensureHealthFolders(
            familyId: familyId,
            modelContext: modelContext
        )
    }
    
    // MARK: - Upload
    
    func upload(
        url: URL,
        visitId: String,
        familyId: String,
        childId: String,
        modelContext: ModelContext
    ) async -> KBDocument? {
        KBLog.storage.kbInfo("Upload start visitId=\(visitId) familyId=\(familyId) childId=\(childId) file=\(url.lastPathComponent)")
        
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
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let docId = UUID().uuidString
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let mime = mimeType(for: ext)
        let title = url.deletingPathExtension().lastPathComponent
        let storagePath = "families/\(familyId)/visit-attachments/\(visitId)/\(docId)/\(fileName).kbenc"
        
        KBLog.storage.kbDebug("Resolved attachment metadata docId=\(docId) mime=\(mime) storagePath=\(storagePath)")
        
        let (_, referti) = ensureHealthFolders(familyId: familyId, modelContext: modelContext)
        
        guard let localRelPath = try? DocumentLocalCache.write(
            familyId: familyId,
            docId: docId,
            fileName: fileName,
            data: data
        ) else {
            KBLog.storage.kbError("Failed writing local cache docId=\(docId) file=\(fileName)")
            return nil
        }
        
        KBLog.storage.kbDebug("Local cache write OK docId=\(docId) localRelPath=\(localRelPath)")
        
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
            notes: VisitAttachmentTag.make(visitId),
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
            KBLog.persistence.kbInfo("Inserted and saved attachment docId=\(doc.id) title=\(doc.title)")
        } catch {
            KBLog.persistence.kbError("Failed saving attachment docId=\(doc.id): \(error.localizedDescription)")
        }
        
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
        
        Task.detached {
            await KBLog.storage.kbInfo("Remote encrypted upload start docId=\(docId) file=\(fileName)")
            
            do {
                guard let encrypted = try? await DocumentCryptoService.encrypt(
                    data,
                    familyId: familyId,
                    userId: uid
                ) else {
                    await KBLog.crypto.kbError("Encryption failed docId=\(docId)")
                    return
                }
                
                await KBLog.crypto.kbDebug("Encryption completed docId=\(docId) encryptedBytes=\(encrypted.count)")
                
                let ref = Storage.storage().reference(withPath: storagePath)
                let metadata = StorageMetadata()
                metadata.contentType = "application/octet-stream"
                metadata.customMetadata = [
                    "kb_encrypted": "1",
                    "kb_alg": "AES-GCM",
                    "kb_orig_mime": mime,
                    "kb_orig_name": fileName
                ]
                
                _ = try await ref.putDataAsync(encrypted, metadata: metadata)
                await KBLog.storage.kbInfo("Remote upload completed docId=\(docId)")
                
                let downloadURL = try await ref.downloadURL().absoluteString
                await KBLog.storage.kbDebug("Download URL fetched docId=\(docId)")
                
                await MainActor.run {
                    doc.downloadURL = downloadURL
                    doc.syncState = .synced
                    doc.updatedAt = Date()
                    doc.updatedBy = uid
                    
                    do {
                        try modelContext.save()
                        KBLog.persistence.kbInfo("Attachment marked synced docId=\(doc.id)")
                    } catch {
                        KBLog.persistence.kbError("Failed saving synced attachment docId=\(doc.id): \(error.localizedDescription)")
                    }
                }
            } catch {
                await KBLog.storage.kbError("Remote upload failed docId=\(docId): \(error.localizedDescription)")
                
                await MainActor.run {
                    doc.syncState = .error
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
    
    func delete(_ doc: KBDocument, modelContext: ModelContext) {
        KBLog.storage.kbInfo("Delete attachment requested docId=\(doc.id) fileName=\(doc.fileName)")
        
        let path = doc.storagePath
        let local = doc.localPath
        
        if let lp = local, !lp.isEmpty {
            KBLog.storage.kbDebug("Deleting local cached file localPath=\(lp)")
            DocumentLocalCache.deleteFile(localPath: lp)
        } else {
            KBLog.storage.kbDebug("No local cached file to delete docId=\(doc.id)")
        }
        
        doc.localPath = nil
        
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
        visitId: String,
        familyId: String,
        modelContext: ModelContext
    ) -> [KBDocument] {
        KBLog.storage.kbDebug("Fetch attachments visitId=\(visitId) familyId=\(familyId)")
        
        let fid = familyId
        let desc = FetchDescriptor<KBDocument>(
            predicate: #Predicate<KBDocument> {
                $0.familyId == fid && $0.isDeleted == false
            },
            sortBy: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
        
        let all = (try? modelContext.fetch(desc)) ?? []
        let filtered = all.filter { VisitAttachmentTag.matches($0, visitId: visitId) }
        
        KBLog.storage.kbInfo("Fetched visit attachments total=\(all.count) filtered=\(filtered.count) visitId=\(visitId)")
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
        KBLog.storage.kbInfo("Open attachment requested docId=\(doc.id) fileName=\(doc.fileName)")
        
        TreatmentAttachmentService.shared.open(
            doc: doc,
            modelContext: modelContext,
            onURL: { url in
                KBLog.storage.kbInfo("Open attachment success docId=\(doc.id) url=\(url.lastPathComponent)")
                onURL(url)
            },
            onError: { error in
                KBLog.storage.kbError("Open attachment failed docId=\(doc.id): \(error)")
                onError(error)
            },
            onKeyMissing: {
                KBLog.crypto.kbError("Open attachment failed: key missing docId=\(doc.id)")
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
        modelContext: ModelContext
    ) async {
        KBLog.storage.kbInfo("Download remote attachment docId=\(docId) familyId=\(familyId) fileName=\(fileName)")
        
        await TreatmentAttachmentService.shared.downloadRemoteAttachment(
            docId: docId,
            familyId: familyId,
            storagePath: storagePath,
            fileName: fileName,
            modelContext: modelContext
        )
    }
    
    // MARK: - Helpers
    
    private func mimeType(for ext: String) -> String {
        let resolved: String
        switch ext {
        case "pdf": resolved = "application/pdf"
        case "jpg", "jpeg": resolved = "image/jpeg"
        case "png": resolved = "image/png"
        case "heic": resolved = "image/heic"
        case "doc", "docx": resolved = "application/msword"
        case "xls", "xlsx": resolved = "application/vnd.ms-excel"
        default: resolved = "application/octet-stream"
        }
        
        KBLog.storage.kbDebug("Resolved mimeType ext=\(ext) -> \(resolved)")
        return resolved
    }
}

// MARK: - VisitAttachmentsSection

struct VisitAttachmentsSection: View {
    
    let visit: KBMedicalVisit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Query private var attachments: [KBDocument]
    
    @State private var isUploading = false
    @State private var showSourcePicker = false
    @State private var showImporter = false
    @State private var showGallery = false
    @State private var showCamera = false
    @State private var previewURL: URL? = nil
    @State private var showKeyAlert = false
    @State private var errorText: String? = nil
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    private let service = VisitAttachmentService.shared
    
    init(visit: KBMedicalVisit) {
        self.visit = visit
        let fid = visit.familyId
        _attachments = Query(
            filter: #Predicate<KBDocument> {
                $0.familyId == fid &&
                $0.isDeleted == false
            },
            sort: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
    }
    
    private var visitAttachments: [KBDocument] {
        let tag = VisitAttachmentTag.make(visit.id)
        return attachments.filter { $0.notes == tag }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            HStack {
                Label("Allegati", systemImage: "paperclip")
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
                
                Spacer()
                
                if isUploading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button {
                        KBLog.ui.kbDebug("Show attachment source picker visitId=\(visit.id)")
                        showSourcePicker = true
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
            
            if visitAttachments.isEmpty {
                Text("Nessun allegato")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(visitAttachments) { attachmentRow($0) }
                }
            }
            
            Text("Visibili anche in Documenti › Salute › Referti")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
        )
        .sheet(isPresented: $showSourcePicker) {
            AttachmentSourcePickerSheet(
                onCamera: {
                    KBLog.ui.kbInfo("Attachment source selected: camera visitId=\(visit.id)")
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCamera = true }
                },
                onGallery: {
                    KBLog.ui.kbInfo("Attachment source selected: gallery visitId=\(visit.id)")
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showGallery = true }
                },
                onDocument: {
                    KBLog.ui.kbInfo("Attachment source selected: document importer visitId=\(visit.id)")
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showImporter = true }
                }
            )
            .presentationDetents([.height(250)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGallery) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                KBLog.ui.kbInfo("Gallery image picked visitId=\(visit.id)")
                if let url = saveImageToTemp(image) { emitUpload(urls: [url]) }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in
                KBLog.ui.kbInfo("Camera image picked visitId=\(visit.id)")
                if let url = saveImageToTemp(image) { emitUpload(urls: [url]) }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else {
                KBLog.ui.kbError("File importer failed visitId=\(visit.id)")
                return
            }
            KBLog.ui.kbInfo("File importer returned urls=\(urls.count) visitId=\(visit.id)")
            emitUpload(urls: urls)
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
        .onReceive(KBEventBus.shared.stream) { (event: KBAppEvent) in
            if case .visitAttachmentPending(_, let vid, _, _) = event, vid == visit.id {
                KBLog.ui.kbDebug("VisitAttachmentsSection received pending upload event visitId=\(visit.id)")
                isUploading = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    isUploading = false
                    KBLog.ui.kbDebug("VisitAttachmentsSection upload spinner auto-hide visitId=\(visit.id)")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func emitUpload(urls: [URL]) {
        KBLog.ui.kbInfo("Emit visit attachment upload visitId=\(visit.id) urls=\(urls.count)")
        isUploading = true
        KBEventBus.shared.emit(KBAppEvent.visitAttachmentPending(
            urls: urls,
            visitId: visit.id,
            familyId: visit.familyId,
            childId: visit.childId
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
                
                extractionStatusView(for: doc)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    KBLog.ui.kbInfo("Open attachment tapped docId=\(doc.id)")
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
                
                if doc.extractionStatus == .failed {
                    Button("Riprova") {
                        KBLog.ui.kbInfo("Retry extraction tapped docId=\(doc.id)")
                        let uid = Auth.auth().currentUser?.uid ?? "local"
                        DocumentTextExtractionCoordinator.shared.enqueueExtraction(
                            for: doc,
                            updatedBy: uid,
                            modelContext: modelContext
                        )
                    }
                    .font(.caption2)
                    .foregroundStyle(tint)
                    .buttonStyle(.plain)
                }
                
                Button {
                    KBLog.ui.kbInfo("Delete attachment tapped docId=\(doc.id)")
                    service.delete(doc, modelContext: modelContext)
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
    
    @ViewBuilder
    private func extractionStatusView(for doc: KBDocument) -> some View {
        switch doc.extractionStatus {
        case .none:
            EmptyView()
            
        case .pending:
            Label("Analisi testo in attesa", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
        case .processing:
            Label("Analisi testo in corso...", systemImage: "text.viewfinder")
                .font(.caption2)
                .foregroundStyle(.orange)
            
        case .completed:
            Label("Testo estratto disponibile", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
            
        case .failed:
            VStack(alignment: .leading, spacing: 2) {
                Label("Analisi testo non riuscita", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                
                if let error = doc.extractionError, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
    
    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf") { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        if mime.contains("word") { return "doc.text.fill" }
        if mime.contains("excel") || mime.contains("spreadsheet") { return "tablecells.fill" }
        return "paperclip"
    }
    
    private func sizeLabel(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

// MARK: - VisitAttachmentPicker

struct VisitAttachmentPicker: View {
    
    @Binding var pendingURLs: [URL]
    let onAddTapped: () -> Void
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            HStack {
                Label("Allegati della Visita", systemImage: "paperclip")
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
                Spacer()
                Text("\(pendingURLs.count)/5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text("Aggiungi ricette, referti, esami o foto della visita")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if !pendingURLs.isEmpty {
                VStack(spacing: 6) {
                    ForEach(pendingURLs, id: \.absoluteString) { url in
                        HStack(spacing: 8) {
                            if let img = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: fileIcon(url.pathExtension.lowercased()))
                                    .foregroundStyle(tint)
                                    .frame(width: 32, height: 32)
                            }
                            
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Button {
                                KBLog.ui.kbInfo("Remove pending attachment file=\(url.lastPathComponent)")
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
            
            Button {
                KBLog.ui.kbInfo("VisitAttachmentPicker add tapped currentCount=\(pendingURLs.count)")
                onAddTapped()
            } label: {
                Label("Aggiungi allegato", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.1)))
                    .foregroundStyle(tint)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(pendingURLs.count >= 5)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
    }
    
    private func fileIcon(_ ext: String) -> String {
        switch ext {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "heic": return "photo.fill"
        case "doc", "docx": return "doc.text.fill"
        default: return "paperclip"
        }
    }
}
