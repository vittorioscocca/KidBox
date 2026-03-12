//
//  FamilyPhotosViewModel.swift
//  KidBox
//
//  Pattern mirrors ChatViewModel exactly:
//  - @Published var photos / albums invece di @Query direttamente nella view.
//  - reloadLocal() rilegge SwiftData e riassegna l'array → re-render garantito.
//  - SyncCenter._photosChanged → reloadLocal() per aggiornamenti inbound dal listener.
//
//  Perché @Query non bastava:
//  SwiftData @Query osserva inserimenti/cancellazioni ma non propaga affidabilmente
//  modifiche a proprietà Optional<Double> su oggetti esistenti all'interno di una
//  LazyVGrid, causando la mancata comparsa della badge durata sui video.
//

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
    
    // MARK: - Bind (chiamato dalla view con @Environment(\.modelContext))
    
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
    
    // MARK: - Reload (debounced, identico a ChatViewModel)
    
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
        
        // --- Photos ---
        let photoDesc = FetchDescriptor<KBFamilyPhoto>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        if let rows = try? modelContext.fetch(photoDesc) {
            // Riassegna sempre — non confrontiamo per evitare che la guard blocchi
            // aggiornamenti a campi come videoDurationSeconds quando updatedAt
            // è identico tra due snapshot Firestore consecutivi.
            self.photos = rows
            KBLog.sync.kbDebug("FamilyPhotosVM reloadLocal: photos=\(rows.count) familyId=\(fid)")
        }
        
        // --- Albums ---
        // Riassegna sempre (no guard su ids) — lo stesso motivo delle foto:
        // il ViewModel deve aggiornare la UI anche quando solo titolo/sortOrder cambia.
        let albumDesc = FetchDescriptor<KBPhotoAlbum>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        if let rows = try? modelContext.fetch(albumDesc) {
            self.albums = rows
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        reloadTask?.cancel()
        cancellables.removeAll()
    }
}
