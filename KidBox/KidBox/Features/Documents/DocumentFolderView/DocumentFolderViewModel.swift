//
//  DocumentFolderViewModel.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import Foundation
import SwiftUI
import Combine
import SwiftData
import UniformTypeIdentifiers
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
internal import os

@MainActor
final class DocumentFolderViewModel: ObservableObject {
    
    // MARK: - Input
    let familyId: String
    let folderId: String?
    
    private var cancellables = Set<AnyCancellable>()
    private var isObserving = false
    
    // MARK: - State (published)
    @Published var folders: [KBDocumentCategory] = []
    @Published var docs: [KBDocument] = []
    @Published var layout: DocumentFolderView.LayoutMode = .grid
    
    @Published var isUploading: Bool = false
    
    // MARK: - Download state (preview)
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0        // 0...1
    @Published var downloadCurrentName: String = ""
    @Published var errorText: String?
    
    @Published var uploadTotal: Int = 0
    @Published var uploadDone: Int = 0
    @Published var uploadCurrentName: String = ""
    @Published var uploadFailures: Int = 0
    
    @Published var isDeleting: Bool = false
    
    // rename
    @Published var folderToRename: KBDocumentCategory?
    @Published var docToRename: KBDocument?
    @Published var renameText: String = ""
    
    @Published var showKeyMissingAlert = false
    @Published var keyMissingAction: (() -> Void)?
    
    // preview
    @Published var previewURL: URL?
    
    // Photo Library
    @Published var showPhotoLibrary = false
    @Published var photoItems: [PhotosPickerItem] = []
    
    // MARK: - Services
    private let deleteService = DocumentDeleteService()
    private let categoryRemoteStore = DocumentCategoryRemoteStore()
    private let storageService = DocumentStorageService()
    
    // MARK: - SwiftData
    private var modelContext: ModelContext?
    
    enum NameSortOrder {
        case asc
        case desc
        mutating func toggle() { self = (self == .asc) ? .desc : .asc }
    }
    
    @Published var nameSortOrder: NameSortOrder = .asc
    
    enum SelectionItem: Hashable, Identifiable {
        case folder(String)
        case doc(String)
        
        var id: String {
            switch self {
            case .folder(let id): return "f:\(id)"
            case .doc(let id): return "d:\(id)"
            }
        }
    }
    
    @Published var isSelecting: Bool = false
    @Published var selectedItems: Set<SelectionItem> = []
    
    // MARK: - Init
    init(familyId: String, folderId: String?) {
        self.familyId = familyId
        self.folderId = folderId
        KBLog.data.debug("DocumentFolderVM init familyId=\(familyId, privacy: .public) folderId=\((folderId ?? "nil"), privacy: .public)")
    }
    
    func bind(modelContext: ModelContext) {
        self.modelContext = modelContext
        KBLog.data.debug("DocumentFolderVM bind modelContext set")
    }
    
    // MARK: - Sorting
    
    private func applyNameSort() {
        let isAsc = (nameSortOrder == .asc)
        
        folders.sort { a, b in
            let la = a.title.localizedCaseInsensitiveCompare(b.title)
            return isAsc ? (la == .orderedAscending) : (la == .orderedDescending)
        }
        
        docs.sort { a, b in
            let la = a.title.localizedCaseInsensitiveCompare(b.title)
            return isAsc ? (la == .orderedAscending) : (la == .orderedDescending)
        }
    }
    
    func reload() {
        guard let modelContext else { return }
        do {
            folders = try fetchFolders(modelContext: modelContext)
            docs = try fetchDocs(modelContext: modelContext)
            applyNameSort()
            KBLog.data.debug("DocumentFolderVM reload ok folders=\(self.folders.count) docs=\(self.docs.count)")
        } catch {
            errorText = error.localizedDescription
            KBLog.data.error("DocumentFolderVM reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func toggleNameSort() {
        nameSortOrder.toggle()
        applyNameSort()
        KBLog.data.debug("DocumentFolderVM toggleNameSort -> \(self.nameSortOrder == .asc ? "asc" : "desc", privacy: .public)")
    }
    
    // MARK: - Selection mode
    
    func enterSelectionMode() {
        isSelecting = true
        selectedItems.removeAll()
        KBLog.data.debug("DocumentFolderVM enterSelectionMode")
    }
    
    func exitSelectionMode() {
        isSelecting = false
        selectedItems.removeAll()
        KBLog.data.debug("DocumentFolderVM exitSelectionMode")
    }
    
    func toggleSelection(_ item: SelectionItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
        KBLog.data.debug("DocumentFolderVM toggleSelection selected=\(self.selectedItems.count)")
    }
    
    func isSelected(_ item: SelectionItem) -> Bool {
        selectedItems.contains(item)
    }
    
    // MARK: - Photo library upload
    func handlePhotoLibrarySelection(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        
        guard let modelContext else { return }
        
        KBLog.data.info("PhotoLibrarySelection start count=\(items.count)")
        
        isUploading = true
        uploadTotal = items.count
        uploadDone = 0
        uploadFailures = 0
        uploadCurrentName = ""
        
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    uploadFailures += 1
                    uploadDone += 1
                    continue
                }
                
                let filename = "Foto_\(Int(Date().timeIntervalSince1970)).jpg"
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: tmpURL, options: .atomic)
                
                uploadCurrentName = filename
                
                let ok = await uploadSingleFileFromURL(
                    tmpURL,
                    forcedMime: "image/jpeg",
                    forcedTitle: filename.replacingOccurrences(of: ".jpg", with: "")
                )
                
                uploadDone += 1
                if !ok { uploadFailures += 1 }
                
                try? FileManager.default.removeItem(at: tmpURL)
            } catch {
                uploadFailures += 1
                uploadDone += 1
                KBLog.data.error("PhotoLibrarySelection: error=\(error.localizedDescription)")
            }
        }
        
        isUploading = false
        uploadCurrentName = ""
        photoItems = []
        reload()
        
        // ✅ AGGIUNGI: Flush per sincronizzare i documenti a Firestore
        KBLog.data.info("PhotoLibrarySelection: flushing outbox")
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        KBLog.data.info("PhotoLibrarySelection done ok=\(self.uploadTotal - self.uploadFailures) fail=\(self.uploadFailures)")
    }
    
    // MARK: - Bulk delete
    
    func deleteSelectedItems() async {
        guard let modelContext else { return }
        guard !isDeleting else { return }
        isDeleting = true
        errorText = nil
        
        KBLog.data.info("deleteSelectedItems start count=\(self.selectedItems.count)")
        
        defer {
            isDeleting = false
            selectedItems.removeAll()
            isSelecting = false
            reload()
            KBLog.data.info("deleteSelectedItems end")
        }
        
        do {
            let fid = familyId
            let allCats = try modelContext.fetch(
                FetchDescriptor<KBDocumentCategory>(
                    predicate: #Predicate<KBDocumentCategory> { c in
                        c.familyId == fid && c.isDeleted == false
                    }
                )
            )
            
            let allDocs = try modelContext.fetch(
                FetchDescriptor<KBDocument>(
                    predicate: #Predicate<KBDocument> { d in
                        d.familyId == fid && d.isDeleted == false
                    }
                )
            )
            
            let catsById = Dictionary(uniqueKeysWithValues: allCats.map { ($0.id, $0) })
            let docsById = Dictionary(uniqueKeysWithValues: allDocs.map { ($0.id, $0) })
            
            let selectedFolderIds: [String] = selectedItems.compactMap { item in
                switch item {
                case .folder(let id): return id
                default: return nil
                }
            }
            
            let selectedDocIds: [String] = selectedItems.compactMap { item in
                switch item {
                case .doc(let id): return id
                default: return nil
                }
            }
            
            let folderIdsCoveredByCascade: Set<String> = {
                var covered = Set<String>()
                for fidSel in selectedFolderIds {
                    if let root = catsById[fidSel] {
                        let subtree = computeFolderSubtree(root: root, allCategories: allCats)
                        for f in subtree { covered.insert(f.id) }
                    }
                }
                return covered
            }()
            
            for folderId in selectedFolderIds {
                guard let folder = catsById[folderId] else { continue }
                try await deleteFolderCascadeCore(folder, allCats: allCats, allDocs: allDocs)
            }
            
            for docId in selectedDocIds {
                guard let doc = docsById[docId] else { continue }
                let parentFolder = (doc.categoryId ?? "")
                if folderIdsCoveredByCascade.contains(parentFolder) {
                    continue
                }
                try await deleteDocumentCore(doc)
            }
            
        } catch {
            errorText = error.localizedDescription
            KBLog.data.error("deleteSelectedItems failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func deleteDocumentCore(_ doc: KBDocument) async throws {
        guard let modelContext else { return }
        
        if doc.syncState != .synced {
            purgeOutboxForDocs([doc.id])
            modelContext.delete(doc)
            try modelContext.save()
            return
        }
        
        try await deleteService.deleteDocumentHard(familyId: familyId, doc: doc)
        purgeOutboxForDocs([doc.id])
        
        modelContext.delete(doc)
        try modelContext.save()
    }
    
    private func deleteFolderCascadeCore(
        _ folder: KBDocumentCategory,
        allCats: [KBDocumentCategory],
        allDocs: [KBDocument]
    ) async throws {
        guard let modelContext else { return }
        
        let subtree = computeFolderSubtree(root: folder, allCategories: allCats) // deep->root
        let subtreeIds = Set(subtree.map(\.id))
        
        let docsInSubtree = allDocs.filter { d in
            subtreeIds.contains(d.categoryId ?? "")
        }
        
        if folder.syncState != .synced {
            Task.detached { [storageService] in
                for d in docsInSubtree { try? await storageService.delete(path: d.storagePath) }
            }
            
            purgeOutboxForFoldersAndDocs(folderIds: subtree.map(\.id), docs: docsInSubtree)
            
            for d in docsInSubtree { modelContext.delete(d) }
            for f in subtree { modelContext.delete(f) }
            try modelContext.save()
            return
        }
        
        for d in docsInSubtree where d.syncState == .synced {
            do {
                try await deleteService.deleteDocumentHard(familyId: familyId, doc: d)
            } catch {
                d.syncState = .error
                d.lastSyncError = error.localizedDescription
                try? modelContext.save()
            }
        }
        
        for f in subtree where f.syncState == .synced {
            do {
                try await categoryRemoteStore.delete(familyId: familyId, categoryId: f.id)
            } catch {
                f.syncState = .error
                f.lastSyncError = error.localizedDescription
                try? modelContext.save()
            }
        }
        
        purgeOutboxForFoldersAndDocs(folderIds: subtree.map(\.id), docs: docsInSubtree)
        
        for d in docsInSubtree { modelContext.delete(d) }
        for f in subtree { modelContext.delete(f) }
        try modelContext.save()
    }
    
    // MARK: - Realtime observation
    
    func startObservingChanges() {
        guard !isObserving else { return }
        isObserving = true
        
        KBLog.data.debug("startObservingChanges attach familyId=\(self.familyId, privacy: .public)")
        
        SyncCenter.shared.docsChanged
            .filter { [weak self] fid in fid == self?.familyId }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Download overlay
    
    private func endDownloadingWithMinimumDelay(start: Date) async {
        let minVisible: TimeInterval = 0.35
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minVisible {
            try? await Task.sleep(nanoseconds: UInt64((minVisible - elapsed) * 1_000_000_000))
        }
        isDownloading = false
        downloadProgress = 0
        downloadCurrentName = ""
    }
    
    func uploadSingleFileFromURL(
        _ url: URL,
        forcedMime: String? = nil,
        forcedTitle: String? = nil
    ) async -> Bool {
        
        guard let modelContext else { return false }
        
        do {
            let okScope = url.startAccessingSecurityScopedResource()
            defer { if okScope { url.stopAccessingSecurityScopedResource() } }
            
            let data = try Data(contentsOf: url)
            if data.isEmpty { return false }
            
            let fileName = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            let mime = forcedMime ?? (mimeType(forExtension: ext) ?? "application/octet-stream")
            let size = Int64(data.count)
            let title = forcedTitle ?? url.deletingPathExtension().lastPathComponent
            
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            let documentId = UUID().uuidString
            let storagePath = "families/\(familyId)/documents/\(documentId)/\(fileName).kbenc"
            
            // 1️⃣ Salva PLAINTEXT in cache locale
            let localRelPath = try DocumentLocalCache.write(
                familyId: familyId,
                docId: documentId,
                fileName: fileName,
                data: data
            )
            KBLog.data.info("uploadSingleFileFromURL: saved plaintext to cache docId=\(documentId)")
            
            // 2️⃣ Crea documento locale
            let local = KBDocument(
                id: documentId,
                familyId: familyId,
                childId: nil,
                categoryId: folderId,
                title: title,
                fileName: fileName,
                mimeType: mime,
                fileSize: size,
                storagePath: storagePath,
                downloadURL: nil,
                updatedBy: uid,
                createdAt: now,
                updatedAt: now,
                isDeleted: false
            )
            
            local.localPath = localRelPath
            local.syncState = .pendingUpsert
            local.lastSyncError = nil
            
            modelContext.insert(local)
            try modelContext.save()
            KBLog.data.info("uploadSingleFileFromURL: created local document docId=\(documentId)")
            
            // ✅ AGGIUNGI: Enqueue per sincronizzazione Firestore
            SyncCenter.shared.enqueueDocumentUpsert(
                documentId: local.id,
                familyId: familyId,
                modelContext: modelContext
            )
            KBLog.data.info("uploadSingleFileFromURL: enqueued for sync docId=\(documentId)")
            
            // 3️⃣ Cifra e upload a Storage
            do {
                let plaintext = data
                let encryptedData = try DocumentCryptoService.encrypt(plaintext, familyId: familyId, userId: Auth.auth().currentUser?.uid ?? "local")
                KBLog.data.info("uploadSingleFileFromURL: encrypted docId=\(documentId) bytes=\(plaintext.count)->\(encryptedData.count)")
                
                let (_, downloadURL) = try await storageService.upload(
                    familyId: familyId,
                    docId: documentId,
                    fileName: fileName,
                    originalMimeType: mime,
                    encryptedData: encryptedData
                )
                KBLog.data.info("uploadSingleFileFromURL: uploaded to storage docId=\(documentId)")
                
                // 4️⃣ Aggiorna documento (mark synced)
                local.downloadURL = downloadURL
                local.syncState = .synced
                local.lastSyncError = nil
                local.updatedAt = Date()
                local.updatedBy = uid
                try modelContext.save()
                KBLog.data.info("uploadSingleFileFromURL: marked synced docId=\(documentId)")
                
                return true
                
            } catch {
                KBLog.data.error("uploadSingleFileFromURL: storage/encrypt failed docId=\(documentId) error=\(error.localizedDescription)")
                local.syncState = .error
                local.lastSyncError = error.localizedDescription
                try? modelContext.save()
                return false
            }
            
        } catch {
            KBLog.data.error("uploadSingleFileFromURL: failed error=\(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Fetch
    
    private func fetchFolders(modelContext: ModelContext) throws -> [KBDocumentCategory] {
        let fid = familyId
        
        if let pid = folderId {
            let desc = FetchDescriptor<KBDocumentCategory>(
                predicate: #Predicate { c in
                    c.familyId == fid &&
                    c.parentId == pid &&
                    c.isDeleted == false
                },
                sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
            )
            return try modelContext.fetch(desc)
        } else {
            let descNil = FetchDescriptor<KBDocumentCategory>(
                predicate: #Predicate { c in
                    c.familyId == fid &&
                    c.parentId == nil &&
                    c.isDeleted == false
                }
            )
            let descEmpty = FetchDescriptor<KBDocumentCategory>(
                predicate: #Predicate { c in
                    c.familyId == fid &&
                    c.parentId == "" &&
                    c.isDeleted == false
                }
            )
            
            let a = try modelContext.fetch(descNil)
            let b = try modelContext.fetch(descEmpty)
            
            var map: [String: KBDocumentCategory] = [:]
            for x in a { map[x.id] = x }
            for x in b { map[x.id] = x }
            
            return map.values.sorted { $0.sortOrder < $1.sortOrder }
        }
    }
    
    private func fetchDocs(modelContext: ModelContext) throws -> [KBDocument] {
        let fid = familyId
        
        if let pid = folderId {
            let desc = FetchDescriptor<KBDocument>(
                predicate: #Predicate { d in
                    d.familyId == fid &&
                    d.categoryId == pid &&
                    d.isDeleted == false
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext.fetch(desc)
        } else {
            let descNil = FetchDescriptor<KBDocument>(
                predicate: #Predicate { d in
                    d.familyId == fid &&
                    d.categoryId == nil &&
                    d.isDeleted == false
                }
            )
            let descEmpty = FetchDescriptor<KBDocument>(
                predicate: #Predicate { d in
                    d.familyId == fid &&
                    d.categoryId == "" &&
                    d.isDeleted == false
                }
            )
            
            let a = try modelContext.fetch(descNil)
            let b = try modelContext.fetch(descEmpty)
            
            var map: [String: KBDocument] = [:]
            for x in a { map[x.id] = x }
            for x in b { map[x.id] = x }
            
            return map.values.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
    
    // MARK: - Create folder
    
    func createFolder(name raw: String) {
        guard let modelContext else { return }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let nextOrder = (folders.map(\.sortOrder).max() ?? 0) + 1
        
        let folder = KBDocumentCategory(
            familyId: familyId,
            title: name,
            sortOrder: nextOrder,
            parentId: folderId,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        
        folder.syncState = .pendingUpsert
        folder.lastSyncError = nil
        
        do {
            modelContext.insert(folder)
            try modelContext.save()
            
            SyncCenter.shared.enqueueDocumentCategoryUpsert(
                categoryId: folder.id,
                familyId: familyId,
                modelContext: modelContext
            )
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            
            let dto = RemoteDocumentCategoryDTO(
                id: folder.id,
                familyId: familyId,
                title: folder.title,
                sortOrder: folder.sortOrder,
                parentId: folder.parentId,
                isDeleted: false,
                updatedAt: now,
                updatedBy: uid
            )
            
            Task.detached(priority: .userInitiated) {
                do {
                    let remote = await DocumentCategoryRemoteStore()
                    try await remote.upsert(dto: dto)
                } catch {
                    // best effort: ignore, outbox will retry
                }
            }
            
            reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    // MARK: - Rename
    
    func renameFolder(_ folder: KBDocumentCategory, newName raw: String) {
        guard let modelContext else { return }
        let newName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        
        folder.title = newName
        folder.updatedAt = Date()
        folder.updatedBy = Auth.auth().currentUser?.uid ?? "local"
        folder.syncState = .pendingUpsert
        folder.lastSyncError = nil
        
        do {
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentCategoryUpsert(
                categoryId: folder.id,
                familyId: familyId,
                modelContext: modelContext
            )
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    func renameDocument(_ doc: KBDocument, newName raw: String) {
        guard let modelContext else { return }
        let newName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        
        doc.title = newName
        doc.updatedAt = Date()
        doc.updatedBy = Auth.auth().currentUser?.uid ?? "local"
        doc.syncState = .pendingUpsert
        doc.lastSyncError = nil
        
        do {
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentUpsert(
                documentId: doc.id,
                familyId: familyId,
                modelContext: modelContext
            )
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    // MARK: - Open / Preview
    
    func open(_ doc: KBDocument) {
        guard let modelContext else { return }
        errorText = nil
        
        Task { @MainActor in
            let userId = Auth.auth().currentUser?.uid ?? "local"
            
            // ✅ Controlla se la chiave esiste
            if FamilyKeychainStore.loadFamilyKey(familyId: doc.familyId, userId: userId) == nil {
                KBLog.data.warning("Master key not found for familyId=\(doc.familyId) userId=\(userId)")
                showKeyMissingAlert = true
                return
            }
            
            if let localPath = doc.localPath, !localPath.isEmpty,
               let _ = DocumentLocalCache.exists(localPath: localPath) {
                do {
                    let plaintext = try DocumentLocalCache.readEncrypted(localPath: localPath)
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(doc.id)_\(doc.fileName)")
                    try plaintext.write(to: tempURL, options: .atomic)
                    previewURL = tempURL
                    return
                } catch {
                    if isCryptoKeyError(error) {
                        showKeyMissingAlert = true
                    } else {
                        errorText = "Apertura file fallita: \(error.localizedDescription)"
                    }
                    return
                }
            }
            
            do {
                let plaintext = try await downloadToLocalWithProgress(doc: doc, modelContext: modelContext)
                previewURL = plaintext
            } catch {
                isDownloading = false
                downloadProgress = 0
                downloadCurrentName = ""
                if isCryptoKeyError(error) {
                    showKeyMissingAlert = true
                } else {
                    errorText = "Apertura file fallita: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func isCryptoKeyError(_ error: Error) -> Bool {
        // CryptoKit error 3 = authenticationFailure, tipicamente chiave mancante/sbagliata
        let desc = error.localizedDescription.lowercased()
        if desc.contains("cryptokit") { return true }
        let nsErr = error as NSError
        if nsErr.domain == "CryptoKit.CryptoKitError" { return true }
        return false
    }
    
    private func downloadToLocalWithProgress(doc: KBDocument, modelContext: ModelContext) async throws -> URL {
        let start = Date()
        
        guard !doc.storagePath.isEmpty else {
            throw NSError(domain: "KidBox", code: -2, userInfo: [NSLocalizedDescriptionKey: "storagePath vuoto"])
        }
        
        isDownloading = true
        downloadProgress = 0
        downloadCurrentName = doc.fileName.isEmpty ? doc.title : doc.fileName
        
        let ext = (doc.fileName as NSString).pathExtension
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "tmp" : ext)
        
        let ref = Storage.storage().reference(withPath: doc.storagePath)
        let task = ref.write(toFile: tmp)
        
        do {
            let tmpURL: URL = try await withCheckedThrowingContinuation { cont in
                var done = false
                
                task.observe(.progress) { [weak self] snap in
                    guard let self else { return }
                    if let p = snap.progress, p.totalUnitCount > 0 {
                        let val = Double(p.completedUnitCount) / Double(p.totalUnitCount)
                        Task { @MainActor in
                            self.downloadProgress = val
                        }
                    }
                }
                
                task.observe(.success) { _ in
                    guard !done else { return }
                    done = true
                    cont.resume(returning: tmp)
                }
                
                task.observe(.failure) { snap in
                    guard !done else { return }
                    done = true
                    cont.resume(throwing: snap.error ?? NSError(domain: "KidBox", code: -3,
                                                                userInfo: [NSLocalizedDescriptionKey: "Download fallito"]))
                }
            }
            
            let encrypted = try Data(contentsOf: tmpURL)
            let decrypted = try DocumentCryptoService.decrypt(encrypted, familyId: doc.familyId, userId: Auth.auth().currentUser?.uid ?? "local")
            
            let rel = try DocumentLocalCache.write(
                familyId: doc.familyId,
                docId: doc.id,
                fileName: doc.fileName.isEmpty ? doc.id : doc.fileName,
                data: decrypted
            )
            
            doc.localPath = rel
            try modelContext.save()
            
            try? FileManager.default.removeItem(at: tmpURL)
            await endDownloadingWithMinimumDelay(start: start)
            return try DocumentLocalCache.resolve(localPath: rel)
            
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            await endDownloadingWithMinimumDelay(start: start)
            throw error
        }
    }
    
    // MARK: - Delete doc
    
    func deleteDocument(_ doc: KBDocument) {
        guard let modelContext else { return }
        guard !isDeleting else { return }
        isDeleting = true
        errorText = nil
        
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                if doc.syncState != .synced {
                    purgeOutboxForDocs([doc.id])
                    modelContext.delete(doc)
                    try modelContext.save()
                    reload()
                    return
                }
                
                try await deleteService.deleteDocumentHard(familyId: familyId, doc: doc)
                purgeOutboxForDocs([doc.id])
                
                modelContext.delete(doc)
                try modelContext.save()
                reload()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
    
    private func purgeOutboxForDocs(_ docIds: [String]) {
        guard let modelContext else { return }
        do {
            let fid = familyId
            let etDoc = SyncEntityType.document.rawValue
            
            for did in docIds {
                let ops = try modelContext.fetch(
                    FetchDescriptor<KBSyncOp>(predicate: #Predicate {
                        $0.familyId == fid && $0.entityTypeRaw == etDoc && $0.entityId == did
                    })
                )
                for op in ops { modelContext.delete(op) }
            }
            
            try modelContext.save()
        } catch {
            KBLog.data.debug("purgeOutboxForDocs failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Folder cascade delete
    
    func deleteFolderCascade(_ folder: KBDocumentCategory) {
        guard let modelContext else { return }
        guard !isDeleting else { return }
        isDeleting = true
        errorText = nil
        
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                let fid = familyId
                
                let allCats = try modelContext.fetch(
                    FetchDescriptor<KBDocumentCategory>(
                        predicate: #Predicate<KBDocumentCategory> { c in
                            c.familyId == fid && c.isDeleted == false
                        }
                    )
                )
                
                let allDocs = try modelContext.fetch(
                    FetchDescriptor<KBDocument>(
                        predicate: #Predicate<KBDocument> { d in
                            d.familyId == fid && d.isDeleted == false
                        }
                    )
                )
                
                let subtree = computeFolderSubtree(root: folder, allCategories: allCats) // deep->root
                let subtreeIds = Set(subtree.map(\.id))
                
                let docsInSubtree = allDocs.filter { d in
                    subtreeIds.contains(d.categoryId ?? "")
                }
                
                if folder.syncState != .synced {
                    hardDeleteFolderLocalOnly(subtree: subtree, docs: docsInSubtree)
                    reload()
                    return
                }
                
                try await hardDeleteFolderRemoteThenLocal(subtree: subtree, docs: docsInSubtree)
                reload()
                
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
    
    private func computeFolderSubtree(root: KBDocumentCategory, allCategories: [KBDocumentCategory]) -> [KBDocumentCategory] {
        var result: [KBDocumentCategory] = []
        var queue: [KBDocumentCategory] = [root]
        
        while let current = queue.first {
            queue.removeFirst()
            result.append(current)
            let children = allCategories.filter { $0.parentId == current.id }
            queue.append(contentsOf: children)
        }
        
        return result.reversed() // deep -> root
    }
    
    private func hardDeleteFolderLocalOnly(subtree: [KBDocumentCategory], docs: [KBDocument]) {
        guard let modelContext else { return }
        
        Task.detached { [storageService] in
            for d in docs { try? await storageService.delete(path: d.storagePath) }
        }
        
        purgeOutboxForFoldersAndDocs(folderIds: subtree.map(\.id), docs: docs)
        
        do {
            for d in docs { modelContext.delete(d) }
            for f in subtree { modelContext.delete(f) }
            try modelContext.save()
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    private func hardDeleteFolderRemoteThenLocal(subtree: [KBDocumentCategory], docs: [KBDocument]) async throws {
        guard let modelContext else { return }
        
        for d in docs where d.syncState == .synced {
            do {
                try await deleteService.deleteDocumentHard(familyId: familyId, doc: d)
            } catch {
                d.syncState = .error
                d.lastSyncError = error.localizedDescription
                try? modelContext.save()
            }
        }
        
        for f in subtree where f.syncState == .synced {
            do {
                try await categoryRemoteStore.delete(familyId: familyId, categoryId: f.id)
            } catch {
                f.syncState = .error
                f.lastSyncError = error.localizedDescription
                try? modelContext.save()
            }
        }
        
        purgeOutboxForFoldersAndDocs(folderIds: subtree.map(\.id), docs: docs)
        
        for d in docs { modelContext.delete(d) }
        for f in subtree { modelContext.delete(f) }
        try modelContext.save()
    }
    
    private func purgeOutboxForFoldersAndDocs(folderIds: [String], docs: [KBDocument]) {
        guard let modelContext else { return }
        do {
            let fid = familyId
            
            let etCat = SyncEntityType.documentCategory.rawValue
            for folderId in folderIds {
                let cid = folderId
                let ops = try modelContext.fetch(
                    FetchDescriptor<KBSyncOp>(predicate: #Predicate {
                        $0.familyId == fid && $0.entityTypeRaw == etCat && $0.entityId == cid
                    })
                )
                for op in ops { modelContext.delete(op) }
            }
            
            let etDoc = SyncEntityType.document.rawValue
            for d in docs {
                let did = d.id
                let ops = try modelContext.fetch(
                    FetchDescriptor<KBSyncOp>(predicate: #Predicate {
                        $0.familyId == fid && $0.entityTypeRaw == etDoc && $0.entityId == did
                    })
                )
                for op in ops { modelContext.delete(op) }
            }
            
            try modelContext.save()
        } catch {
            KBLog.data.debug("purgeOutboxForFoldersAndDocs failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Multi upload (TaskGroup + progress)
    
    actor AsyncSemaphore {
        private var value: Int
        private var waiters: [CheckedContinuation<Void, Never>] = []
        init(_ value: Int) { self.value = value }
        
        func wait() async {
            if value > 0 { value -= 1; return }
            await withCheckedContinuation { cont in waiters.append(cont) }
        }
        
        func signal() {
            if !waiters.isEmpty {
                let cont = waiters.removeFirst()
                cont.resume()
            } else {
                value += 1
            }
        }
    }
    
    func handleImport(_ result: Result<[URL], Error>, activeChildId: String?) async {
        guard modelContext != nil else { return }
        errorText = nil
        
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            
            isUploading = true
            uploadTotal = urls.count
            uploadDone = 0
            uploadFailures = 0
            uploadCurrentName = ""
            
            let semaphore = AsyncSemaphore(3)
            let batch = urls
            
            await withTaskGroup(of: Bool.self) { group in
                for url in batch {
                    group.addTask { [weak self] in
                        guard let self else { return false }
                        await semaphore.wait()
                        await MainActor.run { self.uploadCurrentName = url.lastPathComponent }
                        let ok = await self.uploadSingleFileConcurrent(url, childId: activeChildId)
                        await MainActor.run {
                            self.uploadDone += 1
                            if !ok { self.uploadFailures += 1 }
                        }
                        await semaphore.signal()
                        return ok
                    }
                }
                for await _ in group { }
            }
            
            isUploading = false
            uploadCurrentName = ""
            if uploadFailures > 0 {
                errorText = "Caricamento completato con \(uploadFailures) errori."
            }
            
            reload()
            
            guard let modelContext else { return }
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            
        } catch {
            isUploading = false
            uploadCurrentName = ""
            errorText = error.localizedDescription
        }
    }
    
    func openIfPresent(docId: String) {
        if let d = docs.first(where: { $0.id == docId }) {
            open(d)
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
                reload()
                if let d = docs.first(where: { $0.id == docId }) {
                    open(d)
                }
            }
        }
    }
    
    func uploadSingleFileConcurrent(_ url: URL, childId: String?) async -> Bool {
        guard let modelContext else { return false }
        
        do {
            let okScope = url.startAccessingSecurityScopedResource()
            defer { if okScope { url.stopAccessingSecurityScopedResource() } }
            
            let plaintext = try Data(contentsOf: url)
            if plaintext.isEmpty { return false }
            
            let fileName = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            let mime = mimeType(forExtension: ext) ?? "application/octet-stream"
            let size = Int64(plaintext.count)
            let title = url.deletingPathExtension().lastPathComponent
            
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            let documentId = UUID().uuidString
            let storagePath = "families/\(familyId)/documents/\(documentId)/\(fileName).kbenc"
            
            let encryptedData: Data
            do {
                encryptedData = try DocumentCryptoService.encrypt(plaintext, familyId: familyId, userId: Auth.auth().currentUser?.uid ?? "local")
            } catch {
                return false
            }
            
            let localPath: String
            do {
                localPath = try DocumentLocalCache.write(
                    familyId: familyId,
                    docId: documentId,
                    fileName: fileName,
                    data: plaintext
                )
            } catch {
                return false
            }
            
            do {
                let local = KBDocument(
                    id: documentId,
                    familyId: familyId,
                    childId: childId,
                    categoryId: folderId,
                    title: title,
                    fileName: fileName,
                    mimeType: mime,
                    fileSize: size,
                    storagePath: storagePath,
                    downloadURL: nil,
                    updatedBy: uid,
                    createdAt: now,
                    updatedAt: now,
                    isDeleted: false
                )
                local.syncState = .pendingUpsert
                local.lastSyncError = nil
                local.localPath = localPath
                
                modelContext.insert(local)
                try modelContext.save()
                
                SyncCenter.shared.enqueueDocumentUpsert(
                    documentId: local.id,
                    familyId: familyId,
                    modelContext: modelContext
                )
                
            } catch {
                return false
            }
            
            do {
                let (uploadedPath, downloadURL) = try await storageService.upload(
                    familyId: familyId,
                    docId: documentId,
                    fileName: fileName,
                    originalMimeType: mime,
                    encryptedData: encryptedData
                )
                
                do {
                    let did = documentId
                    let desc = FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })
                    if let local = try modelContext.fetch(desc).first {
                        local.downloadURL = downloadURL
                        local.storagePath = uploadedPath
                        local.syncState = .synced
                        local.lastSyncError = nil
                        local.updatedAt = Date()
                        local.updatedBy = uid
                        try modelContext.save()
                    }
                } catch { }
                
                return true
                
            } catch {
                do {
                    let did = documentId
                    let desc = FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })
                    if let local = try modelContext.fetch(desc).first {
                        local.syncState = .error
                        local.lastSyncError = error.localizedDescription
                        try? modelContext.save()
                    }
                } catch { }
                return false
            }
            
        } catch {
            return false
        }
    }
    
    private func mimeType(forExtension ext: String) -> String? {
        if ext.isEmpty { return nil }
        if let ut = UTType(filenameExtension: ext),
           let m = ut.preferredMIMEType { return m }
        switch ext {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        default: return nil
        }
    }
}
