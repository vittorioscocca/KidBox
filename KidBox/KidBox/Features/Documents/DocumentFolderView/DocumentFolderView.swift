//
//  DocumentFolderView.swift
//  KidBox
//
//  Created by vscocca on 06/02/26. Updated 21/02/26.
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
internal import os

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
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Dynamic theme (same as LoginView / HomeView / ProfileView / ChatView)
    var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    var pillBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.22, green: 0.22, blue: 0.22)
        : Color(.tertiarySystemBackground)
    }
    
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
    
    @ViewBuilder
    var keyMissingAlertButtons: some View {
        Button("Impostazioni") {
            if let url = URL(string: "App-Prefs:root=CASTLE") { UIApplication.shared.open(url) }
        }
        Button("OK", role: .cancel) { }
    }
    
    var keyMissingAlertMessage: Text {
        Text("Abilita iCloud Keychain in Impostazioni > [Il tuo account] > iCloud > Portachiavi, oppure chiedi al proprietario della famiglia di condividere un QR code con la chiave.")
    }
    
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
            get: { guard let url = viewModel.previewURL else { return nil }; return IdentifiableURL(url: url) },
            set: { if $0 == nil { viewModel.previewURL = nil } }
        )
    }
    
    var renameAlertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.folderToRename != nil || viewModel.docToRename != nil },
            set: { isOn in
                if !isOn {
                    viewModel.folderToRename = nil; viewModel.docToRename = nil; viewModel.renameText = ""
                }
            }
        )
    }
    
    // MARK: - Body
    
    var body: some View {
        baseContent.modifier(applyCommonModifiers())
    }
    
    // MARK: - Base content
    
    private var baseContent: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorText {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            
            header
            
            if viewModel.folders.isEmpty && viewModel.docs.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(backgroundColor)
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Segmented picker lista/grid
                Picker("", selection: Binding(
                    get: { viewModel.layout },
                    set: { viewModel.layout = $0 }
                )) {
                    ForEach(LayoutMode.allCases) { m in
                        Image(systemName: m == .grid ? "square.grid.2x2" : "list.bullet")
                            .tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                
                Spacer()
                
                // Contatore
                HStack(spacing: 4) {
                    Image(systemName: "folder").font(.caption2).foregroundStyle(.secondary)
                    Text("\(viewModel.folders.count)").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Image(systemName: "doc").font(.caption2).foregroundStyle(.secondary)
                    Text("\(viewModel.docs.count)").font(.caption.bold()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(pillBackground, in: Capsule())
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Sort bar stile Dropbox
            sortBar
        }
    }
    
    /// Barra di ordinamento orizzontale scrollabile
    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DocumentFolderViewModel.SortMode.allCases) { mode in
                    sortChip(mode)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    @ViewBuilder
    private func sortChip(_ mode: DocumentFolderViewModel.SortMode) -> some View {
        let isActive = viewModel.sortMode == mode
        Button {
            if isActive {
                viewModel.toggleNameSort()
            } else {
                viewModel.sortMode = mode
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.systemImage)
                    .font(.caption2)
                Text(mode.rawValue)
                    .font(.caption.weight(isActive ? .semibold : .regular))
                if isActive {
                    Image(systemName: viewModel.nameSortOrder == .asc ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isActive
                ? Color.accentColor.opacity(0.15)
                : pillBackground,
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isActive ? Color.accentColor.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: viewModel.nameSortOrder)
    }
    
    // MARK: - Empty state
    
    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(pillBackground).frame(width: 72, height: 72)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2).foregroundStyle(.secondary)
            }
            Text("Nessun contenuto").font(.headline)
            Text("Premi + per creare cartelle o caricare documenti.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Content switch
    
    private var content: some View {
        Group {
            switch viewModel.layout {
            case .grid: gridContent
            case .list: listContent
            }
        }
    }
    
    // MARK: - GRID ─────────────────────────────────────────────────────────
    
    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 16
            ) {
                // Folders
                ForEach(viewModel.folders) { f in
                    let item = DocumentFolderViewModel.SelectionItem.folder(f.id)
                    Button {
                        if viewModel.isSelecting { viewModel.toggleSelection(item) }
                        else { navSelection = FolderNav(id: f.id, title: f.title) }
                    } label: {
                        FolderGridCard(
                            title: f.title,
                            updatedAt: f.updatedAt,
                            isSelecting: viewModel.isSelecting,
                            isSelected: viewModel.isSelected(item)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu { if !viewModel.isSelecting { folderContextMenu(f) } }
                }
                
                // Docs
                ForEach(viewModel.docs) { doc in
                    let item = DocumentFolderViewModel.SelectionItem.doc(doc.id)
                    DocumentGridCard(
                        doc: doc,
                        isSelecting: viewModel.isSelecting,
                        isSelected: viewModel.isSelected(item),
                        onTap: {
                            if viewModel.isSelecting { viewModel.toggleSelection(item) }
                            else { viewModel.open(doc) }
                        },
                        onRename: { viewModel.docToRename = doc; viewModel.renameText = doc.title },
                        onDelete: { viewModel.deleteDocument(doc) },
                        onMove:   { viewModel.beginMoveDocument(doc) },
                        onCopy:   { viewModel.beginCopyDocument(doc) },
                        onDuplicate: { viewModel.duplicateDocument(doc) }
                    )
                }
            }
            .padding()
        }
        .background(backgroundColor)
    }
    
    // MARK: - LIST ─────────────────────────────────────────────────────────
    
    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Folders
                ForEach(viewModel.folders) { f in
                    let item = DocumentFolderViewModel.SelectionItem.folder(f.id)
                    Button {
                        if viewModel.isSelecting { viewModel.toggleSelection(item) }
                        else { navSelection = FolderNav(id: f.id, title: f.title) }
                    } label: {
                        HStack(spacing: 14) {
                            if viewModel.isSelecting {
                                SelectionBadge(isSelected: viewModel.isSelected(item))
                                    .frame(width: 24, height: 24)
                            }
                            FolderRow(title: f.title, updatedAt: f.updatedAt)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if !viewModel.isSelecting { folderSwipeActions(f) }
                    }
                    .swipeActions(edge: .leading) {
                        if !viewModel.isSelecting { folderLeadingSwipeActions(f) }
                    }
                    
                }
                
                // Docs
                ForEach(viewModel.docs) { doc in
                    let item = DocumentFolderViewModel.SelectionItem.doc(doc.id)
                    Button {
                        if viewModel.isSelecting { viewModel.toggleSelection(item) }
                        else { viewModel.open(doc) }
                    } label: {
                        HStack(spacing: 14) {
                            if viewModel.isSelecting {
                                SelectionBadge(isSelected: viewModel.isSelected(item))
                                    .frame(width: 24, height: 24)
                            }
                            DocumentRow(doc: doc)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if !viewModel.isSelecting { docSwipeActions(doc) }
                    }
                    .swipeActions(edge: .leading) {
                        if !viewModel.isSelecting { docLeadingSwipeActions(doc) }
                    }
                    
                }
            }
            .padding(.vertical, 4)
        }
        .background(backgroundColor)
    }
    
    // MARK: - Context menus ────────────────────────────────────────────────
    
    @ViewBuilder
    private func folderContextMenu(_ f: KBDocumentCategory) -> some View {
        Button { viewModel.folderToRename = f; viewModel.renameText = f.title } label: {
            Label("Rinomina", systemImage: "pencil")
        }
        Divider()
        Button { viewModel.beginMoveFolder(f) } label: {
            Label("Sposta in…", systemImage: "folder")
        }
        Button { viewModel.beginCopyFolder(f) } label: {
            Label("Copia in…", systemImage: "doc.on.doc")
        }
        Button { viewModel.duplicateFolder(f) } label: {
            Label("Duplica", systemImage: "plus.square.on.square")
        }
        Divider()
        Button(role: .destructive) { viewModel.deleteFolderCascade(f) } label: {
            Label("Elimina cartella", systemImage: "trash")
        }
    }
    
    // MARK: - Swipe actions ────────────────────────────────────────────────
    
    @ViewBuilder
    private func folderSwipeActions(_ f: KBDocumentCategory) -> some View {
        Button(role: .destructive) { viewModel.deleteFolderCascade(f) } label: {
            Label("Elimina", systemImage: "trash")
        }
        Button { viewModel.folderToRename = f; viewModel.renameText = f.title } label: {
            Label("Rinomina", systemImage: "pencil")
        }
        .tint(.blue)
    }
    
    @ViewBuilder
    private func folderLeadingSwipeActions(_ f: KBDocumentCategory) -> some View {
        Button { viewModel.beginMoveFolder(f) } label: {
            Label("Sposta", systemImage: "folder")
        }
        .tint(.indigo)
        Button { viewModel.duplicateFolder(f) } label: {
            Label("Duplica", systemImage: "plus.square.on.square")
        }
        .tint(.teal)
    }
    
    @ViewBuilder
    private func docSwipeActions(_ doc: KBDocument) -> some View {
        Button(role: .destructive) { viewModel.deleteDocument(doc) } label: {
            Label("Elimina", systemImage: "trash")
        }
        Button { viewModel.docToRename = doc; viewModel.renameText = doc.title } label: {
            Label("Rinomina", systemImage: "pencil")
        }
        .tint(.blue)
    }
    
    @ViewBuilder
    private func docLeadingSwipeActions(_ doc: KBDocument) -> some View {
        Button { viewModel.beginMoveDocument(doc) } label: {
            Label("Sposta", systemImage: "folder")
        }
        .tint(.indigo)
        Button { viewModel.duplicateDocument(doc) } label: {
            Label("Duplica", systemImage: "plus.square.on.square")
        }
        .tint(.teal)
    }
    
    // MARK: - Upload camera
    @MainActor
    private func uploadCameraImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            viewModel.errorText = "Impossibile convertire la foto."; return
        }
        let filename = "Foto_\(Int(Date().timeIntervalSince1970)).jpg"
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tmpURL, options: .atomic)
            viewModel.isUploading = true; viewModel.uploadTotal = 1; viewModel.uploadDone = 0
            viewModel.uploadFailures = 0; viewModel.uploadCurrentName = filename
            let ok = await viewModel.uploadSingleFileFromURL(tmpURL, forcedMime: "image/jpeg",
                                                             forcedTitle: filename.replacingOccurrences(of: ".jpg", with: ""))
            viewModel.uploadDone = 1; viewModel.uploadFailures = ok ? 0 : 1
            viewModel.isUploading = false; viewModel.uploadCurrentName = ""
            try? FileManager.default.removeItem(at: tmpURL)
            viewModel.reload()
            if ok { SyncCenter.shared.flushGlobal(modelContext: modelContext) }
        } catch {
            viewModel.isUploading = false; viewModel.uploadCurrentName = ""
            viewModel.errorText = error.localizedDescription
        }
    }
    
    // MARK: - Camera Picker
    private struct CameraPicker: UIViewControllerRepresentable {
        @Binding var image: UIImage?
        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera; picker.cameraCaptureMode = .photo; picker.delegate = context.coordinator
            return picker
        }
        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
            let parent: CameraPicker
            init(_ parent: CameraPicker) { self.parent = parent }
            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
            func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                if let img = info[.originalImage] as? UIImage { parent.image = img }
                picker.dismiss(animated: true)
            }
        }
    }
}

// MARK: - Modifiers split

private extension DocumentFolderView {
    
    @ToolbarContentBuilder
    var topToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            
            // Seleziona / Annulla
            Button {
                if viewModel.isSelecting { viewModel.exitSelectionMode() }
                else { viewModel.enterSelectionMode() }
            } label: {
                Text(viewModel.isSelecting ? "Annulla" : "Seleziona")
            }
            
            // Elimina selezionati
            if viewModel.isSelecting && !viewModel.selectedItems.isEmpty {
                Button(role: .destructive) { showDeleteSelectedConfirm = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Elimina selezionati")
            }
            
            // Menu +
            Menu {
                Button { showNewFolderAlert = true } label: {
                    Label("Nuova cartella", systemImage: "folder.badge.plus")
                }
                Button { viewModel.errorText = nil; showImporter = true } label: {
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
    
    @ViewBuilder
    var newFolderAlertContent: some View {
        TextField("Nome", text: $newFolderName)
        Button("Annulla", role: .cancel) { newFolderName = "" }
        Button("Crea") { viewModel.createFolder(name: newFolderName); newFolderName = "" }
    }
    
    @ViewBuilder
    var renameAlertContent: some View {
        TextField("Nome", text: $viewModel.renameText)
        Button("Annulla", role: .cancel) {
            viewModel.folderToRename = nil; viewModel.docToRename = nil; viewModel.renameText = ""
        }
        Button("Salva") {
            if let f = viewModel.folderToRename { viewModel.renameFolder(f, newName: viewModel.renameText) }
            else if let d = viewModel.docToRename { viewModel.renameDocument(d, newName: viewModel.renameText) }
            viewModel.folderToRename = nil; viewModel.docToRename = nil; viewModel.renameText = ""
        }
    }
    
    var cameraSheet: some View {
        CameraPicker(image: $cameraImage)
            .ignoresSafeArea()
            .onDisappear {
                guard let img = cameraImage else { return }
                Task { await uploadCameraImage(img) }
            }
    }
    
    @ViewBuilder
    var uploadingOverlay: some View {
        if viewModel.isUploading {
            ZStack {
                Color.black.opacity(0.10).ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                    if viewModel.uploadTotal > 0 {
                        Text("\(viewModel.uploadDone)/\(viewModel.uploadTotal) caricati")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !viewModel.uploadCurrentName.isEmpty {
                            Text(viewModel.uploadCurrentName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else {
                        Text("Caricamento documento…").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(16).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
    
    @ViewBuilder
    var downloadingOverlay: some View {
        if viewModel.isDownloading {
            ZStack {
                Color.black.opacity(0.10).ignoresSafeArea()
                VStack(spacing: 10) {
                    if viewModel.downloadProgress > 0 {
                        ProgressView(value: viewModel.downloadProgress).frame(width: 220)
                        Text("\(Int(viewModel.downloadProgress * 100))%").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                    Text("Scaricamento…").font(.subheadline).foregroundStyle(.secondary)
                    if !viewModel.downloadCurrentName.isEmpty {
                        Text(viewModel.downloadCurrentName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(16).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .transition(.opacity)
        }
    }
    
    // MARK: - CommonModifiers
    
    func applyCommonModifiers() -> some ViewModifier { CommonModifiers(view: self) }
    
    private struct CommonModifiers: ViewModifier {
        let view: DocumentFolderView
        @EnvironmentObject private var coordinator: AppCoordinator
        
        private var previewItemBinding: Binding<IdentifiableURL?> {
            Binding<IdentifiableURL?>(
                get: { guard let url = view.viewModel.previewURL else { return nil }; return IdentifiableURL(url: url) },
                set: { if $0 == nil { view.viewModel.previewURL = nil } }
            )
        }
        
        func body(content: Content) -> some View {
            let step1 = applyNavAndAppear(content)
            let step2 = applyAlerts(step1)
            let step3 = applySheets(step2)
            let step4 = applyOverlayAndNav(step3)
            return step4
        }
        
        @ViewBuilder
        private func applyNavAndAppear(_ content: Content) -> some View {
            content
                .navigationTitle(view.folderTitle)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    view.viewModel.bind(modelContext: view.modelContext)
                    view.viewModel.startObservingChanges()
                    view.viewModel.reload()
                    if let docId = coordinator.pendingOpenDocumentId,
                       view.viewModel.docs.first(where: { $0.id == docId }) != nil || view.viewModel.docs.isEmpty {
                        coordinator.pendingOpenDocumentId = nil
                        view.viewModel.openIfPresent(docId: docId)
                    }
                    
                    Task {
                        await CountersService.shared.reset(familyId: view.familyId, field: .documents)
                        await MainActor.run {
                            BadgeManager.shared.clearDocuments()
                        }
                    }
                    
                    let defaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
                    if let data = defaults?.dictionary(forKey: "pendingShare") as? [String: String],
                       data["destination"] == "document",
                       let pathString = data["sharedFilePath"],
                       !pathString.isEmpty {
                        
                        // Pulisci subito per non ripetere l'upload al prossimo onAppear
                        defaults?.removeObject(forKey: "pendingShare")
                        
                        let fileURL = URL(fileURLWithPath: pathString)
                        let title = data["title"] ?? ""
                        
                        // Piccolo delay per assicurarsi che la view sia pronta
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            Task {
                                view.viewModel.isUploading = true
                                view.viewModel.uploadCurrentName = title.isEmpty
                                ? fileURL.lastPathComponent
                                : title
                                
                                let ok = await view.viewModel.uploadSingleFileFromURL(
                                    fileURL,
                                    forcedMime: pathString.hasSuffix(".jpg") || pathString.hasSuffix(".jpeg")
                                    ? "image/jpeg"
                                    : nil,
                                    forcedTitle: title.isEmpty ? nil : title
                                )
                                
                                view.viewModel.uploadDone = 1
                                view.viewModel.uploadFailures = ok ? 0 : 1
                                view.viewModel.isUploading = false
                                view.viewModel.uploadCurrentName = ""
                                
                                // Pulisci il file temporaneo dall'App Group
                                try? FileManager.default.removeItem(at: fileURL)
                                
                                view.viewModel.reload()
                                if ok {
                                    SyncCenter.shared.flushGlobal(modelContext: view.modelContext)
                                }
                            }
                        }
                    }
                }
                .onChange(of: coordinator.pendingOpenDocumentId) { _, newDocId in
                    guard let docId = newDocId else { return }
                    if view.viewModel.docs.first(where: { $0.id == docId }) != nil || view.viewModel.docs.isEmpty {
                        coordinator.pendingOpenDocumentId = nil
                        view.viewModel.openIfPresent(docId: docId)
                    }
                }
                .toolbar { view.topToolbar }
        }
        
        @ViewBuilder
        private func applyAlerts<V: View>(_ content: V) -> some View {
            content
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
                        Task { @MainActor in await view.viewModel.deleteSelectedItems() }
                    }
                } message: {
                    Text("Questa azione eliminerà cartelle e documenti selezionati in locale e in remoto su tutti i dispositivi.")
                }
                .alert("Chiave di crittografia non trovata", isPresented: Binding(
                    get: { view.viewModel.showKeyMissingAlert },
                    set: { view.viewModel.showKeyMissingAlert = $0 }
                )) {
                    view.keyMissingAlertButtons
                } message: {
                    view.keyMissingAlertMessage
                }
        }
        
        @ViewBuilder
        private func applySheets<V: View>(_ content: V) -> some View {
            content
            // Preview
                .sheet(item: previewItemBinding) { item in
                    QuickLookPreview(urls: [item.url], initialIndex: 0)
                }
            // Camera
                .sheet(isPresented: view.$showCamera) { view.cameraSheet }
            // FolderPicker (Sposta / Copia)
                .sheet(isPresented: Binding(
                    get: { view.viewModel.showFolderPicker },
                    set: { view.viewModel.showFolderPicker = $0 }
                )) {
                    FolderPickerSheet(
                        familyId: view.familyId,
                        excludedFolderIds: view.viewModel.excludedFolderIdsForCurrentOperation(),
                        title: view.viewModel.folderPickerTitle,
                        onSelect: { destId in
                            view.viewModel.resolvePendingOperation(destinationId: destId)
                        }
                    )
                }
            // Photo library
                .photosPicker(
                    isPresented: view.$viewModel.showPhotoLibrary,
                    selection: view.$viewModel.photoItems,
                    maxSelectionCount: 0,
                    matching: .images
                )
                .onChange(of: view.viewModel.photoItems) { _, items in
                    guard !items.isEmpty else { return }
                    Task { @MainActor in await view.viewModel.handlePhotoLibrarySelection(items) }
                }
        }
        
        @ViewBuilder
        private func applyOverlayAndNav<V: View>(_ content: V) -> some View {
            content
                .overlay {
                    ZStack { view.uploadingOverlay; view.downloadingOverlay }
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
}
