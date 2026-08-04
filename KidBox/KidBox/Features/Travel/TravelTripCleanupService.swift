//
//  TravelTripCleanupService.swift
//  KidBox
//
//  Rimozione delle entità che un viaggio si porta dietro: album foto, nota,
//  lista todo. Senza questa pulizia, eliminando il viaggio restavano visibili
//  in Foto, Note e Todo un album, una nota e una lista intestati a un viaggio
//  che non esiste più — e l'utente non aveva modo di collegarli a nulla.
//
//  Le spese NON sono qui: vivono nella sottocollezione `expenses` del viaggio
//  su Firestore e spariscono con il documento padre (TripRemoteStore).
//

import Foundation
import SwiftData

enum TravelTripCleanupService {

    /// Cancella album, nota e lista todo collegati al viaggio.
    ///
    /// Da chiamare PRIMA di cancellare il viaggio: i riferimenti stanno sul
    /// `KBTrip` (`photoAlbumId`, `notesNoteId`, `todoListId`), quindi una volta
    /// rimosso l'oggetto non c'è più modo di risalire a cosa cancellare.
    ///
    /// Usa i percorsi di cancellazione già esistenti per ciascuna entità
    /// (soft delete + outbox di SyncCenter) invece di toccare Firestore
    /// direttamente: sono gli stessi che usano Note, Foto e Todo, quindi la
    /// cancellazione si propaga agli altri membri della famiglia esattamente
    /// come se l'utente l'avesse fatta da quelle schermate.
    @MainActor
    static func deleteAttachedEntities(
        for trip: KBTrip,
        modelContext: ModelContext,
        userId: String
    ) {
        let familyId = trip.familyId
        let now = Date()

        // ── Album foto ────────────────────────────────────────────────
        // Le foto dentro l'album NON si cancellano: possono essere state
        // spostate o riusate altrove, e cancellare media altrui è un danno
        // irreversibile. Sparisce il contenitore, non i ricordi.
        if let albumId = trip.photoAlbumId, !albumId.isEmpty {
            let descriptor = FetchDescriptor<KBPhotoAlbum>(
                predicate: #Predicate<KBPhotoAlbum> { $0.id == albumId }
            )
            if let album = try? modelContext.fetch(descriptor).first {
                album.isDeleted = true
                album.updatedAt = now
            }
            SyncCenter.shared.deleteAlbumDirectly(
                albumId: albumId, familyId: familyId, modelContext: modelContext
            )
        }

        // ── Nota di viaggio ───────────────────────────────────────────
        if let noteId = trip.notesNoteId, !noteId.isEmpty {
            let descriptor = FetchDescriptor<KBNote>(
                predicate: #Predicate<KBNote> { $0.id == noteId }
            )
            if let note = try? modelContext.fetch(descriptor).first {
                note.isDeleted = true
                note.syncState = .pendingDelete
                note.lastSyncError = nil
                note.updatedAt = now
            }
            SyncCenter.shared.enqueueNoteDelete(
                noteId: noteId, familyId: familyId, modelContext: modelContext
            )
        }

        // ── Lista todo ────────────────────────────────────────────────
        // Qui i figli SI cancellano: un todo appartiene alla sua lista e da
        // solo non significa niente (a differenza di una foto).
        if let listId = trip.todoListId, !listId.isEmpty {
            let todoDescriptor = FetchDescriptor<KBTodoItem>(
                predicate: #Predicate<KBTodoItem> { $0.listId == listId && $0.isDeleted == false }
            )
            for todo in (try? modelContext.fetch(todoDescriptor)) ?? [] {
                todo.isDeleted = true
                todo.syncState = .pendingDelete
                todo.lastSyncError = nil
                todo.updatedBy = userId
                todo.updatedAt = now
                SyncCenter.shared.enqueueTodoDelete(
                    todoId: todo.id, familyId: familyId, modelContext: modelContext
                )
            }

            let listDescriptor = FetchDescriptor<KBTodoList>(
                predicate: #Predicate<KBTodoList> { $0.id == listId }
            )
            if let list = try? modelContext.fetch(listDescriptor).first {
                list.isDeleted = true
                list.updatedAt = now
            }
            SyncCenter.shared.enqueueTodoListDelete(
                listId: listId, familyId: familyId, modelContext: modelContext
            )
        }

        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        KBLog.sync.kbInfo(
            "TravelTripCleanup: tripId=\(trip.id) album=\(trip.photoAlbumId ?? "-") note=\(trip.notesNoteId ?? "-") list=\(trip.todoListId ?? "-")"
        )
    }
}
