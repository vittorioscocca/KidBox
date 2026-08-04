//
//  TravelTripAlbumService.swift
//  KidBox
//

import Foundation
import SwiftData

enum TravelTripAlbumService {

    static func defaultAlbumTitle(for trip: KBTrip) -> String {
        "Viaggio · \(trip.name)"
    }

    /// Crea o recupera l'album KidBox dedicato al viaggio e aggiorna `trip.photoAlbumId`.
    @discardableResult
    static func ensureAlbum(
        for trip: KBTrip,
        modelContext: ModelContext,
        userId: String
    ) -> String? {
        guard !userId.isEmpty else { return nil }

        if let existing = trip.photoAlbumId, !existing.isEmpty,
           albumExists(id: existing, familyId: trip.familyId, in: modelContext) {
            return existing
        }

        let familyId = trip.familyId
        let descriptor = FetchDescriptor<KBPhotoAlbum>(
            predicate: #Predicate<KBPhotoAlbum> { $0.familyId == familyId && !$0.isDeleted }
        )
        let sortOrder = (try? modelContext.fetchCount(descriptor)) ?? 0

        // Album già esistente di questo viaggio, rimasto scollegato: si
        // riaggancia invece di crearne un secondo. Stessa fragilità della
        // nota — l'unico legame è `trip.photoAlbumId`.
        let wantedTitle = defaultAlbumTitle(for: trip)
        let existingDescriptor = FetchDescriptor<KBPhotoAlbum>(
            predicate: #Predicate<KBPhotoAlbum> { $0.familyId == familyId && !$0.isDeleted }
        )
        if let orphan = (try? modelContext.fetch(existingDescriptor))?.first(where: {
            $0.title.trimmingCharacters(in: .whitespaces) == wantedTitle.trimmingCharacters(in: .whitespaces)
        }) {
            trip.photoAlbumId = orphan.id
            trip.updatedAt = .now
            try? modelContext.save()
            return orphan.id
        }

        let album = KBPhotoAlbum(
            familyId: trip.familyId,
            title: defaultAlbumTitle(for: trip),
            sortOrder: sortOrder,
            createdBy: userId,
            updatedBy: userId
        )
        modelContext.insert(album)
        trip.photoAlbumId = album.id
        trip.updatedAt = .now
        try? modelContext.save()
        SyncCenter.shared.uploadAlbumDirectly(
            albumId: album.id,
            familyId: trip.familyId,
            modelContext: modelContext
        )
        return album.id
    }

    static func photoCount(albumId: String, in photos: [KBFamilyPhoto]) -> Int {
        photos.filter { !$0.isDeleted && $0.albumIds.contains(albumId) }.count
    }

    private static func albumExists(id: String, familyId: String, in context: ModelContext) -> Bool {
        let albumId = id
        let fid = familyId
        let descriptor = FetchDescriptor<KBPhotoAlbum>(
            predicate: #Predicate<KBPhotoAlbum> {
                $0.id == albumId && $0.familyId == fid && !$0.isDeleted
            }
        )
        return (try? context.fetch(descriptor).first) != nil
    }
}
