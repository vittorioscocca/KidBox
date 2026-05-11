//
//  HomeAttachmentService.swift
//  KidBox
//
//  Allegati Casa (elementi / scadenze e pagamenti) — stesso flusso di VisitAttachmentService:
//  KBDocument in cartella Documenti › Casa, Storage cifrato, sync Firestore.
//

import Combine
import SwiftUI
import SwiftData
import UIKit
import FirebaseAuth
import FirebaseStorage
import QuickLook

// MARK: - Tags (notes su KBDocument)

enum HomeItemAttachmentTag {
    static func make(_ homeItemId: String) -> String { "homeItem:\(homeItemId)" }
    static func matches(_ doc: KBDocument, homeItemId: String) -> Bool {
        doc.notes == make(homeItemId) && !doc.isDeleted
    }
}

enum HousePaymentAttachmentTag {
    static func make(_ paymentId: String) -> String { "housePayment:\(paymentId)" }
    static func matches(_ doc: KBDocument, paymentId: String) -> Bool {
        doc.notes == make(paymentId) && !doc.isDeleted
    }
}

// MARK: - Service

@MainActor
final class HomeAttachmentService {

    static let shared = HomeAttachmentService()
    private init() {}

    private var cancellables = Set<AnyCancellable>()

    private static func casaRootId(familyId: String) -> String { "home-root-\(familyId)" }

    /// Cartella root «Casa» in Documenti (id deterministico `home-root-{familyId}`).
    func ensureCasaFolder(familyId: String, modelContext: ModelContext) -> KBDocumentCategory {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let rootId = Self.casaRootId(familyId: familyId)
        let fid = familyId
        let rid = rootId

        let desc = FetchDescriptor<KBDocumentCategory>(
            predicate: #Predicate<KBDocumentCategory> { $0.id == rid && $0.isDeleted == false }
        )
        if let existing = try? modelContext.fetch(desc).first {
            return existing
        }

        let folder = KBDocumentCategory(
            id: rootId,
            familyId: familyId,
            title: "Casa",
            sortOrder: 86,
            parentId: nil,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        modelContext.insert(folder)
        try? modelContext.save()
        SyncCenter.shared.enqueueDocumentCategoryUpsert(
            categoryId: folder.id,
            familyId: familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        return folder
    }

    func start(modelContext: ModelContext) {
        KBLog.storage.kbInfo("HomeAttachmentService start")

        KBEventBus.shared.stream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (event: KBAppEvent) in
                guard let self else { return }
                switch event {
                case .homeItemAttachmentPending(let urls, let homeItemId, let familyId):
                    Task {
                        for url in urls {
                            await self.uploadHomeItem(url: url, homeItemId: homeItemId, familyId: familyId, modelContext: modelContext)
                        }
                    }
                case .housePaymentAttachmentPending(let urls, let paymentId, let familyId):
                    Task {
                        for url in urls {
                            await self.uploadHousePayment(url: url, paymentId: paymentId, familyId: familyId, modelContext: modelContext)
                        }
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func uploadHomeItem(
        url: URL,
        homeItemId: String,
        familyId: String,
        modelContext: ModelContext
    ) async -> KBDocument? {
        await uploadCommon(
            url: url,
            familyId: familyId,
            notesTag: HomeItemAttachmentTag.make(homeItemId),
            storageScope: "home-item-attachments/\(homeItemId)",
            modelContext: modelContext
        )
    }

    func uploadHousePayment(
        url: URL,
        paymentId: String,
        familyId: String,
        modelContext: ModelContext
    ) async -> KBDocument? {
        await uploadCommon(
            url: url,
            familyId: familyId,
            notesTag: HousePaymentAttachmentTag.make(paymentId),
            storageScope: "house-payment-attachments/\(paymentId)",
            modelContext: modelContext
        )
    }

    private func uploadCommon(
        url: URL,
        familyId: String,
        notesTag: String,
        storageScope: String,
        modelContext: ModelContext
    ) async -> KBDocument? {
        let okScope = url.startAccessingSecurityScopedResource()
        defer {
            if okScope { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            KBLog.storage.kbError("Casa attachment: empty or unreadable \(url.lastPathComponent)")
            return nil
        }

        switch KBStorageGate.shared.canUpload(bytes: Int64(data.count), modelContext: modelContext, familyId: familyId) {
        case .allowed:
            break
        case .blocked(let reason):
            KBLog.storage.kbError("Casa attachment storage blocked: \(reason.message)")
            return nil
        }

        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let docId = UUID().uuidString
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let mime = mimeType(for: ext)
        let title = url.deletingPathExtension().lastPathComponent
        // Firebase Storage rules: uploads must live under `documents/` (same as DocumentStorageService).
        // Logical scope (home vs payment) stays in Firestore metadata + notes tag, not in the path.
        let storagePath = "families/\(familyId)/documents/\(docId)/\(fileName).kbenc"
        KBLog.storage.kbDebug("Casa attachment upload logicalScope=\(storageScope) storagePath=\(storagePath)")

        let casaFolder = ensureCasaFolder(familyId: familyId, modelContext: modelContext)

        guard let encrypted = try? DocumentCryptoService.encrypt(data, familyId: familyId, userId: uid) else {
            KBLog.storage.kbError("Casa attachment encrypt failed docId=\(docId)")
            return nil
        }
        guard let localRelPath = try? DocumentLocalCache.write(
            familyId: familyId,
            docId: docId,
            fileName: fileName,
            data: encrypted
        ) else {
            KBLog.storage.kbError("Casa attachment local cache failed docId=\(docId)")
            return nil
        }

        let doc = KBDocument(
            id: docId,
            familyId: familyId,
            childId: nil,
            categoryId: casaFolder.id,
            title: title,
            fileName: fileName,
            mimeType: mime,
            fileSize: Int64(data.count),
            storagePath: storagePath,
            downloadURL: nil,
            notes: notesTag,
            createdBy: uid.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        doc.localPath = localRelPath
        doc.syncState = .pendingUpsert
        modelContext.insert(doc)
        try? modelContext.save()

        DocumentTextExtractionCoordinator.shared.enqueueExtraction(
            for: doc,
            updatedBy: uid,
            modelContext: modelContext
        )
        SyncCenter.shared.enqueueDocumentUpsert(
            documentId: doc.id,
            familyId: familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        Task.detached {
            do {
                let ref = Storage.storage().reference(withPath: storagePath)
                let metadata = StorageMetadata()
                metadata.contentType = "application/octet-stream"
                metadata.customMetadata = [
                    "kb_encrypted": "1",
                    "kb_alg": "AES-GCM",
                    "kb_orig_mime": mime,
                    "kb_orig_name": fileName,
                ]
                _ = try await ref.putDataAsync(encrypted, metadata: metadata)
                let downloadURL = try await ref.downloadURL().absoluteString
                await MainActor.run {
                    doc.downloadURL = downloadURL
                    doc.syncState = .synced
                    doc.updatedAt = Date()
                    doc.updatedBy = uid
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    doc.syncState = .error
                    doc.lastSyncError = error.localizedDescription
                    try? modelContext.save()
                }
            }
        }
        return doc
    }

    func delete(_ doc: KBDocument, modelContext: ModelContext) {
        let path = doc.storagePath
        let local = doc.localPath
        if let lp = local, !lp.isEmpty {
            DocumentLocalCache.deleteFile(localPath: lp)
        }
        doc.localPath = nil
        SyncCenter.shared.enqueueDocumentDelete(
            documentId: doc.id,
            familyId: doc.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        if !path.isEmpty {
            Task.detached {
                try? await Storage.storage().reference(withPath: path).delete()
            }
        }
    }

    func deleteAllForHomeItem(homeItemId: String, familyId: String, modelContext: ModelContext) {
        for d in fetchHomeItemAttachments(homeItemId: homeItemId, familyId: familyId, modelContext: modelContext) {
            delete(d, modelContext: modelContext)
        }
    }

    func deleteAllForHousePayment(paymentId: String, familyId: String, modelContext: ModelContext) {
        for d in fetchHousePaymentAttachments(paymentId: paymentId, familyId: familyId, modelContext: modelContext) {
            delete(d, modelContext: modelContext)
        }
    }

    func fetchHomeItemAttachments(homeItemId: String, familyId: String, modelContext: ModelContext) -> [KBDocument] {
        let fid = familyId
        let desc = FetchDescriptor<KBDocument>(
            predicate: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(desc)) ?? []
        return all.filter { HomeItemAttachmentTag.matches($0, homeItemId: homeItemId) }
    }

    func fetchHousePaymentAttachments(paymentId: String, familyId: String, modelContext: ModelContext) -> [KBDocument] {
        let fid = familyId
        let desc = FetchDescriptor<KBDocument>(
            predicate: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(desc)) ?? []
        return all.filter { HousePaymentAttachmentTag.matches($0, paymentId: paymentId) }
    }

    func open(
        doc: KBDocument,
        modelContext: ModelContext,
        onURL: @escaping (URL) -> Void,
        onError: @escaping (String) -> Void,
        onKeyMissing: @escaping () -> Void
    ) {
        TreatmentAttachmentService.shared.open(
            doc: doc,
            modelContext: modelContext,
            onURL: onURL,
            onError: onError,
            onKeyMissing: onKeyMissing
        )
    }

    func downloadRemoteAttachment(
        docId: String,
        familyId: String,
        storagePath: String,
        fileName: String,
        notes: String? = nil,
        modelContext: ModelContext
    ) async {
        await TreatmentAttachmentService.shared.downloadRemoteAttachment(
            docId: docId,
            familyId: familyId,
            storagePath: storagePath,
            fileName: fileName,
            notes: notes,
            modelContext: modelContext
        )
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "doc", "docx": return "application/msword"
        case "xls", "xlsx": return "application/vnd.ms-excel"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - UI allegati elemento Casa

struct HomeItemAttachmentsSection: View {
    let homeItemId: String
    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query private var attachments: [KBDocument]

    @State private var isUploading = false
    @State private var showSourcePicker = false
    @State private var showImporter = false
    @State private var showGallery = false
    @State private var showCamera = false
    @State private var showKidBoxPicker = false
    @State private var previewURL: URL?
    @State private var showKeyAlert = false
    @State private var showStorageUpgrade = false
    @State private var errorText: String?

    private let tint = Color(hex: "#FF6B00") ?? .orange
    private let service = HomeAttachmentService.shared

    init(homeItemId: String, familyId: String) {
        self.homeItemId = homeItemId
        self.familyId = familyId
        let fid = familyId
        _attachments = Query(
            filter: #Predicate<KBDocument> {
                $0.familyId == fid && $0.isDeleted == false
            },
            sort: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
    }

    private var rows: [KBDocument] {
        attachments.filter { HomeItemAttachmentTag.matches($0, homeItemId: homeItemId) }
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
                        checkUploadAllowed(modelContext: modelContext, familyId: familyId, showUpgrade: $showStorageUpgrade) {
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
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if rows.isEmpty {
                Text("Nessun allegato")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows, id: \.id) { attachmentRow($0) }
                }
            }
            Text("Visibili anche in Documenti › Casa")
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
                tint: tint,
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
                },
                onKidBoxDocument: {
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showKidBoxPicker = true }
                }
            )
        }
        .sheet(isPresented: $showKidBoxPicker) {
            KidBoxDocumentPickerSheet(familyId: familyId, accentTint: tint) { url in
                emitUpload(urls: [url])
            }
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if let urls = try? result.get() { emitUpload(urls: urls) }
        }
        .sheet(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) {
            if let url = previewURL {
                QuickLookPreview(urls: [url], initialIndex: 0)
            }
        }
        .alert("Chiave mancante", isPresented: $showKeyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Chiave di crittografia non trovata. Verifica le impostazioni famiglia.")
        }
        .onReceive(KBEventBus.shared.stream) { (event: KBAppEvent) in
            if case .homeItemAttachmentPending(_, let hid, _) = event, hid == homeItemId {
                isUploading = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isUploading = false }
            }
        }
        .storageUpgradeSheet($showStorageUpgrade)
    }

    private func emitUpload(urls: [URL]) {
        isUploading = true
        KBEventBus.shared.emit(KBAppEvent.homeItemAttachmentPending(urls: urls, homeItemId: homeItemId, familyId: familyId))
    }

    private func saveImageToTemp(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: url)
            return url
        } catch { return nil }
    }

    @ViewBuilder
    private func attachmentRow(_ doc: KBDocument) -> some View {
        HStack(spacing: 10) {
            garageThumbOrIcon(doc)
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(sizeLabel(doc.fileSize)).font(.caption2).foregroundStyle(.secondary)
                    if doc.syncState == .pendingUpsert {
                        Image(systemName: "arrow.up.circle").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    errorText = nil
                    service.open(
                        doc: doc,
                        modelContext: modelContext,
                        onURL: { previewURL = $0 },
                        onError: { errorText = $0 },
                        onKeyMissing: { showKeyAlert = true }
                    )
                } label: {
                    Image(systemName: "eye.fill").foregroundStyle(tint).font(.subheadline)
                }
                .buttonStyle(.plain)
                Button {
                    service.delete(doc, modelContext: modelContext)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red).font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(KBTheme.inputBackground(colorScheme)))
    }

    @ViewBuilder
    private func garageThumbOrIcon(_ doc: KBDocument) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12))
                .frame(width: 44, height: 44)
            if doc.mimeType.contains("image"),
               let ui = decryptedThumbnailUIImage(doc: doc) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: mimeIcon(doc.mimeType))
                    .foregroundStyle(tint)
                    .font(.subheadline)
            }
        }
    }

    private func decryptedThumbnailUIImage(doc: KBDocument) -> UIImage? {
        guard let lp = doc.localPath, !lp.isEmpty,
              DocumentLocalCache.exists(localPath: lp) != nil else { return nil }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        guard let cipher = try? DocumentLocalCache.readEncrypted(localPath: lp),
              let plain = try? DocumentCryptoService.decryptStoredKBDocumentPayload(
                cipher,
                storagePath: doc.storagePath,
                notes: doc.notes,
                familyId: doc.familyId,
                userId: uid
              ) else { return nil }
        return UIImage(data: plain)
    }

    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf") { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        return "paperclip"
    }

    private func sizeLabel(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

// MARK: - UI allegati scadenza & pagamento

struct HousePaymentAttachmentsSection: View {
    let paymentId: String
    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query private var attachments: [KBDocument]

    @State private var isUploading = false
    @State private var showSourcePicker = false
    @State private var showImporter = false
    @State private var showGallery = false
    @State private var showCamera = false
    @State private var showKidBoxPicker = false
    @State private var previewURL: URL?
    @State private var showKeyAlert = false
    @State private var showStorageUpgrade = false
    @State private var errorText: String?

    private let tint = Color(hex: "#FF6B00") ?? .orange
    private let service = HomeAttachmentService.shared

    init(paymentId: String, familyId: String) {
        self.paymentId = paymentId
        self.familyId = familyId
        let fid = familyId
        _attachments = Query(
            filter: #Predicate<KBDocument> {
                $0.familyId == fid && $0.isDeleted == false
            },
            sort: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
    }

    private var rows: [KBDocument] {
        attachments.filter { HousePaymentAttachmentTag.matches($0, paymentId: paymentId) }
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
                        checkUploadAllowed(modelContext: modelContext, familyId: familyId, showUpgrade: $showStorageUpgrade) {
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
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if rows.isEmpty {
                Text("Nessun allegato")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows, id: \.id) { row in
                        housePaymentAttachmentRow(row)
                    }
                }
            }
            Text("Visibili anche in Documenti › Casa")
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
                tint: tint,
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
                },
                onKidBoxDocument: {
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showKidBoxPicker = true }
                }
            )
        }
        .sheet(isPresented: $showKidBoxPicker) {
            KidBoxDocumentPickerSheet(familyId: familyId, accentTint: tint) { url in
                emitUpload(urls: [url])
            }
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if let urls = try? result.get() { emitUpload(urls: urls) }
        }
        .sheet(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) {
            if let url = previewURL {
                QuickLookPreview(urls: [url], initialIndex: 0)
            }
        }
        .alert("Chiave mancante", isPresented: $showKeyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Chiave di crittografia non trovata. Verifica le impostazioni famiglia.")
        }
        .onReceive(KBEventBus.shared.stream) { (event: KBAppEvent) in
            if case .housePaymentAttachmentPending(_, let pid, _) = event, pid == paymentId {
                isUploading = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isUploading = false }
            }
        }
        .storageUpgradeSheet($showStorageUpgrade)
    }

    private func emitUpload(urls: [URL]) {
        isUploading = true
        KBEventBus.shared.emit(KBAppEvent.housePaymentAttachmentPending(urls: urls, paymentId: paymentId, familyId: familyId))
    }

    private func saveImageToTemp(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do { try data.write(to: url); return url } catch { return nil }
    }

    @ViewBuilder
    private func housePaymentAttachmentRow(_ doc: KBDocument) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.12))
                    .frame(width: 44, height: 44)
                if doc.mimeType.contains("image"),
                   let ui = decryptedThumb(doc) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: doc.mimeType.contains("pdf") ? "doc.fill" : "paperclip")
                        .foregroundStyle(tint)
                        .font(.subheadline)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title).font(.subheadline).lineLimit(1)
                Text(sizeLabel(doc.fileSize)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    errorText = nil
                    service.open(
                        doc: doc,
                        modelContext: modelContext,
                        onURL: { previewURL = $0 },
                        onError: { errorText = $0 },
                        onKeyMissing: { showKeyAlert = true }
                    )
                } label: {
                    Image(systemName: "eye.fill").foregroundStyle(tint).font(.subheadline)
                }
                .buttonStyle(.plain)
                Button {
                    service.delete(doc, modelContext: modelContext)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red).font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(KBTheme.inputBackground(colorScheme)))
    }

    private func decryptedThumb(_ doc: KBDocument) -> UIImage? {
        guard let lp = doc.localPath, !lp.isEmpty,
              DocumentLocalCache.exists(localPath: lp) != nil else { return nil }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        guard let cipher = try? DocumentLocalCache.readEncrypted(localPath: lp),
              let plain = try? DocumentCryptoService.decryptStoredKBDocumentPayload(
                cipher,
                storagePath: doc.storagePath,
                notes: doc.notes,
                familyId: doc.familyId,
                userId: uid
              ) else { return nil }
        return UIImage(data: plain)
    }

    private func sizeLabel(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
