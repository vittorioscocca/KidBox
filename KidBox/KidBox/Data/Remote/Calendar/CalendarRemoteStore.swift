//
//  CalendarRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 10/03/26.
//

import Foundation
import FirebaseFirestore

// MARK: - CalendarRemoteStore

final class CalendarRemoteStore {
    
    private let db = Firestore.firestore()
    
    // MARK: - Collection ref
    
    /// `families/{familyId}/calendarEvents`
    private func col(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("calendarEvents")
    }
    
    // MARK: - Upsert
    
    func upsert(dto: KBCalendarEventDTO) async throws {
        var data: [String: Any] = [
            "id":            dto.id,
            "familyId":      dto.familyId,
            "title":         dto.title,
            "isAllDay":      dto.isAllDay,
            "categoryRaw":   dto.categoryRaw,
            "recurrenceRaw": dto.recurrenceRaw,
            "isDeleted":     dto.isDeleted,
            "startDate":     Timestamp(date: dto.startDate),
            "endDate":       Timestamp(date: dto.endDate),
            "createdAt":     Timestamp(date: dto.createdAt),
            "updatedAt":     Timestamp(date: dto.updatedAt),
            "updatedBy":     dto.updatedBy,
            "createdBy":     dto.createdBy
        ]
        
        // Optional fields – delete key when nil so Firestore stays clean
        data["childId"]          = dto.childId          ?? FieldValue.delete()
        data["notes"]            = dto.notes             ?? FieldValue.delete()
        data["location"]         = dto.location          ?? FieldValue.delete()
        data["reminderMinutes"]  = dto.reminderMinutes   ?? FieldValue.delete()
        
        try await col(familyId: dto.familyId)
            .document(dto.id)
            .setData(data, merge: true)
    }
    
    // MARK: - Soft delete
    
    func softDelete(familyId: String, eventId: String) async throws {
        try await col(familyId: familyId)
            .document(eventId)
            .updateData([
                "isDeleted": true,
                "updatedAt": Timestamp(date: Date())
            ])
    }
    
    // MARK: - Realtime listener (family-wide, no childId filter)
    
    func listen(
        familyId: String,
        onChange: @escaping ([KBCalendarEventDTO]) -> Void,
        onError:  @escaping (Error) -> Void
    ) -> ListenerRegistration {
        col(familyId: familyId)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                let dtos = snapshot?.documents.compactMap {
                    CalendarRemoteStore.parseDTO(doc: $0)
                } ?? []
                onChange(dtos)
            }
    }
    
    // MARK: - Parse
    
    static func parseDTO(doc: QueryDocumentSnapshot) -> KBCalendarEventDTO? {
        let d = doc.data()
        guard
            let id       = d["id"]       as? String,
            let familyId = d["familyId"] as? String,
            let title    = d["title"]    as? String
        else { return nil }
        
        func ts(_ key: String) -> Date? {
            (d[key] as? Timestamp)?.dateValue()
        }
        
        guard
            let startDate = ts("startDate"),
            let endDate   = ts("endDate")
        else { return nil }
        
        return KBCalendarEventDTO(
            id:              id,
            familyId:        familyId,
            childId:         d["childId"]         as? String,
            title:           title,
            notes:           d["notes"]            as? String,
            location:        d["location"]         as? String,
            startDate:       startDate,
            endDate:         endDate,
            isAllDay:        d["isAllDay"]          as? Bool   ?? false,
            categoryRaw:     d["categoryRaw"] as? String ?? KBEventCategory.family.rawValue,
            recurrenceRaw:   d["recurrenceRaw"]     as? String ?? KBEventRecurrence.none.rawValue,
            reminderMinutes: d["reminderMinutes"]   as? Int,
            isDeleted:       d["isDeleted"]         as? Bool   ?? false,
            createdAt:       ts("createdAt") ?? Date(),
            updatedAt:       ts("updatedAt") ?? Date(),
            updatedBy:       d["updatedBy"]         as? String ?? "",
            createdBy:       d["createdBy"]         as? String ?? ""
        )
    }
}
