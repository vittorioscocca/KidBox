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
