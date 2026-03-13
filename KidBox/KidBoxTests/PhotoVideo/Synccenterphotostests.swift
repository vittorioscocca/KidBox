//
//  Synccenterphotostests.swift
//  KidBox
//
//  Created by vscocca on 13/03/26.
//

//
//  SyncCenterPhotosTests.swift
//  KidBoxTests
//
//  Testa la logica LWW (Last-Write-Wins) di applyPhotosInbound
//  usando un ModelContainer in-memory e DTO mock.
//
//  Poiché applyPhotosInbound è `private`, lo testiamo indirettamente
//  tramite un metodo `testable` esposto con #if DEBUG oppure
//  tramite l'effetto osservabile su SwiftData (approccio black-box).
//
//  Per abilitare i test su metodi private, aggiungi al SyncCenter+Photos.swift:
//
//    #if DEBUG
//    func applyPhotosInbound_testable(...) { applyPhotosInbound(...) }
//    #endif
//
//  Oppure usa il pattern "package internal" con `internal` invece di `private`.
//

import XCTest
import SwiftData
@testable import KidBox

@MainActor
final class SyncCenterPhotosTests: XCTestCase {
    
    private var container: ModelContainer!
    private var context: ModelContext!
    private let familyId = "fam-sync-test"
    
    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: KBFamilyPhoto.self, KBPhotoAlbum.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }
    
    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func makeDTO(
        id: String = UUID().uuidString,
        fileName: String = "photo.jpg",
        mimeType: String = "image/jpeg",
        storagePath: String = "families/fam/photos/id/original.enc",
        albumIdsRaw: String = "",
        videoDurationSeconds: Double? = nil,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) -> RemotePhotoDTO {
        RemotePhotoDTO(
            id: id,
            familyId: familyId,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: 1000,
            storagePath: storagePath,
            downloadURL: "https://example.com/photo.enc",
            thumbnailBase64: nil,
            caption: nil,
            albumIdsRaw: albumIdsRaw,
            videoDurationSeconds: videoDurationSeconds,
            takenAt: Date(),
            createdAt: Date(),
            updatedAt: updatedAt,
            createdBy: "remote-user",
            updatedBy: "remote-user",
            isDeleted: isDeleted
        )
    }
    
    private func fetchPhoto(id: String) throws -> KBFamilyPhoto? {
        let pid = id
        return try context.fetch(
            FetchDescriptor<KBFamilyPhoto>(predicate: #Predicate { $0.id == pid })
        ).first
    }
    
    private func applyChanges(_ changes: [PhotoRemoteChange]) {
        // Usa il metodo testable esposto con #if DEBUG
        SyncCenter.shared.applyPhotosInbound_testable(
            changes: changes,
            familyId: familyId,
            modelContext: context
        )
    }
    
    // MARK: - LWW: upsert nuovo record
    
    func test_upsert_newPhoto_isInserted() throws {
        let dto = makeDTO(id: "p1")
        applyChanges([.upsert(dto)])
        
        let photo = try fetchPhoto(id: "p1")
        XCTAssertNotNil(photo)
        XCTAssertEqual(photo?.fileName, "photo.jpg")
        XCTAssertEqual(photo?.syncState, .synced)
    }
    
    func test_upsert_existingPhoto_newerRemote_overwritesLocal() throws {
        // Inserisce record locale con data vecchia
        let local = KBFamilyPhoto(
            id: "p2", familyId: familyId,
            fileName: "old_name.jpg",
            createdBy: "u1", updatedBy: "u1"
        )
        local.updatedAt = Date(timeIntervalSinceNow: -3600)  // 1 ora fa
        context.insert(local)
        try context.save()
        
        // DTO remoto più recente
        let dto = makeDTO(id: "p2", fileName: "new_name.jpg", updatedAt: Date())
        applyChanges([.upsert(dto)])
        
        let updated = try fetchPhoto(id: "p2")
        XCTAssertEqual(updated?.fileName, "new_name.jpg", "Il record remoto più recente deve vincere")
    }
    
    func test_upsert_existingPhoto_olderRemote_keepLocal() throws {
        // Record locale più recente
        let local = KBFamilyPhoto(
            id: "p3", familyId: familyId,
            fileName: "local_name.jpg",
            createdBy: "u1", updatedBy: "u1"
        )
        local.updatedAt = Date()  // adesso
        context.insert(local)
        try context.save()
        
        // DTO remoto più vecchio
        let dto = makeDTO(id: "p3", fileName: "stale_name.jpg",
                          updatedAt: Date(timeIntervalSinceNow: -3600))
        applyChanges([.upsert(dto)])
        
        let photo = try fetchPhoto(id: "p3")
        XCTAssertEqual(photo?.fileName, "local_name.jpg", "Il record locale più recente deve vincere")
    }
    
    // MARK: - Placeholder
    
    func test_upsert_placeholder_alwaysOverwritten() throws {
        // Placeholder: storagePath vuoto, updatedAt = distantPast
        let placeholder = KBFamilyPhoto(
            id: "p4", familyId: familyId,
            fileName: "", createdBy: "remote", updatedBy: "remote"
        )
        placeholder.storagePath = ""
        placeholder.updatedAt = .distantPast
        context.insert(placeholder)
        try context.save()
        
        let dto = makeDTO(id: "p4", fileName: "real_photo.jpg",
                          updatedAt: Date(timeIntervalSinceNow: -7200))  // anche vecchio
        applyChanges([.upsert(dto)])
        
        let photo = try fetchPhoto(id: "p4")
        XCTAssertEqual(photo?.fileName, "real_photo.jpg",
                       "Il placeholder deve essere sempre sovrascritto indipendentemente dalla data")
    }
    
    // MARK: - Soft delete
    
    func test_upsert_deletedDTO_removesLocalRecord() throws {
        let local = KBFamilyPhoto(
            id: "p5", familyId: familyId,
            fileName: "to_delete.jpg",
            createdBy: "u1", updatedBy: "u1"
        )
        context.insert(local)
        try context.save()
        
        let dto = makeDTO(id: "p5", isDeleted: true)
        applyChanges([.upsert(dto)])
        
        let photo = try fetchPhoto(id: "p5")
        XCTAssertNil(photo, "La foto con isDeleted=true deve essere rimossa da SwiftData")
    }
    
    // MARK: - Remove change
    
    func test_remove_deletesLocalRecord() throws {
        let local = KBFamilyPhoto(
            id: "p6", familyId: familyId,
            fileName: "removable.jpg",
            createdBy: "u1", updatedBy: "u1"
        )
        context.insert(local)
        try context.save()
        
        applyChanges([.remove("p6")])
        
        let photo = try fetchPhoto(id: "p6")
        XCTAssertNil(photo, "Il change .remove deve eliminare il record locale")
    }
    
    func test_remove_nonExistentId_doesNotCrash() {
        // Non deve crashare per un id che non esiste
        XCTAssertNoThrow(applyChanges([.remove("non-existent-id")]))
    }
    
    // MARK: - videoDurationSeconds
    
    func test_upsert_videoDuration_isPreservedFromRemote() throws {
        let dto = makeDTO(id: "v1", fileName: "video.mp4", mimeType: "video/mp4", videoDurationSeconds: 42.5)
        applyChanges([.upsert(dto)])
        
        let photo = try fetchPhoto(id: "v1")
        XCTAssertEqual(photo?.videoDurationSeconds, 42.5)
    }
    
    func test_upsert_videoDurationNilRemote_doesNotOverwriteLocal() throws {
        // Locale ha già la durata
        let local = KBFamilyPhoto(
            id: "v2", familyId: familyId,
            fileName: "video.mp4", mimeType: "video/mp4",
            createdBy: "u1", updatedBy: "u1"
        )
        local.videoDurationSeconds = 99.0
        local.updatedAt = Date(timeIntervalSinceNow: -3600)
        context.insert(local)
        try context.save()
        
        // Remoto arriva senza durata (listener arrivato prima di upsertMetadata)
        let dto = makeDTO(id: "v2", fileName: "video.mp4", mimeType: "video/mp4", videoDurationSeconds: nil,
                          updatedAt: Date())
        applyChanges([.upsert(dto)])
        
        let photo = try fetchPhoto(id: "v2")
        XCTAssertEqual(photo?.videoDurationSeconds, 99.0,
                       "La durata locale non deve essere sovrascritta da un remoto con nil")
    }
    
    // MARK: - albumIdsRaw
    
    func test_upsert_albumIds_areApplied() throws {
        let dto = makeDTO(id: "a1", albumIdsRaw: "album-x,album-y")
        applyChanges([.upsert(dto)])
        
        let photo = try fetchPhoto(id: "a1")
        XCTAssertEqual(photo?.albumIds, ["album-x", "album-y"])
    }
    
    // MARK: - Multiple changes
    
    func test_multipleChanges_appliedInOrder() throws {
        let dto1 = makeDTO(id: "m1", fileName: "first.jpg")
        let dto2 = makeDTO(id: "m2", fileName: "second.jpg")
        applyChanges([.upsert(dto1), .upsert(dto2)])
        
        XCTAssertNotNil(try fetchPhoto(id: "m1"))
        XCTAssertNotNil(try fetchPhoto(id: "m2"))
    }
    
}
