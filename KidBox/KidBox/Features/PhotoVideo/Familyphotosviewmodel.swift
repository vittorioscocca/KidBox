//
//  FamilyPhotosViewModel.swift
//  KidBox
//
//  ╔══════════════════════════════════════════════════════════════════╗
//  ║  BUG FIX — download triplicato / quadruplicato delle foto       ║
//  ╠══════════════════════════════════════════════════════════════════╣
//  ║  Causa:                                                         ║
//  ║    reloadLocal() riassegnava SEMPRE self.photos = rows anche    ║
//  ║    quando i dati non erano cambiati (es. secondo snapshot       ║
//  ║    Firestore per la stessa foto con updatedAt identico).        ║
//  ║    Ogni riassegnazione forza SwiftUI a ricreare le celle della  ║
//  ║    LazyVGrid, che rilanciano .task(id: photo.id) → download     ║
//  ║    ripetuto dello stesso file da 34 MB + decryption inutile.   ║
//  ║                                                                 ║
//  ║  Fix:                                                           ║
//  ║    Confronto per ID prima di riassegnare self.photos.           ║
//  ║    Se gli ID sono identici (stesso set, stesso ordine) non      ║
//  ║    viene toccato l'array → SwiftUI non ricrea le celle →        ║
//  ║    i .task non ripartono → nessun download ripetuto.           ║
//  ║                                                                 ║
//  ║    Per i campi che cambiano senza che cambi l'ID (es.          ║
//  ║    videoDurationSeconds, thumbnailBase64) usiamo               ║
//  ║    updateInPlace(): aggiorniamo solo la proprietà che è        ║
//  ║    cambiata sull'oggetto SwiftData già in memoria.             ║
//  ║    SwiftData propagherà il @Published tramite @Bindable         ║
//  ║    senza ricreare le celle.                                     ║
//  ╚══════════════════════════════════════════════════════════════════╝

import Foundation
import SwiftUI
import SwiftData
import Combine
import FirebaseAuth

@MainActor
final class FamilyPhotosViewModel: ObservableObject {
    
    // MARK: - Input
    let familyId: String
    
    // MARK: - Published state
    @Published var photos: [KBFamilyPhoto] = []
    @Published var albums: [KBPhotoAlbum]  = []
    
    // MARK: - Private
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var reloadTask: Task<Void, Never>?
    
    // MARK: - Init
    
    init(familyId: String) {
        self.familyId = familyId
    }
    
    // MARK: - Bind
    
    func bind(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        reloadLocal()
        observePhotosChanged()
    }
    
    // MARK: - Osserva SyncCenter._photosChanged
    
    private func observePhotosChanged() {
        SyncCenter.shared.photosChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] familyId in
                guard let self, familyId == self.familyId else { return }
                self.requestReloadLocal(debounceMs: 80, reason: "photosChanged")
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Reload (debounced)
    
    func requestReloadLocal(debounceMs: Int = 80, reason: String = "") {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self.reloadLocal()
        }
    }
    
    func reloadLocal() {
        guard let modelContext else { return }
        let fid = familyId
        
        // ── Photos ────────────────────────────────────────────────────────────
        let photoDesc = FetchDescriptor<KBFamilyPhoto>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        if let rows = try? modelContext.fetch(photoDesc) {
            // FIX — confronto per ID prima di riassegnare.
            //
            // Se gli ID sono identici (stesso set, stesso ordine) non tocchiamo
            // l'array: SwiftUI non ricrea le celle, i .task non ripartono,
            // nessun download ripetuto.
            //
            // Se gli ID cambiano (foto aggiunta, rimossa, riordinata) riassegniamo
            // normalmente → le nuove celle vengono create e scaricano il loro file.
            //
            // Per le proprietà che cambiano senza che l'ID cambi (videoDurationSeconds,
            // thumbnailBase64, downloadURL…) SwiftData le propaga già via @Bindable
            // sulle celle esistenti, senza bisogno di riassegnare l'array.
            let newIds  = rows.map(\.id)
            let currIds = photos.map(\.id)
            if newIds != currIds {
                photos = rows
                KBLog.sync.kbDebug("FamilyPhotosVM reloadLocal: photos UPDATED \(currIds.count)→\(rows.count) familyId=\(fid)")
            } else {
                KBLog.sync.kbDebug("FamilyPhotosVM reloadLocal: photos SKIPPED (ids unchanged) count=\(rows.count) familyId=\(fid)")
            }
        }
        
        // ── Albums ────────────────────────────────────────────────────────────
        // Gli album non scatenano download → riassegniamo sempre per semplicità,
        // così i campi come title e sortOrder vengono sempre aggiornati nella UI.
        let albumDesc = FetchDescriptor<KBPhotoAlbum>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        if let rows = try? modelContext.fetch(albumDesc) {
            albums = rows
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        reloadTask?.cancel()
        cancellables.removeAll()
    }
}
