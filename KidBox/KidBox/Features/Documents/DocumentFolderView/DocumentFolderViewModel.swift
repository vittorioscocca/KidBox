//
//  DocumentFolderViewModel.swift
//  KidBox
//
//  Created by vscocca on 09/02/26. Updated 21/02/26.
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
    
    /// Layout persistito in UserDefaults — uguale per tutte le istanze della view
    @AppStorage("documentsLayoutMode") private var _layoutRaw: String = DocumentFolderView.LayoutMode.grid.rawValue
    var layout: DocumentFolderView.LayoutMode {
        get { DocumentFolderView.LayoutMode(rawValue: _layoutRaw) ?? .grid }
        set { _layoutRaw = newValue.rawValue }
    }
    
    @Published var isUploading: Bool = false
    
    // MARK: - Download state (preview)
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
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
    
    // MARK: - Move / Copy / Duplicate state
    /// Documento in attesa di operazione (Sposta o Copia)
    @Published var docPendingMove: KBDocument?
    @Published var docPendingCopy: KBDocument?
    /// Cartella in attesa di operazione (Sposta o Copia)
    @Published var folderPendingMove: KBDocumentCategory?
    @Published var folderPendingCopy: KBDocumentCategory?
    /// Mostra il FolderPickerSheet
    @Published var showFolderPicker = false
    /// Tipo di operazione corrente
    enum PendingOperation { case moveDoc, copyDoc, moveFolder, copyFolder }
    @Published var pendingOperation: PendingOperation?
    
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
        folders.sort {
            let r = $0.title.localizedCaseInsensitiveCompare($1.title)
            return isAsc ? (r == .orderedAscending) : (r == .orderedDescending)
        }
        docs.sort {
            let r = $0.title.localizedCaseInsensitiveCompare($1.title)
            return isAsc ? (r == .orderedAscending) : (r == .orderedDescending)
        }
    }
    
    func reload() {
        guard let modelContext else { return }
        do {
            folders = try fetchFolders(modelContext: modelContext)
            docs    = try fetchDocs(modelContext: modelContext)
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
    }
    
    // MARK: - Selection mode
    
    func enterSelectionMode() {
        isSelecting = true
        selectedItems.removeAll()
    }
    
    func exitSelectionMode() {
        isSelecting = false
        selectedItems.removeAll()
    }
    
    func toggleSelection(_ item: SelectionItem) {
        if selectedItems.contains(item) { selectedItems.remove(item) }
        else { selectedItems.insert(item) }
    }
    
    func isSelected(_ item: SelectionItem) -> Bool { selectedItems.contains(item) }
    
    // MARK: - Photo library upload
    func handlePhotoLibrarySelection(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, let modelContext else { return }
        
        isUploading = true; uploadTotal = items.count; uploadDone = 0
        uploadFailures = 0; uploadCurrentName = ""
        
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    uploadFailures += 1; uploadDone += 1; continue
                }
                let filename = "Foto_\(Int(Date().timeIntervalSince1970)).jpg"
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: tmpURL, options: .atomic)
                uploadCurrentName = filename
                let ok = await uploadSingleFileFromURL(tmpURL, forcedMime: "image/jpeg",
                                                       forcedTitle: filename.replacingOccurrences(of: ".jpg", with: ""))
                uploadDone += 1; if !ok { uploadFailures += 1 }
                try? FileManager.default.removeItem(at: tmpURL)
            } catch { uploadFailures += 1; uploadDone += 1 }
        }
        
        isUploading = false; uploadCurrentName = ""; photoItems = []; reload()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    // MARK: - Bulk delete
    
    func deleteSelectedItems() async {
        guard let modelContext else { return }
        guard !isDeleting else { return }
        isDeleting = true; errorText = nil
        
        defer { isDeleting = false; selectedItems.removeAll(); isSelecting = false; reload() }
        
        do {
            let fid = familyId
            let allCats = try modelContext.fetch(
                FetchDescriptor<KBDocumentCategory>(predicate: #Predicate<KBDocumentCategory> { c in
                    c.familyId == fid && c.isDeleted == false })
            )
            let allDocs = try modelContext.fetch(
                FetchDescriptor<KBDocument>(predicate: #Predicate<KBDocument> { d in
                    d.familyId == fid && d.isDeleted == false })
            )
            
            let catsById = Dictionary(uniqueKeysWithValues: allCats.map { ($0.id, $0) })
            let docsById = Dictionary(uniqueKeysWithValues: allDocs.map { ($0.id, $0) })
            
            let selectedFolderIds = selectedItems.compactMap { if case .folder(let id) = $0 { return id } else { return nil } }
            let selectedDocIds    = selectedItems.compactMap { if case .doc(let id) = $0    { return id } else { return nil } }
            
            let folderIdsCoveredByCascade: Set<String> = {
                var covered = Set<String>()
                for fid in selectedFolderIds {
                    if let root = catsById[fid] {
                        computeFolderSubtree(root: root, allCategories: allCats).forEach { covered.insert($0.id) }
                    }
                }
                return covered
            }()
            
            for fid in selectedFolderIds {
                guard let folder = catsById[fid] else { continue }
                try await deleteFolderCascadeCore(folder, allCats: allCats, allDocs: allDocs)
            }
            for docId in selectedDocIds {
                guard let doc = docsById[docId] else { continue }
                if folderIdsCoveredByCascade.contains(doc.categoryId ?? "") { continue }
                try await deleteDocumentCore(doc)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    private func deleteDocumentCore(_ doc: KBDocument) async throws {
        guard let modelContext else { return }
        if doc.syncState != .synced {
            purgeOutboxForDocs([doc.id]); modelContext.delete(doc); try modelContext.save(); return
        }
        try await deleteService.deleteDocumentHard(familyId: familyId, doc: doc)
        purgeOutboxForDocs([doc.id]); modelContext.delete(doc); try modelContext.save()
    }
    
    private func deleteFolderCascadeCore(_ folder: KBDocumentCategory,
                                         allCats: [KBDocumentCategory],
                                         allDocs: [KBDocument]) async throws {
        guard let modelContext else { return }
        let subtree = computeFolderSubtree(root: folder, allCategories: allCats)
        let subtreeIds = Set(subtree.map(\.id))
        let docsInSubtree = allDocs.filter { subtreeIds.contains($0.categoryId ?? "") }
        
        if folder.syncState != .synced {
            Task.detached { [storageService] in
                for d in docsInSubtree { try? await storageService.delete(path: d.storagePath) }
            }
            purgeOutboxForFoldersAndDocs(folderIds: subtree.map(\.id), docs: docsInSubtree)
            for d in docsInSubtree { modelContext.delete(d) }
            for f in subtree { modelContext.delete(f) }
            try modelContext.save(); return
        }
        
        for d in docsInSubtree where d.syncState == .synced {
            do { try await deleteService.deleteDocumentHard(familyId: familyId, doc: d) }
            catch { d.syncState = .error; d.lastSyncError = error.localizedDescription; try? modelContext.save() }
        }
        for f in subtree where f.syncState == .synced {
            do { try await categoryRemoteStore.delete(familyId: familyId, categoryId: f.id) }
            catch { f.syncState = .error; f.lastSyncError = error.localizedDescription; try? modelContext.save() }
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
        SyncCenter.shared.docsChanged
            .filter { [weak self] fid in fid == self?.familyId }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }
    
    // MARK: - Download overlay
    
    private func endDownloadingWithMinimumDelay(start: Date) async {
        let minVisible: TimeInterval = 0.35
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minVisible {
            try? await Task.sleep(nanoseconds: UInt64((minVisible - elapsed) * 1_000_000_000))
        }
        isDownloading = false; downloadProgress = 0; downloadCurrentName = ""
    }
    
    // MARK: - ─── MOVE DOCUMENT ───────────────────────────────────────────────
    
    /// Avvia il flusso "Sposta documento": mostra il FolderPicker.
    func beginMoveDocument(_ doc: KBDocument) {
        docPendingMove = doc
        pendingOperation = .moveDoc
        showFolderPicker = true
    }
    
    /// Esegue lo spostamento del documento nella cartella destinazione (nil = root).
    func moveDocument(_ doc: KBDocument, toFolderId destId: String?) {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        doc.categoryId = destId
        doc.updatedAt = now
        doc.updatedBy = uid
        doc.syncState = .pendingUpsert
        doc.lastSyncError = nil
        
        do {
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentUpsert(documentId: doc.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            reload()
            KBLog.data.info("moveDocument ok docId=\(doc.id) destId=\(destId ?? "root")")
            
            // ✅ Scrittura Firestore immediata — non aspetta il SyncCenter
            let dto = RemoteDocumentDTO(
                id: doc.id, familyId: familyId,
                childId: doc.childId, categoryId: destId,
                title: doc.title, fileName: doc.fileName,
                mimeType: doc.mimeType, fileSize: Int(doc.fileSize),
                storagePath: doc.storagePath, downloadURL: doc.downloadURL,
                isDeleted: false, updatedAt: now, updatedBy: uid
            )
            Task.detached(priority: .userInitiated) {
                do {
                    try await DocumentRemoteStore().upsert(dto: dto)
                    await MainActor.run { KBLog.data.info("moveDocument Firestore direct write OK docId=\(doc.id)") }
                } catch {
                    await MainActor.run { KBLog.data.error("moveDocument Firestore direct write failed: \(error.localizedDescription)") }
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    // MARK: - ─── COPY DOCUMENT ───────────────────────────────────────────────
    
    /// Avvia il flusso "Copia documento": mostra il FolderPicker.
    func beginCopyDocument(_ doc: KBDocument) {
        docPendingCopy = doc
        pendingOperation = .copyDoc
        showFolderPicker = true
    }
    
    /// Crea una copia del documento nella cartella destinazione.
    func copyDocument(_ doc: KBDocument, toFolderId destId: String?) {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let newId = UUID().uuidString
        
        let copy = KBDocument(
            id: newId,
            familyId: familyId,
            childId: doc.childId,
            categoryId: destId,
            title: doc.title + " (copia)",
            fileName: doc.fileName,
            mimeType: doc.mimeType,
            fileSize: doc.fileSize,
            localPath: doc.localPath,
            storagePath: doc.storagePath,
            downloadURL: doc.downloadURL,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        copy.syncState = .pendingUpsert
        copy.lastSyncError = nil
        
        do {
            modelContext.insert(copy)
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentUpsert(documentId: copy.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            reload()
            KBLog.data.info("copyDocument ok srcId=\(doc.id) newId=\(newId) destId=\(destId ?? "root")")
            
            // ✅ Scrittura Firestore immediata — garantisce sync sull'altro account
            let dto = RemoteDocumentDTO(
                id: newId, familyId: familyId,
                childId: doc.childId, categoryId: destId,
                title: doc.title + " (copia)", fileName: doc.fileName,
                mimeType: doc.mimeType, fileSize: Int(doc.fileSize),
                storagePath: doc.storagePath, downloadURL: doc.downloadURL,
                isDeleted: false, updatedAt: now, updatedBy: uid
            )
            Task.detached(priority: .userInitiated) {
                do {
                    try await DocumentRemoteStore().upsert(dto: dto)
                    await MainActor.run { KBLog.data.info("copyDocument Firestore direct write OK newId=\(newId)") }
                } catch {
                    await MainActor.run { KBLog.data.error("copyDocument Firestore direct write failed: \(error.localizedDescription)") }
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    // MARK: - ─── DUPLICATE DOCUMENT ─────────────────────────────────────────
    
    /// Duplica il documento nella stessa cartella corrente.
    func duplicateDocument(_ doc: KBDocument) {
        copyDocument(doc, toFolderId: doc.categoryId)
    }
    
    // MARK: - ─── MOVE FOLDER ─────────────────────────────────────────────────
    
    /// Avvia il flusso "Sposta cartella".
    func beginMoveFolder(_ folder: KBDocumentCategory) {
        folderPendingMove = folder
        pendingOperation = .moveFolder
        showFolderPicker = true
    }
    
    /// Esegue lo spostamento della cartella (cambia parentId).
    func moveFolder(_ folder: KBDocumentCategory, toFolderId destId: String?) {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        folder.parentId = destId
        folder.updatedAt = now
        folder.updatedBy = uid
        folder.syncState = .pendingUpsert
        folder.lastSyncError = nil
        
        do {
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentCategoryUpsert(categoryId: folder.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            reload()
            KBLog.data.info("moveFolder ok folderId=\(folder.id) destId=\(destId ?? "root")")
            
            // ✅ Scrittura Firestore immediata
            let dto = RemoteDocumentCategoryDTO(
                id: folder.id, familyId: familyId,
                title: folder.title, sortOrder: folder.sortOrder,
                parentId: destId, isDeleted: false,
                updatedAt: now, updatedBy: uid
            )
            Task.detached(priority: .userInitiated) {
                do {
                    try await DocumentCategoryRemoteStore().upsert(dto: dto)
                    await MainActor.run { KBLog.data.info("moveFolder Firestore direct write OK folderId=\(folder.id)") }
                } catch {
                    await MainActor.run { KBLog.data.error("moveFolder Firestore direct write failed: \(error.localizedDescription)") }
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    // MARK: - ─── COPY FOLDER ─────────────────────────────────────────────────
    
    /// Avvia il flusso "Copia cartella".
    func beginCopyFolder(_ folder: KBDocumentCategory) {
        folderPendingCopy = folder
        pendingOperation = .copyFolder
        showFolderPicker = true
    }
    
    /// Copia la cartella (senza i suoi contenuti) nella destinazione.
    func copyFolder(_ folder: KBDocumentCategory, toFolderId destId: String?) {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let newId = UUID().uuidString
        let nextOrder = (folders.map(\.sortOrder).max() ?? 0) + 1
        
        let copy = KBDocumentCategory(
            id: newId,
            familyId: familyId,
            title: folder.title + " (copia)",
            sortOrder: nextOrder,
            parentId: destId,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        copy.syncState = .pendingUpsert
        copy.lastSyncError = nil
        
        do {
            modelContext.insert(copy)
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentCategoryUpsert(categoryId: copy.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            reload()
            KBLog.data.info("copyFolder ok srcId=\(folder.id) newId=\(newId) destId=\(destId ?? "root")")
            
            // ✅ Scrittura Firestore immediata — garantisce sync sull'altro account
            let dto = RemoteDocumentCategoryDTO(
                id: newId, familyId: familyId,
                title: folder.title + " (copia)", sortOrder: nextOrder,
                parentId: destId, isDeleted: false,
                updatedAt: now, updatedBy: uid
            )
            Task.detached(priority: .userInitiated) {
                do {
                    try await DocumentCategoryRemoteStore().upsert(dto: dto)
                    await MainActor.run { KBLog.data.info("copyFolder Firestore direct write OK newId=\(newId)") }
                } catch {
                    await MainActor.run { KBLog.data.error("copyFolder Firestore direct write failed: \(error.localizedDescription)") }
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    // MARK: - ─── DUPLICATE FOLDER ────────────────────────────────────────────
    
    /// Duplica la cartella nella stessa posizione (stesso padre).
    func duplicateFolder(_ folder: KBDocumentCategory) {
        copyFolder(folder, toFolderId: folder.parentId)
    }
    
    // MARK: - FolderPicker: risolvi operazione pendente
    
    /// Chiamato quando l'utente ha scelto la cartella destinazione nel picker.
    func resolvePendingOperation(destinationId: String?) {
        defer {
            docPendingMove = nil; docPendingCopy = nil
            folderPendingMove = nil; folderPendingCopy = nil
            pendingOperation = nil; showFolderPicker = false
        }
        switch pendingOperation {
        case .moveDoc:
            if let doc = docPendingMove { moveDocument(doc, toFolderId: destinationId) }
        case .copyDoc:
            if let doc = docPendingCopy { copyDocument(doc, toFolderId: destinationId) }
        case .moveFolder:
            if let folder = folderPendingMove { moveFolder(folder, toFolderId: destinationId) }
        case .copyFolder:
            if let folder = folderPendingCopy { copyFolder(folder, toFolderId: destinationId) }
        case nil:
            break
        }
    }
    
    /// ID cartelle da escludere nel FolderPicker (per Sposta cartella).
    func excludedFolderIdsForCurrentOperation() -> Set<String> {
        guard let modelContext else { return [] }
        switch pendingOperation {
        case .moveFolder, .copyFolder:
            let source = folderPendingMove ?? folderPendingCopy
            guard let source else { return [] }
            let fid = familyId
            let all = (try? modelContext.fetch(
                FetchDescriptor<KBDocumentCategory>(predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false })
            )) ?? []
            let subtree = computeFolderSubtree(root: source, allCategories: all)
            return Set(subtree.map(\.id))
        default:
            return []
        }
    }
    
    /// Titolo dinamico del FolderPickerSheet.
    var folderPickerTitle: String {
        switch pendingOperation {
        case .moveDoc:    return "Sposta documento in…"
        case .copyDoc:    return "Copia documento in…"
        case .moveFolder: return "Sposta cartella in…"
        case .copyFolder: return "Copia cartella in…"
        case nil:         return "Scegli cartella"
        }
    }
    
    // MARK: - Upload (single file helper)
    
    func uploadSingleFileFromURL(_ url: URL, forcedMime: String? = nil, forcedTitle: String? = nil) async -> Bool {
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
            
            let localRelPath = try DocumentLocalCache.write(familyId: familyId, docId: documentId, fileName: fileName, data: data)
            
            let local = KBDocument(
                id: documentId, familyId: familyId, childId: nil, categoryId: folderId,
                title: title, fileName: fileName, mimeType: mime, fileSize: size,
                storagePath: storagePath, downloadURL: nil, updatedBy: uid,
                createdAt: now, updatedAt: now, isDeleted: false
            )
            local.localPath = localRelPath; local.syncState = .pendingUpsert; local.lastSyncError = nil
            modelContext.insert(local); try modelContext.save()
            SyncCenter.shared.enqueueDocumentUpsert(documentId: local.id, familyId: familyId, modelContext: modelContext)
            
            do {
                let encryptedData = try DocumentCryptoService.encrypt(data, familyId: familyId, userId: uid)
                let (_, downloadURL) = try await storageService.upload(
                    familyId: familyId, docId: documentId, fileName: fileName,
                    originalMimeType: mime, encryptedData: encryptedData)
                local.downloadURL = downloadURL; local.syncState = .synced; local.lastSyncError = nil
                local.updatedAt = Date(); local.updatedBy = uid; try modelContext.save()
                return true
            } catch {
                local.syncState = .error; local.lastSyncError = error.localizedDescription
                try? modelContext.save(); return false
            }
        } catch { return false }
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
            
            guard let encryptedData = try? DocumentCryptoService.encrypt(plaintext, familyId: familyId, userId: uid) else { return false }
            guard let localPath = try? DocumentLocalCache.write(familyId: familyId, docId: documentId, fileName: fileName, data: plaintext) else { return false }
            
            let local = KBDocument(
                id: documentId, familyId: familyId, childId: childId, categoryId: folderId,
                title: title, fileName: fileName, mimeType: mime, fileSize: size,
                storagePath: storagePath, downloadURL: nil, updatedBy: uid,
                createdAt: now, updatedAt: now, isDeleted: false
            )
            local.syncState = .pendingUpsert; local.lastSyncError = nil; local.localPath = localPath
            modelContext.insert(local); try modelContext.save()
            SyncCenter.shared.enqueueDocumentUpsert(documentId: local.id, familyId: familyId, modelContext: modelContext)
            
            do {
                let (uploadedPath, downloadURL) = try await storageService.upload(
                    familyId: familyId, docId: documentId, fileName: fileName,
                    originalMimeType: mime, encryptedData: encryptedData)
                let did = documentId
                if let l = try? modelContext.fetch(FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })).first {
                    l.downloadURL = downloadURL; l.storagePath = uploadedPath
                    l.syncState = .synced; l.lastSyncError = nil; l.updatedAt = Date(); l.updatedBy = uid
                    try? modelContext.save()
                }
                return true
            } catch {
                let did = documentId
                if let l = try? modelContext.fetch(FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })).first {
                    l.syncState = .error; l.lastSyncError = error.localizedDescription; try? modelContext.save()
                }
                return false
            }
        } catch { return false }
    }
    
    // MARK: - Fetch
    
    private func fetchFolders(modelContext: ModelContext) throws -> [KBDocumentCategory] {
        let fid = familyId
        if let pid = folderId {
            return try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                predicate: #Predicate { $0.familyId == fid && $0.parentId == pid && $0.isDeleted == false },
                sortBy: [SortDescriptor(\.sortOrder)]))
        } else {
            let a = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                predicate: #Predicate { $0.familyId == fid && $0.parentId == nil && $0.isDeleted == false }))
            let b = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                predicate: #Predicate { $0.familyId == fid && $0.parentId == "" && $0.isDeleted == false }))
            var map: [String: KBDocumentCategory] = [:]
            for x in a { map[x.id] = x }; for x in b { map[x.id] = x }
            return map.values.sorted { $0.sortOrder < $1.sortOrder }
        }
    }
    
    private func fetchDocs(modelContext: ModelContext) throws -> [KBDocument] {
        let fid = familyId
        if let pid = folderId {
            return try modelContext.fetch(FetchDescriptor<KBDocument>(
                predicate: #Predicate { $0.familyId == fid && $0.categoryId == pid && $0.isDeleted == false },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        } else {
            let a = try modelContext.fetch(FetchDescriptor<KBDocument>(
                predicate: #Predicate { $0.familyId == fid && $0.categoryId == nil && $0.isDeleted == false }))
            let b = try modelContext.fetch(FetchDescriptor<KBDocument>(
                predicate: #Predicate { $0.familyId == fid && $0.categoryId == "" && $0.isDeleted == false }))
            var map: [String: KBDocument] = [:]
            for x in a { map[x.id] = x }; for x in b { map[x.id] = x }
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
            familyId: familyId, title: name, sortOrder: nextOrder,
            parentId: folderId, updatedBy: uid, createdAt: now, updatedAt: now, isDeleted: false
        )
        folder.syncState = .pendingUpsert; folder.lastSyncError = nil
        
        do {
            modelContext.insert(folder); try modelContext.save()
            SyncCenter.shared.enqueueDocumentCategoryUpsert(categoryId: folder.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            let dto = RemoteDocumentCategoryDTO(
                id: folder.id, familyId: familyId, title: folder.title,
                sortOrder: folder.sortOrder, parentId: folder.parentId,
                isDeleted: false, updatedAt: now, updatedBy: uid)
            Task.detached(priority: .userInitiated) {
                try? await DocumentCategoryRemoteStore().upsert(dto: dto)
            }
            reload()
        } catch { errorText = error.localizedDescription }
    }
    
    // MARK: - Rename
    
    func renameFolder(_ folder: KBDocumentCategory, newName raw: String) {
        guard let modelContext else { return }
        let newName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        folder.title = newName; folder.updatedAt = Date()
        folder.updatedBy = Auth.auth().currentUser?.uid ?? "local"
        folder.syncState = .pendingUpsert; folder.lastSyncError = nil
        do {
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentCategoryUpsert(categoryId: folder.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            reload()
        } catch { errorText = error.localizedDescription }
    }
    
    func renameDocument(_ doc: KBDocument, newName raw: String) {
        guard let modelContext else { return }
        let newName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        doc.title = newName; doc.updatedAt = Date()
        doc.updatedBy = Auth.auth().currentUser?.uid ?? "local"
        doc.syncState = .pendingUpsert; doc.lastSyncError = nil
        do {
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentUpsert(documentId: doc.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            reload()
        } catch { errorText = error.localizedDescription }
    }
    
    // MARK: - Open / Preview
    
    func open(_ doc: KBDocument) {
        guard let modelContext else { return }
        errorText = nil
        Task { @MainActor in
            let userId = Auth.auth().currentUser?.uid ?? "local"
            if FamilyKeychainStore.loadFamilyKey(familyId: doc.familyId, userId: userId) == nil {
                showKeyMissingAlert = true; return
            }
            if let localPath = doc.localPath, !localPath.isEmpty,
               let _ = DocumentLocalCache.exists(localPath: localPath) {
                do {
                    let plaintext = try DocumentLocalCache.readEncrypted(localPath: localPath)
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(doc.id)_\(doc.fileName)")
                    try plaintext.write(to: tempURL, options: .atomic)
                    previewURL = tempURL; return
                } catch {
                    if isCryptoKeyError(error) { showKeyMissingAlert = true }
                    else { errorText = "Apertura file fallita: \(error.localizedDescription)" }
                    return
                }
            }
            do {
                previewURL = try await downloadToLocalWithProgress(doc: doc, modelContext: modelContext)
            } catch {
                isDownloading = false; downloadProgress = 0; downloadCurrentName = ""
                if isCryptoKeyError(error) { showKeyMissingAlert = true }
                else { errorText = "Apertura file fallita: \(error.localizedDescription)" }
            }
        }
    }
    
    func openIfPresent(docId: String) {
        if let d = docs.first(where: { $0.id == docId }) { open(d); return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            reload()
            if let d = docs.first(where: { $0.id == docId }) { open(d) }
        }
    }
    
    private func isCryptoKeyError(_ error: Error) -> Bool {
        let desc = error.localizedDescription.lowercased()
        if desc.contains("cryptokit") { return true }
        return (error as NSError).domain == "CryptoKit.CryptoKitError"
    }
    
    private func downloadToLocalWithProgress(doc: KBDocument, modelContext: ModelContext) async throws -> URL {
        let start = Date()
        guard !doc.storagePath.isEmpty else {
            throw NSError(domain: "KidBox", code: -2, userInfo: [NSLocalizedDescriptionKey: "storagePath vuoto"])
        }
        isDownloading = true; downloadProgress = 0
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
                        Task { @MainActor in self.downloadProgress = val }
                    }
                }
                task.observe(.success) { _ in guard !done else { return }; done = true; cont.resume(returning: tmp) }
                task.observe(.failure) { snap in
                    guard !done else { return }; done = true
                    cont.resume(throwing: snap.error ?? NSError(domain: "KidBox", code: -3,
                                                                userInfo: [NSLocalizedDescriptionKey: "Download fallito"]))
                }
            }
            let encrypted = try Data(contentsOf: tmpURL)
            let decrypted = try DocumentCryptoService.decrypt(encrypted, familyId: doc.familyId, userId: Auth.auth().currentUser?.uid ?? "local")
            let rel = try DocumentLocalCache.write(familyId: doc.familyId, docId: doc.id,
                                                   fileName: doc.fileName.isEmpty ? doc.id : doc.fileName, data: decrypted)
            doc.localPath = rel; try modelContext.save()
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
        isDeleting = true; errorText = nil
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                if doc.syncState != .synced {
                    purgeOutboxForDocs([doc.id]); modelContext.delete(doc); try modelContext.save(); reload(); return
                }
                try await deleteService.deleteDocumentHard(familyId: familyId, doc: doc)
                purgeOutboxForDocs([doc.id]); modelContext.delete(doc); try modelContext.save(); reload()
            } catch { errorText = error.localizedDescription }
        }
    }
    
    private func purgeOutboxForDocs(_ docIds: [String]) {
        guard let modelContext else { return }
        let fid = familyId; let etDoc = SyncEntityType.document.rawValue
        for did in docIds {
            let ops = (try? modelContext.fetch(FetchDescriptor<KBSyncOp>(
                predicate: #Predicate { $0.familyId == fid && $0.entityTypeRaw == etDoc && $0.entityId == did }
            ))) ?? []
            for op in ops { modelContext.delete(op) }
        }
        try? modelContext.save()
    }
    
    // MARK: - Folder cascade delete
    
    func deleteFolderCascade(_ folder: KBDocumentCategory) {
        guard let modelContext else { return }
        guard !isDeleting else { return }
        isDeleting = true; errorText = nil
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                let fid = familyId
                let allCats = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                    predicate: #Predicate<KBDocumentCategory> { c in c.familyId == fid && c.isDeleted == false }))
                let allDocs = try modelContext.fetch(FetchDescriptor<KBDocument>(
                    predicate: #Predicate<KBDocument> { d in d.familyId == fid && d.isDeleted == false }))
                let subtree = computeFolderSubtree(root: folder, allCategories: allCats)
                let subtreeIds = Set(subtree.map(\.id))
                let docsInSubtree = allDocs.filter { subtreeIds.contains($0.categoryId ?? "") }
                if folder.syncState != .synced {
                    hardDeleteFolderLocalOnly(subtree: subtree, docs: docsInSubtree); reload(); return
                }
                try await hardDeleteFolderRemoteThenLocal(subtree: subtree, docs: docsInSubtree); reload()
            } catch { errorText = error.localizedDescription }
        }
    }
    
    func computeFolderSubtree(root: KBDocumentCategory, allCategories: [KBDocumentCategory]) -> [KBDocumentCategory] {
        var result: [KBDocumentCategory] = []
        var queue = [root]
        while let current = queue.first {
            queue.removeFirst(); result.append(current)
            queue.append(contentsOf: allCategories.filter { $0.parentId == current.id })
        }
        return result.reversed()
    }
    
    private func hardDeleteFolderLocalOnly(subtree: [KBDocumentCategory], docs: [KBDocument]) {
        guard let modelContext else { return }
        Task.detached { [storageService] in
            for d in docs { try? await storageService.delete(path: d.storagePath) }
        }
        purgeOutboxForFoldersAndDocs(folderIds: subtree.map(\.id), docs: docs)
        do { for d in docs { modelContext.delete(d) }; for f in subtree { modelContext.delete(f) }; try modelContext.save() }
        catch { errorText = error.localizedDescription }
    }
    
    private func hardDeleteFolderRemoteThenLocal(subtree: [KBDocumentCategory], docs: [KBDocument]) async throws {
        guard let modelContext else { return }
        for d in docs where d.syncState == .synced {
            do { try await deleteService.deleteDocumentHard(familyId: familyId, doc: d) }
            catch { d.syncState = .error; d.lastSyncError = error.localizedDescription; try? modelContext.save() }
        }
        for f in subtree where f.syncState == .synced {
            do { try await categoryRemoteStore.delete(familyId: familyId, categoryId: f.id) }
            catch { f.syncState = .error; f.lastSyncError = error.localizedDescription; try? modelContext.save() }
        }
        purgeOutboxForFoldersAndDocs(folderIds: subtree.map(\.id), docs: docs)
        for d in docs { modelContext.delete(d) }; for f in subtree { modelContext.delete(f) }
        try modelContext.save()
    }
    
    private func purgeOutboxForFoldersAndDocs(folderIds: [String], docs: [KBDocument]) {
        guard let modelContext else { return }
        let fid = familyId; let etCat = SyncEntityType.documentCategory.rawValue
        for cid in folderIds {
            let ops = (try? modelContext.fetch(FetchDescriptor<KBSyncOp>(
                predicate: #Predicate { $0.familyId == fid && $0.entityTypeRaw == etCat && $0.entityId == cid }
            ))) ?? []
            for op in ops { modelContext.delete(op) }
        }
        let etDoc = SyncEntityType.document.rawValue
        for d in docs {
            let did = d.id
            let ops = (try? modelContext.fetch(FetchDescriptor<KBSyncOp>(
                predicate: #Predicate { $0.familyId == fid && $0.entityTypeRaw == etDoc && $0.entityId == did }
            ))) ?? []
            for op in ops { modelContext.delete(op) }
        }
        try? modelContext.save()
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
            if !waiters.isEmpty { waiters.removeFirst().resume() }
            else { value += 1 }
        }
    }
    
    func handleImport(_ result: Result<[URL], Error>, activeChildId: String?) async {
        guard modelContext != nil else { return }
        errorText = nil
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isUploading = true; uploadTotal = urls.count; uploadDone = 0; uploadFailures = 0; uploadCurrentName = ""
            let semaphore = AsyncSemaphore(3)
            await withTaskGroup(of: Bool.self) { group in
                for url in urls {
                    group.addTask { [weak self] in
                        guard let self else { return false }
                        await semaphore.wait()
                        await MainActor.run { self.uploadCurrentName = url.lastPathComponent }
                        let ok = await self.uploadSingleFileConcurrent(url, childId: activeChildId)
                        await MainActor.run { self.uploadDone += 1; if !ok { self.uploadFailures += 1 } }
                        await semaphore.signal(); return ok
                    }
                }
                for await _ in group { }
            }
            isUploading = false; uploadCurrentName = ""
            if uploadFailures > 0 { errorText = "Caricamento completato con \(uploadFailures) errori." }
            reload()
            guard let modelContext else { return }
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
        } catch { isUploading = false; uploadCurrentName = ""; errorText = error.localizedDescription }
    }
    
    // MARK: - MIME
    
    private func mimeType(forExtension ext: String) -> String? {
        if ext.isEmpty { return nil }
        if let ut = UTType(filenameExtension: ext), let m = ut.preferredMIMEType { return m }
        switch ext {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        default: return nil
        }
    }
}

