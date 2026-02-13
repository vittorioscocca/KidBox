//
//  DocumentFolderView.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UniformTypeIdentifiers
import UIKit
import Combine
import PhotosUI

struct DocumentFolderView: View {
    
    enum LayoutMode: String, CaseIterable, Identifiable {
        case grid = "Grid"
        case list = "Lista"
        var id: String { rawValue }
    }
    
    struct FolderNav: Hashable, Identifiable {
        let id: String
        let title: String
    }
    
    struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }
    
    // MARK: - Env
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Input
    let familyId: String
    let folderId: String?
    let folderTitle: String
    
    // MARK: - VM
    @StateObject var viewModel: DocumentFolderViewModel
    
    // MARK: - UI State
    @State var showNewFolderAlert = false
    @State var newFolderName: String = ""
    @State private var showDeleteSelectedConfirm = false
    
    // Importer
    @State var showImporter = false
    
    // Camera
    @State var showCamera = false
    @State var cameraImage: UIImage?
    
    // Nav
    @State var navSelection: FolderNav?
    
    // Child scope
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    var activeChildId: String? { families.first?.children.first?.id }
    
    // MARK: - Init
    init(familyId: String, folderId: String?, folderTitle: String) {
        self.familyId = familyId
        self.folderId = folderId
        self.folderTitle = folderTitle
        _viewModel = StateObject(wrappedValue: DocumentFolderViewModel(familyId: familyId, folderId: folderId))
    }
    
    // MARK: - Bindings helpers
    
    var previewItemBinding: Binding<IdentifiableURL?> {
        Binding<IdentifiableURL?>(
            get: {
                guard let url = viewModel.previewURL else { return nil }
                return IdentifiableURL(url: url)
            },
            set: { newValue in
                if newValue == nil { viewModel.previewURL = nil }
            }
        )
    }
    
    var renameAlertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.folderToRename != nil || viewModel.docToRename != nil },
            set: { isOn in
                if !isOn {
                    viewModel.folderToRename = nil
                    viewModel.docToRename = nil
                    viewModel.renameText = ""
                }
            }
        )
    }
    
    // MARK: - Body
    
    var body: some View {
        baseContent
            .modifier(applyCommonModifiers())
    }
    
    // MARK: - Base content
    
    private var baseContent: some View {
        VStack(spacing: 0) {
            
            if let error = viewModel.errorText {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 10)
            }
            
            header
            
            if viewModel.folders.isEmpty && viewModel.docs.isEmpty {
                emptyState
            } else {
                content
            }
        }
    }
    
    // MARK: - UI pieces
    
    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $viewModel.layout) {
                ForEach(LayoutMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            
            Spacer()
            
            Text("\(viewModel.folders.count) • \(viewModel.docs.count)")
                .font(.caption).bold()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
    
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Vuoto qui dentro")
                .font(.headline)
            Text("Premi + per creare cartelle o caricare documenti.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var content: some View {
        Group {
            switch viewModel.layout {
            case .grid:
                gridContent
            case .list:
                listContent
            }
        }
    }
    
    // MARK: - GRID
    
    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12),
                          GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                
                // Folders
                ForEach(viewModel.folders) { f in
                    let item = DocumentFolderViewModel.SelectionItem.folder(f.id)
                    
                    Button {
                        if viewModel.isSelecting {
                            viewModel.toggleSelection(item)
                        } else {
                            navSelection = FolderNav(id: f.id, title: f.title)
                        }
                    } label: {
                        FolderGridCard(
                            title: f.title,
                            isSelecting: viewModel.isSelecting,
                            isSelected: viewModel.selectedItems.contains(.folder(f.id))
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !viewModel.isSelecting {
                            folderContextMenu(f)
                        }
                    }
                }
                
                // Docs
                ForEach(viewModel.docs) { doc in
                    let item = DocumentFolderViewModel.SelectionItem.doc(doc.id)
                    
                    DocumentGridCard(
                        doc: doc,
                        isSelecting: viewModel.isSelecting,
                        isSelected: viewModel.selectedItems.contains(.doc(doc.id)),
                        onTap: {
                            if viewModel.isSelecting {
                                viewModel.toggleSelection(item)
                            } else {
                                viewModel.open(doc)
                            }
                        },
                        onRename: {
                            guard !viewModel.isSelecting else { return }
                            viewModel.docToRename = doc
                            viewModel.renameText = doc.title
                        },
                        onDelete: {
                            guard !viewModel.isSelecting else { return }
                            viewModel.deleteDocument(doc)
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    private func applyCommonModifiers() -> some ViewModifier {
        CommonModifiers(view: self)
    }
    
    private struct CommonModifiers: ViewModifier {
        let view: DocumentFolderView
        @EnvironmentObject private var coordinator: AppCoordinator
        
        private var previewItemBinding: Binding<IdentifiableURL?> {
            Binding<IdentifiableURL?>(
                get: {
                    guard let url = view.viewModel.previewURL else { return nil }
                    return IdentifiableURL(url: url)
                },
                set: { newValue in
                    if newValue == nil { view.viewModel.previewURL = nil }
                }
            )
        }
        
        func body(content: Content) -> some View {
            content
                .navigationTitle(view.folderTitle)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    do {
                        let baseDir = try DocumentLocalCache.baseDir()
                        try FileManager.default.removeItem(at: baseDir)
                        print("🗑️ Cache cleaned")
                    } catch {
                        print("⚠️ Cache cleanup failed: \(error)")
                    }
                    
                    view.viewModel.bind(modelContext: view.modelContext)
                    view.viewModel.startObservingChanges()
                    view.viewModel.reload()
                    
                    if let docId = coordinator.pendingOpenDocumentId {
                        coordinator.pendingOpenDocumentId = nil
                        view.viewModel.openIfPresent(docId: docId)
                    }
                }
                .toolbar { view.topToolbar }
                .alert("Nuova cartella", isPresented: view.$showNewFolderAlert) {
                    view.newFolderAlertContent
                } message: {
                    Text("Crea una cartella dentro \(view.folderTitle).")
                }
                .alert("Rinomina", isPresented: view.renameAlertIsPresented) {
                    view.renameAlertContent
                } message: {
                    Text("Inserisci il nuovo nome.")
                }
                .alert(
                    "Eliminare \(view.viewModel.selectedItems.count) elementi?",
                    isPresented: view.$showDeleteSelectedConfirm
                ) {
                    Button("Annulla", role: .cancel) { }
                    Button("Elimina", role: .destructive) {
                        Task { @MainActor in
                            await view.viewModel.deleteSelectedItems()
                        }
                    }
                }message: {
                    Text("Questa azione eliminerà cartelle e documenti selezionati in locale e in remoto su tutti i dispositivi.")
                }
                .sheet(item: previewItemBinding) { item in
                    QuickLookPreview(urls: [item.url], initialIndex: 0)
                }
                .sheet(isPresented: view.$showCamera) {
                    view.cameraSheet
                }
                .photosPicker(
                    isPresented: view.$viewModel.showPhotoLibrary,
                    selection: view.$viewModel.photoItems,
                    maxSelectionCount: 0,
                    matching: .images
                )
                .onChange(of: view.viewModel.photoItems) { _, items in
                    guard !items.isEmpty else { return }
                    Task { @MainActor in
                        await view.viewModel.handlePhotoLibrarySelection(items)
                    }
                }
                .overlay {
                    ZStack {
                        view.uploadingOverlay
                        view.downloadingOverlay
                    }
                }
                .navigationDestination(item: view.$navSelection) { item in
                    DocumentFolderView(
                        familyId: view.familyId,
                        folderId: item.id,
                        folderTitle: item.title
                    )
                    .id(item.id)
                }
                .fileImporter(
                    isPresented: view.$showImporter,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
                ) { result in
                    Task { await view.viewModel.handleImport(result, activeChildId: view.activeChildId) }
                }
        }
    }
    
    // MARK: - LIST
    
    private var listContent: some View {
        List {
            
            // Folders
            ForEach(viewModel.folders) { f in
                let item = DocumentFolderViewModel.SelectionItem.folder(f.id)
                
                Button {
                    if viewModel.isSelecting {
                        viewModel.toggleSelection(item)
                    } else {
                        navSelection = FolderNav(id: f.id, title: f.title)
                    }
                } label: {
                    HStack(spacing: 12) {
                        if viewModel.isSelecting {
                            SelectionBadge(isSelected: viewModel.isSelected(item))
                                .frame(width: 28, height: 28)          // ✅ spazio fisso
                        }
                        
                        FolderRow(title: f.title)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    if !viewModel.isSelecting { folderSwipeActions(f) }
                }
            }
            
            // Docs
            ForEach(viewModel.docs) { doc in
                let item = DocumentFolderViewModel.SelectionItem.doc(doc.id)
                
                Button {
                    if viewModel.isSelecting {
                        viewModel.toggleSelection(item)
                    } else {
                        viewModel.open(doc)
                    }
                } label: {
                    HStack(spacing: 12) {
                        if viewModel.isSelecting {
                            SelectionBadge(isSelected: viewModel.isSelected(item))
                                .frame(width: 28, height: 28)          // ✅ spazio fisso
                        }
                        
                        DocumentRow(doc: doc)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    if !viewModel.isSelecting { docSwipeActions(doc) }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Menus / actions builders
    @ViewBuilder
    private func folderContextMenu(_ f: KBDocumentCategory) -> some View {
        Button {
            viewModel.folderToRename = f
            viewModel.renameText = f.title
        } label: {
            Label("Rinomina", systemImage: "pencil")
        }
        
        Button(role: .destructive) {
            viewModel.deleteFolderCascade(f)
        } label: {
            Label("Elimina cartella", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private func folderSwipeActions(_ f: KBDocumentCategory) -> some View {
        Button {
            viewModel.folderToRename = f
            viewModel.renameText = f.title
        } label: {
            Label("Rinomina", systemImage: "pencil")
        }
        .tint(.blue)
        
        Button(role: .destructive) {
            viewModel.deleteFolderCascade(f)
        } label: {
            Label("Elimina", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private func docSwipeActions(_ doc: KBDocument) -> some View {
        Button {
            viewModel.docToRename = doc
            viewModel.renameText = doc.title
        } label: {
            Label("Rinomina", systemImage: "pencil")
        }
        .tint(.blue)
        
        Button(role: .destructive) {
            viewModel.deleteDocument(doc)
        } label: {
            Label("Elimina", systemImage: "trash")
        }
    }
    
    // MARK: - Upload camera
    @MainActor
    private func uploadCameraImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            viewModel.errorText = "Impossibile convertire la foto."
            return
        }
        
        let filename = "Foto_\(Int(Date().timeIntervalSince1970)).jpg"
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tmpURL, options: .atomic)
            
            viewModel.isUploading = true
            viewModel.uploadTotal = 1
            viewModel.uploadDone = 0
            viewModel.uploadFailures = 0
            viewModel.uploadCurrentName = filename
            
            let ok = await viewModel.uploadSingleFileFromURL(
                tmpURL,
                forcedMime: "image/jpeg",
                forcedTitle: filename.replacingOccurrences(of: ".jpg", with: "")
            )
            
            viewModel.uploadDone = 1
            viewModel.uploadFailures = ok ? 0 : 1
            viewModel.isUploading = false
            viewModel.uploadCurrentName = ""
            
            try? FileManager.default.removeItem(at: tmpURL)
            viewModel.reload()
            
        } catch {
            viewModel.isUploading = false
            viewModel.uploadCurrentName = ""
            viewModel.errorText = error.localizedDescription
        }
    }
    
    // MARK: - Camera Picker
    private struct CameraPicker: UIViewControllerRepresentable {
        @Binding var image: UIImage?
        
        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.delegate = context.coordinator
            return picker
        }
        
        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
        
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        
        final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
            let parent: CameraPicker
            init(_ parent: CameraPicker) { self.parent = parent }
            
            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                picker.dismiss(animated: true)
            }
            
            func imagePickerController(_ picker: UIImagePickerController,
                                       didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
                if let img = info[.originalImage] as? UIImage {
                    parent.image = img
                }
                picker.dismiss(animated: true)
            }
        }
    }
}

// MARK: - Modifiers split (compiler-friendly)

private extension DocumentFolderView {
    
    // Toolbar
    @ToolbarContentBuilder
    var topToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            
            // ✅ Seleziona / Annulla
            Button {
                if viewModel.isSelecting {
                    viewModel.exitSelectionMode()
                } else {
                    viewModel.enterSelectionMode()
                }
            } label: {
                Text(viewModel.isSelecting ? "Annulla" : "Seleziona")
            }
            
            // ✅ Elimina selezionati
            if viewModel.isSelecting && !viewModel.selectedItems.isEmpty {
                Button(role: .destructive) {
                    showDeleteSelectedConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Elimina selezionati")
            }
            
            // ✅ Sort button fuori dal menu
            Button {
                viewModel.toggleNameSort()
            } label: {
                Image(systemName: viewModel.nameSortOrder == .asc
                      ? "arrow.up.arrow.down.circle"
                      : "arrow.up.arrow.down.circle.fill")
            }
            .accessibilityLabel(viewModel.nameSortOrder == .asc ? "Ordina nome A-Z" : "Ordina nome Z-A")
            
            // ✅ Menu +
            Menu {
                Button { showNewFolderAlert = true } label: {
                    Label("Nuova cartella", systemImage: "folder.badge.plus")
                }
                
                Button {
                    viewModel.errorText = nil
                    showImporter = true
                } label: {
                    Label("Carica documento", systemImage: "doc.badge.plus")
                }
                
                Button { showCamera = true } label: {
                    Label("Fotocamera", systemImage: "camera")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                
                Button { viewModel.showPhotoLibrary = true } label: {
                    Label("Libreria foto", systemImage: "photo.on.rectangle")
                }
                
            } label: {
                Image(systemName: "plus")
            }
            .disabled(viewModel.isUploading || viewModel.isSelecting)
        }
    }
    
    // Alerts
    @ViewBuilder
    var newFolderAlertContent: some View {
        TextField("Nome", text: $newFolderName)
        Button("Annulla", role: .cancel) { newFolderName = "" }
        Button("Crea") {
            viewModel.createFolder(name: newFolderName)
            newFolderName = ""
        }
    }
    
    @ViewBuilder
    var renameAlertContent: some View {
        TextField("Nome", text: $viewModel.renameText)
        
        Button("Annulla", role: .cancel) {
            viewModel.folderToRename = nil
            viewModel.docToRename = nil
            viewModel.renameText = ""
        }
        
        Button("Salva") {
            if let f = viewModel.folderToRename {
                viewModel.renameFolder(f, newName: viewModel.renameText)
            } else if let d = viewModel.docToRename {
                viewModel.renameDocument(d, newName: viewModel.renameText)
            }
            viewModel.folderToRename = nil
            viewModel.docToRename = nil
            viewModel.renameText = ""
        }
    }
    
    // Camera sheet
    var cameraSheet: some View {
        CameraPicker(image: $cameraImage)
            .ignoresSafeArea()
            .onDisappear {
                guard let img = cameraImage else { return }
                Task { await uploadCameraImage(img) }
            }
    }
    
    // Upload overlay
    @ViewBuilder
    var uploadingOverlay: some View {
        if viewModel.isUploading {
            ZStack {
                Color.black.opacity(0.10).ignoresSafeArea()
                
                VStack(spacing: 10) {
                    ProgressView()
                    
                    if viewModel.uploadTotal > 0 {
                        Text("\(viewModel.uploadDone)/\(viewModel.uploadTotal) caricati")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if !viewModel.uploadCurrentName.isEmpty {
                            Text(viewModel.uploadCurrentName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Caricamento documento…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
    
    // Download overlay
    @ViewBuilder
    var downloadingOverlay: some View {
        if viewModel.isDownloading {
            ZStack {
                Color.black.opacity(0.10).ignoresSafeArea()
                
                VStack(spacing: 10) {
                    
                    if viewModel.downloadProgress > 0 {
                        ProgressView(value: viewModel.downloadProgress)
                            .frame(width: 220)
                        Text("\(Int(viewModel.downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                    
                    Text("Scaricamento…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if !viewModel.downloadCurrentName.isEmpty {
                        Text(viewModel.downloadCurrentName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .transition(.opacity)
        }
    }
}
