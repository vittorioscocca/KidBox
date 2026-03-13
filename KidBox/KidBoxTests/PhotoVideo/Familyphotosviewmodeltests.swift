//
//  FamilyPhotosViewModelTests.swift
//  KidBoxTests
//
//  Testa FamilyPhotosViewModel in isolamento usando un ModelContainer in-memory.
//
//  Problema risolto: il ModelContainer in-memory non deve includere modelli
//  che attivano SyncCenter o Firebase come side effect (KBTreatment, KBVisit, ecc.).
//  Usiamo uno schema minimale con solo KBFamilyPhoto e KBPhotoAlbum.
//
//  IMPORTANTE: FamilyPhotosViewModel osserva SyncCenter.shared.photosChanged
//  in observePhotosChanged(). Nei test questo non causa problemi perché
//  il publisher non emette mai — ma se causasse crash, wrappa il test
//  con XCTExpectFailure o mocka il publisher.
//

import XCTest
import SwiftData
@testable import KidBox

@MainActor
final class FamilyPhotosViewModelTests: XCTestCase {
    
    // MARK: - Setup
    
    private var container: ModelContainer!
    private var context: ModelContext!
    private let familyId = "test-family-123"
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Schema minimale: solo i due modelli che il VM usa.
        // Non includere altri modelli SwiftData dell'app per evitare
        // che i loro init attivino SyncCenter / Firebase.
        let schema = Schema([KBFamilyPhoto.self, KBPhotoAlbum.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext
    }
    
    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func makeVM() -> FamilyPhotosViewModel {
        FamilyPhotosViewModel(familyId: familyId)
    }
    
    private func insertPhoto(
        id: String = UUID().uuidString,
        familyId: String? = nil,
        isDeleted: Bool = false,
        takenAt: Date = Date(),
        albumIdsRaw: String = ""
    ) -> KBFamilyPhoto {
        let p = KBFamilyPhoto(
            id: id,
            familyId: familyId ?? self.familyId,
            fileName: "photo_\(id).jpg",
            createdBy: "u1", updatedBy: "u1",
            albumIdsRaw: albumIdsRaw
        )
        p.takenAt = takenAt
        p.isDeleted = isDeleted
        context.insert(p)
        try? context.save()
        return p
    }
    
    private func insertAlbum(
        id: String = UUID().uuidString,
        title: String = "Album",
        sortOrder: Int = 0,
        isDeleted: Bool = false
    ) -> KBPhotoAlbum {
        let a = KBPhotoAlbum(
            id: id, familyId: familyId, title: title,
            sortOrder: sortOrder, createdBy: "u1", updatedBy: "u1"
        )
        a.isDeleted = isDeleted
        context.insert(a)
        try? context.save()
        return a
    }
    
    // MARK: - bind + reloadLocal
    
    func test_bind_loadsExistingPhotos() {
        insertPhoto(id: "p1")
        insertPhoto(id: "p2")
        
        let vm = makeVM()
        XCTAssertTrue(vm.photos.isEmpty, "Prima di bind photos deve essere vuoto")
        
        vm.bind(modelContext: context)
        
        XCTAssertEqual(vm.photos.count, 2)
    }
    
    func test_bind_isIdempotent() {
        insertPhoto(id: "p1")
        let vm = makeVM()
        vm.bind(modelContext: context)
        vm.bind(modelContext: context)
        XCTAssertEqual(vm.photos.count, 1)
    }
    
    func test_reloadLocal_excludesDeletedPhotos() {
        insertPhoto(id: "visible", isDeleted: false)
        insertPhoto(id: "deleted", isDeleted: true)
        
        let vm = makeVM()
        vm.bind(modelContext: context)
        
        XCTAssertEqual(vm.photos.count, 1)
        XCTAssertEqual(vm.photos.first?.id, "visible")
    }
    
    func test_reloadLocal_excludesOtherFamilyPhotos() {
        insertPhoto(id: "mine",   familyId: familyId)
        insertPhoto(id: "theirs", familyId: "other-family")
        
        let vm = makeVM()
        vm.bind(modelContext: context)
        
        XCTAssertEqual(vm.photos.count, 1)
        XCTAssertEqual(vm.photos.first?.id, "mine")
    }
    
    func test_reloadLocal_photosOrderedByTakenAtDesc() {
        let old    = Date(timeIntervalSinceNow: -3600)
        let mid    = Date(timeIntervalSinceNow: -1800)
        let recent = Date()
        
        insertPhoto(id: "old",    takenAt: old)
        insertPhoto(id: "recent", takenAt: recent)
        insertPhoto(id: "mid",    takenAt: mid)
        
        let vm = makeVM()
        vm.bind(modelContext: context)
        
        XCTAssertEqual(vm.photos.map(\.id), ["recent", "mid", "old"])
    }
    
    func test_reloadLocal_afterInsert_picksUpNewPhoto() {
        let vm = makeVM()
        vm.bind(modelContext: context)
        XCTAssertEqual(vm.photos.count, 0)
        
        insertPhoto(id: "late")
        vm.reloadLocal()
        
        XCTAssertEqual(vm.photos.count, 1)
    }
    
    func test_reloadLocal_afterSoftDelete_removesPhoto() {
        let p = insertPhoto(id: "p1")
        let vm = makeVM()
        vm.bind(modelContext: context)
        XCTAssertEqual(vm.photos.count, 1)
        
        p.isDeleted = true
        try? context.save()
        vm.reloadLocal()
        
        XCTAssertEqual(vm.photos.count, 0)
    }
    
    // MARK: - Albums
    
    func test_bind_loadsAlbums() {
        insertAlbum(id: "a1", title: "Vacanze")
        insertAlbum(id: "a2", title: "Natale")
        
        let vm = makeVM()
        vm.bind(modelContext: context)
        
        XCTAssertEqual(vm.albums.count, 2)
    }
    
    func test_albums_excludesDeleted() {
        insertAlbum(id: "active",  isDeleted: false)
        insertAlbum(id: "deleted", isDeleted: true)
        
        let vm = makeVM()
        vm.bind(modelContext: context)
        
        XCTAssertEqual(vm.albums.count, 1)
        XCTAssertEqual(vm.albums.first?.id, "active")
    }
    
    func test_albums_orderedBySortOrder() {
        insertAlbum(id: "third",  sortOrder: 2)
        insertAlbum(id: "first",  sortOrder: 0)
        insertAlbum(id: "second", sortOrder: 1)
        
        let vm = makeVM()
        vm.bind(modelContext: context)
        
        XCTAssertEqual(vm.albums.map(\.id), ["first", "second", "third"])
    }
    
    // MARK: - cleanup
    
    func test_cleanup_doesNotCrash() {
        let vm = makeVM()
        vm.bind(modelContext: context)
        vm.cleanup()
    }
    
    func test_cleanup_thenReload_doesNotCrash() {
        let vm = makeVM()
        vm.bind(modelContext: context)
        vm.cleanup()
        vm.reloadLocal()
    }
    
    // MARK: - Album photo count (il bug fixato)
    
    func test_albumPhotoCount_afterCameraUpload_isCorrect() {
        let albumId = "album-camera"
        insertAlbum(id: albumId, title: "Camera")
        
        insertPhoto(id: "cam1",     albumIdsRaw: albumId)
        insertPhoto(id: "cam2",     albumIdsRaw: albumId)
        insertPhoto(id: "lib-only", albumIdsRaw: "")
        
        let vm = makeVM()
        vm.bind(modelContext: context)
        
        let albumPhotos = vm.photos.filter { $0.albumIds.contains(albumId) }
        XCTAssertEqual(albumPhotos.count, 2, "L'album deve contenere esattamente 2 foto")
        XCTAssertEqual(vm.photos.count, 3, "La libreria deve contenere tutte e 3 le foto")
    }
    
    func test_albumPhotoCount_multipleAlbums_countsCorrectly() {
        let album1 = "album-1"
        let album2 = "album-2"
        insertAlbum(id: album1, title: "Album 1", sortOrder: 0)
        insertAlbum(id: album2, title: "Album 2", sortOrder: 1)
        
        insertPhoto(id: "p1", albumIdsRaw: album1)
        insertPhoto(id: "p2", albumIdsRaw: album1)
        insertPhoto(id: "p3", albumIdsRaw: "\(album1),\(album2)")  // in entrambi
        insertPhoto(id: "p4", albumIdsRaw: album2)
        
        let vm = makeVM()
        vm.bind(modelContext: context)
        
        let a1Photos = vm.photos.filter { $0.albumIds.contains(album1) }
        let a2Photos = vm.photos.filter { $0.albumIds.contains(album2) }
        
        XCTAssertEqual(a1Photos.count, 3, "Album 1 deve avere 3 foto")
        XCTAssertEqual(a2Photos.count, 2, "Album 2 deve avere 2 foto")
    }
}
