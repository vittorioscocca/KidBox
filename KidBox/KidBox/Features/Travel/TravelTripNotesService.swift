//
//  TravelTripNotesService.swift
//  KidBox
//

import Foundation
import SwiftData
import UIKit

enum TravelTripNotesService {

    static func defaultNoteTitle(for trip: KBTrip) -> String {
        trip.name
    }

    private static let bodyTemplate = """
    Annotazioni di viaggio

    • Idee e promemoria
    • Indirizzi e contatti utili
    • Spese da ricordare

    """

    /// Crea o recupera la nota KidBox dedicata al viaggio e aggiorna `trip.notesNoteId`.
    @discardableResult
    static func ensureNote(
        for trip: KBTrip,
        modelContext: ModelContext,
        userId: String,
        userDisplayName: String = ""
    ) -> String? {
        guard !userId.isEmpty else { return nil }

        if let existing = trip.notesNoteId, !existing.isEmpty,
           let note = fetchNote(id: existing, familyId: trip.familyId, in: modelContext) {
            if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note.title = defaultNoteTitle(for: trip)
                note.updatedAt = .now
                try? modelContext.save()
                SyncCenter.shared.enqueueNoteUpsert(
                    noteId: note.id,
                    familyId: trip.familyId,
                    modelContext: modelContext
                )
            }
            return note.id
        }

        // Prima di creare: esiste già una nota di QUESTO viaggio rimasta
        // scollegata? Il legame è il solo `trip.notesNoteId`, e se quel
        // puntatore si perde — una sync che riscrive il viaggio, un oggetto
        // stantio, una corsa fra la creazione e il primo snapshot — senza
        // questo controllo si creerebbe un duplicato a ogni tentativo, invece
        // di riagganciare la nota che c'è già.
        if let orphan = fetchNoteByTitle(
            defaultNoteTitle(for: trip), familyId: trip.familyId, in: modelContext
        ) {
            trip.notesNoteId = orphan.id
            trip.updatedAt = .now
            try? modelContext.save()
            KBLog.sync.kbInfo("TravelTripNotes: nota riagganciata tripId=\(trip.id) noteId=\(orphan.id)")
            return orphan.id
        }

        let note = KBNote(
            familyId: trip.familyId,
            title: defaultNoteTitle(for: trip),
            body: bodyTemplate,
            createdBy: userId,
            createdByName: userDisplayName,
            updatedBy: userId,
            updatedByName: userDisplayName
        )
        note.syncState = .pendingUpsert
        modelContext.insert(note)
        trip.notesNoteId = note.id
        trip.updatedAt = .now
        try? modelContext.save()
        SyncCenter.shared.enqueueNoteUpsert(
            noteId: note.id,
            familyId: trip.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        return note.id
    }

    static func hasUserContent(noteId: String, in notes: [KBNote]) -> Bool {
        guard let note = notes.first(where: { $0.id == noteId && !$0.isDeleted }) else { return false }
        let body = plainText(from: note.body)
        let template = plainText(from: bodyTemplate)
        return !body.isEmpty && body != template
    }

    private static func plainText(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("<"), let data = trimmed.data(using: .utf8) else { return trimmed }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil))?
            .string
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
    }


    /// Nota già esistente con il titolo del viaggio, non cancellata.
    ///
    /// Il titolo è l'unico appiglio disponibile: `KBNote` non ha un `tripId`,
    /// e aggiungerlo richiederebbe una migrazione dello schema. Il rischio di
    /// falso positivo è una nota creata a mano con esattamente lo stesso nome
    /// del viaggio — molto meno dannoso di un duplicato a ogni apertura.
    private static func fetchNoteByTitle(
        _ title: String, familyId: String, in context: ModelContext
    ) -> KBNote? {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let fid = familyId
        let descriptor = FetchDescriptor<KBNote>(
            predicate: #Predicate<KBNote> { $0.familyId == fid && !$0.isDeleted }
        )
        return (try? context.fetch(descriptor))?.first {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == wanted
        }
    }

    private static func fetchNote(id: String, familyId: String, in context: ModelContext) -> KBNote? {
        let noteId = id
        let fid = familyId
        let descriptor = FetchDescriptor<KBNote>(
            predicate: #Predicate<KBNote> {
                $0.id == noteId && $0.familyId == fid && !$0.isDeleted
            }
        )
        return try? context.fetch(descriptor).first
    }
}
