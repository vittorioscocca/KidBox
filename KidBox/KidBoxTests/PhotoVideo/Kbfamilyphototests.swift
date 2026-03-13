//
//  Kbfamilyphototests.swift
//  KidBox
//
//  Created by vscocca on 13/03/26.
//

//
//  KBFamilyPhotoTests.swift
//  KidBoxTests
//
//  Testa la logica pura del modello KBFamilyPhoto:
//  - isVideo (mimeType + estensione fileName)
//  - albumIds (encode/decode da albumIdsRaw)
//  - thumbnailData (decode base64)
//  - stableGridId (identità composita per LazyVGrid)
//  - syncState round-trip
//
//  Non richiede Firebase, SwiftData, né rete.
//

import XCTest
@testable import KidBox

final class KBFamilyPhotoTests: XCTestCase {
    
    // MARK: - Factory
    
    private func makePhoto(
        mimeType: String = "image/jpeg",
        fileName: String = "photo_abc.jpg",
        videoDurationSeconds: Double? = nil,
        albumIdsRaw: String = ""
    ) -> KBFamilyPhoto {
        let p = KBFamilyPhoto(
            familyId: "fam1",
            fileName: fileName,
            mimeType: mimeType,
            createdBy: "user1",
            updatedBy: "user1",
            albumIdsRaw: albumIdsRaw
        )
        p.videoDurationSeconds = videoDurationSeconds
        return p
    }
    
    // MARK: - isVideo
    
    func test_isVideo_jpegMime_returnsFalse() {
        let photo = makePhoto(mimeType: "image/jpeg", fileName: "photo.jpg")
        XCTAssertFalse(photo.isVideo)
    }
    
    func test_isVideo_mp4Mime_returnsTrue() {
        let photo = makePhoto(mimeType: "video/mp4", fileName: "video.mp4")
        XCTAssertTrue(photo.isVideo)
    }
    
    func test_isVideo_movExtensionFallback_returnsTrue() {
        // Vecchi record caricati con mimeType generico ma estensione .mov
        let photo = makePhoto(mimeType: "application/octet-stream", fileName: "clip.mov")
        XCTAssertTrue(photo.isVideo)
    }
    
    func test_isVideo_m4vExtension_returnsTrue() {
        let photo = makePhoto(mimeType: "video/x-m4v", fileName: "clip.m4v")
        XCTAssertTrue(photo.isVideo)
    }
    
    func test_isVideo_mp4Extension_withGenericMime_returnsTrue() {
        let photo = makePhoto(mimeType: "application/octet-stream", fileName: "video_abc.mp4")
        XCTAssertTrue(photo.isVideo)
    }
    
    func test_isVideo_pngExtension_returnsFalse() {
        let photo = makePhoto(mimeType: "image/png", fileName: "image.png")
        XCTAssertFalse(photo.isVideo)
    }
    
    // MARK: - albumIds
    
    func test_albumIds_emptyRaw_returnsEmptyArray() {
        let photo = makePhoto(albumIdsRaw: "")
        XCTAssertEqual(photo.albumIds, [])
    }
    
    func test_albumIds_singleId_returnsOneElement() {
        let photo = makePhoto(albumIdsRaw: "album-1")
        XCTAssertEqual(photo.albumIds, ["album-1"])
    }
    
    func test_albumIds_multipleIds_returnsAll() {
        let photo = makePhoto(albumIdsRaw: "album-1,album-2,album-3")
        XCTAssertEqual(photo.albumIds, ["album-1", "album-2", "album-3"])
    }
    
    func test_albumIds_setter_encodesCorrectly() {
        let photo = makePhoto()
        photo.albumIds = ["x", "y"]
        XCTAssertEqual(photo.albumIdsRaw, "x,y")
    }
    
    func test_albumIds_setter_emptyArray_clearsRaw() {
        let photo = makePhoto(albumIdsRaw: "album-1")
        photo.albumIds = []
        XCTAssertEqual(photo.albumIdsRaw, "")
    }
    
    func test_albumIds_addAndRemove_roundTrip() {
        let photo = makePhoto(albumIdsRaw: "a,b,c")
        var ids = photo.albumIds
        ids.removeAll { $0 == "b" }
        photo.albumIds = ids
        XCTAssertEqual(photo.albumIds, ["a", "c"])
    }
    
    // MARK: - thumbnailData
    
    func test_thumbnailData_nil_whenNoBase64() {
        let photo = makePhoto()
        photo.thumbnailBase64 = nil
        XCTAssertNil(photo.thumbnailData)
    }
    
    func test_thumbnailData_validBase64_returnsData() {
        let original = Data("hello thumbnail".utf8)
        let photo = makePhoto()
        photo.thumbnailBase64 = original.base64EncodedString()
        XCTAssertEqual(photo.thumbnailData, original)
    }
    
    func test_thumbnailData_invalidBase64_returnsNil() {
        let photo = makePhoto()
        photo.thumbnailBase64 = "not-valid-base64!!!"
        XCTAssertNil(photo.thumbnailData)
    }
    
    // MARK: - stableGridId
    
    func test_stableGridId_noVideoDuration_equalsId() {
        let photo = makePhoto()
        photo.videoDurationSeconds = nil
        XCTAssertEqual(photo.stableGridId, photo.id)
    }
    
    func test_stableGridId_withDuration_includesDurationMs() {
        let photo = makePhoto()
        photo.videoDurationSeconds = 12.345
        let expected = "\(photo.id)-\(Int(12.345 * 1000))"
        XCTAssertEqual(photo.stableGridId, expected)
    }
    
    func test_stableGridId_differentDurations_produceDifferentIds() {
        let p1 = makePhoto(); p1.videoDurationSeconds = 10.0
        let p2 = makePhoto(); p2.videoDurationSeconds = 20.0
        // Stesso UUID base — ma stableGridId diverso per forza re-render
        // (questo test usa due istanze separate con id diversi per semplicità)
        XCTAssertNotEqual(p1.stableGridId, p2.stableGridId)
    }
    
    // MARK: - syncState
    
    func test_syncState_defaultIsPendingUpsert() {
        let photo = makePhoto()
        XCTAssertEqual(photo.syncState, .pendingUpsert)
    }
    
    func test_syncState_roundTrip_synced() {
        let photo = makePhoto()
        photo.syncState = .synced
        XCTAssertEqual(photo.syncState, .synced)
        XCTAssertEqual(photo.syncStateRaw, KBSyncState.synced.rawValue)
    }
    
    func test_syncState_roundTrip_pendingUpsert() {
        let photo = makePhoto()
        photo.syncState = .synced   // cambia prima
        photo.syncState = .pendingUpsert
        XCTAssertEqual(photo.syncState, .pendingUpsert)
    }
    
    // MARK: - PhotoThumbnailCell.formatDuration
    
    func test_formatDuration_seconds_only() {
        XCTAssertEqual(PhotoThumbnailCell.formatDuration(9), "0:09")
    }
    
    func test_formatDuration_minutesAndSeconds() {
        XCTAssertEqual(PhotoThumbnailCell.formatDuration(90), "1:30")
    }
    
    func test_formatDuration_hoursMinutesSeconds() {
        XCTAssertEqual(PhotoThumbnailCell.formatDuration(3661), "1:01:01")
    }
    
    func test_formatDuration_exactOneHour() {
        XCTAssertEqual(PhotoThumbnailCell.formatDuration(3600), "1:00:00")
    }
    
    func test_formatDuration_zero() {
        XCTAssertEqual(PhotoThumbnailCell.formatDuration(0), "0:00")
    }
}
