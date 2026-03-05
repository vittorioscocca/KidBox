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
        KBEventBus.shared.stream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (event: KBAppEvent) in
                guard let self else { return }
                switch event {
                case .visitAttachmentPending(let urls, let visitId, let familyId, let childId):
                    Task {
                        for url in urls {
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
    
    // MARK: - Cartelle Salute / Referti (riusa TreatmentAttachmentService)
    
    func ensureHealthFolders(
        familyId: String,
        modelContext: ModelContext
    ) -> (salute: KBDocumentCategory, referti: KBDocumentCategory) {
        TreatmentAttachmentService.shared.ensureHealthFolders(
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
        let storagePath = "families/\(familyId)/visit-attachments/\(visitId)/\(docId)/\(fileName).kbenc"
        
        let (_, referti) = ensureHealthFolders(familyId: familyId, modelContext: modelContext)
        
        guard let localRelPath = try? DocumentLocalCache.write(
            familyId: familyId, docId: docId, fileName: fileName, data: data
        ) else { return nil }
        
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
        try? modelContext.save()
        
        SyncCenter.shared.enqueueDocumentUpsert(
            documentId: doc.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
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
                    doc.downloadURL = downloadURL
                    doc.syncState   = .synced
                    doc.updatedAt   = Date()
                    doc.updatedBy   = uid
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
    
    // MARK: - Delete
    
    func delete(_ doc: KBDocument, modelContext: ModelContext) {
        let path  = doc.storagePath
        let local = doc.localPath
        
        if let lp = local, !lp.isEmpty {
            DocumentLocalCache.deleteFile(localPath: lp)
        }
        doc.localPath = nil
        
        SyncCenter.shared.enqueueDocumentDelete(
            documentId: doc.id, familyId: doc.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        if !path.isEmpty {
            Task.detached {
                do {
                    try await Storage.storage().reference(withPath: path).delete()
                } catch {
                    await KBLog.sync.kbError("VisitAttachmentService: Storage delete failed path=\(path) err=\(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Fetch
    
    func fetchAttachments(
        visitId: String,
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
        return all.filter { VisitAttachmentTag.matches($0, visitId: visitId) }
    }
    
    // MARK: - Open
    
    func open(
        doc: KBDocument,
        modelContext: ModelContext,
        onURL:        @escaping (URL) -> Void,
        onError:      @escaping (String) -> Void,
        onKeyMissing: @escaping () -> Void
    ) {
        // Riusa la stessa logica di TreatmentAttachmentService
        TreatmentAttachmentService.shared.open(
            doc: doc,
            modelContext: modelContext,
            onURL: onURL,
            onError: onError,
            onKeyMissing: onKeyMissing
        )
    }
    
    // MARK: - Helpers
    
    // MARK: - Download remoto (sync da altri dispositivi)
    
    func downloadRemoteAttachment(
        docId:        String,
        familyId:     String,
        storagePath:  String,
        fileName:     String,
        modelContext: ModelContext
    ) async {
        await TreatmentAttachmentService.shared.downloadRemoteAttachment(
            docId:        docId,
            familyId:     familyId,
            storagePath:  storagePath,
            fileName:     fileName,
            modelContext: modelContext
        )
    }
    
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
}

// MARK: - VisitAttachmentsSection
// Da usare nel PediatricVisitDetailView

struct VisitAttachmentsSection: View {
    
    let visit: KBMedicalVisit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Query private var attachments: [KBDocument]
    
    @State private var isUploading      = false
    @State private var showSourcePicker = false
    @State private var showImporter     = false
    @State private var showGallery      = false
    @State private var showCamera       = false
    @State private var previewURL: URL? = nil
    @State private var showKeyAlert     = false
    @State private var errorText: String? = nil
    
    private let tint    = Color(red: 0.35, green: 0.6, blue: 0.85)
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
                    .font(.subheadline.bold()).foregroundStyle(tint)
                Spacer()
                if isUploading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button { showSourcePicker = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(tint).font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if let err = errorText {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            
            if visitAttachments.isEmpty {
                Text("Nessun allegato")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(visitAttachments) { attachmentRow($0) }
                }
            }
            
            Text("Visibili anche in Documenti › Salute › Referti")
                .font(.caption2).foregroundStyle(.tertiary)
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
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCamera = true }
                },
                onGallery: {
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showGallery = true }
                },
                onDocument: {
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showImporter = true }
                }
            )
            .presentationDetents([.height(250)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGallery) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                if let url = saveImageToTemp(image) { emitUpload(urls: [url]) }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in
                if let url = saveImageToTemp(image) { emitUpload(urls: [url]) }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else { return }
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
                isUploading = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isUploading = false }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func emitUpload(urls: [URL]) {
        isUploading = true
        KBEventBus.shared.emit(KBAppEvent.visitAttachmentPending(
            urls: urls,
            visitId: visit.id,
            familyId: visit.familyId,
            childId: visit.childId
        ))
    }
    
    private func saveImageToTemp(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        try? data.write(to: url)
        return url
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
            
            Button { service.delete(doc, modelContext: modelContext) } label: {
                Image(systemName: "trash").foregroundStyle(.red).font(.subheadline)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(KBTheme.inputBackground(colorScheme))
        )
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

// MARK: - VisitAttachmentPicker
// Da usare nello step 4 del wizard PediatricVisitEditView

struct VisitAttachmentPicker: View {
    
    @Binding var pendingURLs: [URL]
    let onAddTapped: () -> Void
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            HStack {
                Label("Allegati della Visita", systemImage: "paperclip")
                    .font(.subheadline.bold()).foregroundStyle(tint)
                Spacer()
                Text("\(pendingURLs.count)/5")
                    .font(.caption).foregroundStyle(.secondary)
            }
            
            Text("Aggiungi ricette, referti, esami o foto della visita")
                .font(.caption).foregroundStyle(.secondary)
            
            if !pendingURLs.isEmpty {
                VStack(spacing: 6) {
                    ForEach(pendingURLs, id: \.absoluteString) { url in
                        HStack(spacing: 8) {
                            if let img = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: fileIcon(url.pathExtension.lowercased()))
                                    .foregroundStyle(tint)
                                    .frame(width: 32, height: 32)
                            }
                            Text(url.lastPathComponent)
                                .font(.caption).lineLimit(1)
                            Spacer()
                            Button {
                                pendingURLs.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.06)))
                    }
                }
            }
            
            Button { onAddTapped() } label: {
                Label("Aggiungi allegato", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.1)))
                    .foregroundStyle(tint).font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(pendingURLs.count >= 5)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
    }
    
    private func fileIcon(_ ext: String) -> String {
        switch ext {
        case "pdf":                     return "doc.fill"
        case "jpg","jpeg","png","heic": return "photo.fill"
        case "doc","docx":              return "doc.text.fill"
        default:                        return "paperclip"
        }
    }
}
