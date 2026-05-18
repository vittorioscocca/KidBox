//
//  TripRemoteStore.swift
//  KidBox
//
//  Push viaggi su Firestore + listener inbound per sync cross-device.
//

import Foundation
import FirebaseFirestore
import OSLog
import SwiftData

final class TripRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    // MARK: - Outbound

    func syncTrip(
        _ trip: KBTrip,
        legs legsOverride: [KBTripLeg]? = nil,
        dayPlans dayPlansOverride: [KBTripDayPlan]? = nil,
        packingItems packingItemsOverride: [KBPackingItem]? = nil
    ) async {
        let tripRef = db.collection("families").document(trip.familyId)
            .collection("trips").document(trip.id)

        do {
            let tripLegs = legsOverride ?? trip.legs
            let tripDayPlans = dayPlansOverride ?? trip.dayPlans
            let tripPackingItems = packingItemsOverride ?? trip.packingItems

            for leg in tripLegs {
                try await tripRef.collection("legs").document(leg.id).setData([
                    "order": leg.order,
                    "fromLocation": leg.fromLocation,
                    "toLocation": leg.toLocation,
                    "transportMode": leg.transportModeRaw,
                    "notes": leg.notes as Any,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], merge: true)
            }

            for day in tripDayPlans {
                try await tripRef.collection("dayPlans").document(day.id).setData([
                    "date": day.dateString,
                    "location": day.location,
                    "morningPlan": day.morningPlan,
                    "afternoonPlan": day.afternoonPlan,
                    "eveningPlan": day.eveningPlan,
                    "accommodationName": day.accommodationName as Any,
                    "accommodationType": day.accommodationType as Any,
                    "accommodationCostPerNight": day.accommodationCostPerNight as Any,
                    "weatherBackupPlan": day.weatherBackupPlan as Any,
                    "estimatedDailyCost": day.estimatedDailyCost as Any,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], merge: true)
            }

            for item in tripPackingItems {
                try await tripRef.collection("packingItems").document(item.id).setData([
                    "label": item.label,
                    "category": item.categoryRaw,
                    "isChecked": item.isChecked,
                    "isAIGenerated": item.isAIGenerated,
                    "fromMedicalProfile": item.fromMedicalProfile,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], merge: true)
            }

            // Scrivi il documento principale per ultimo: il listener sui trips
            // usa questa modifica per ricaricare anche le subcollection.
            // Se il root arrivasse prima, potrebbe rileggere vecchi dayPlans.
            try await tripRef.setData([
                "name": trip.name,
                "startDate": Timestamp(date: trip.startDate),
                "endDate": Timestamp(date: trip.endDate),
                "participantIdsJson": trip.participantIdsJson,
                "budgetTotal": trip.budgetTotal,
                "currency": trip.currency,
                "status": trip.statusRaw,
                "aiProposalJson": trip.aiProposalJson as Any,
                "photoAlbumId": trip.photoAlbumId as Any,
                "notesNoteId": trip.notesNoteId as Any,
                "todoListId": trip.todoListId as Any,
                "createdBy": trip.createdBy,
                "updatedBy": trip.updatedBy,
                "createdAt": Timestamp(date: trip.createdAt),
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)

            KBLog.sync.kbInfo("TripRemoteStore: synced tripId=\(trip.id)")
        } catch {
            KBLog.sync.kbError("TripRemoteStore: sync failed \(error.localizedDescription)")
        }
    }

    // MARK: - Inbound

    func listenTrips(
        familyId: String,
        modelContext: ModelContext,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families")
            .document(familyId)
            .collection("trips")
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let self, let snapshot else { return }
                Task { @MainActor in
                    do {
                        try await self.applyTripsSnapshot(
                            snapshot: snapshot,
                            familyId: familyId,
                            modelContext: modelContext
                        )
                    } catch {
                        KBLog.sync.kbError("TripRemoteStore: inbound apply failed \(error.localizedDescription)")
                        onError(error)
                    }
                }
            }
    }

    func deleteTrip(_ trip: KBTrip, modelContext: ModelContext) async {
        do {
            try await deleteTripRemote(trip)
        } catch {
            KBLog.sync.kbError("TripRemoteStore: remote delete failed \(error.localizedDescription)")
        }
        deleteTripLocally(trip, modelContext: modelContext)
        try? modelContext.save()
    }

    private func deleteTripRemote(_ trip: KBTrip) async throws {
        let tripRef = db.collection("families")
            .document(trip.familyId)
            .collection("trips")
            .document(trip.id)

        try await deleteCollection(tripRef.collection("legs"))
        try await deleteCollection(tripRef.collection("dayPlans"))
        try await deleteCollection(tripRef.collection("packingItems"))
        try await deleteCollection(tripRef.collection("expenses"))
        try await tripRef.delete()
    }

    private func deleteCollection(_ collection: CollectionReference) async throws {
        let snap = try await collection.getDocuments()
        for doc in snap.documents {
            try await doc.reference.delete()
        }
    }

    @MainActor
    private func deleteTripLocally(_ trip: KBTrip, modelContext: ModelContext) {
        modelContext.delete(trip)
    }

    @MainActor
    private func applyTripsSnapshot(
        snapshot: QuerySnapshot,
        familyId: String,
        modelContext: ModelContext
    ) async throws {
        if !snapshot.documentChanges.isEmpty {
            for change in snapshot.documentChanges {
                switch change.type {
                case .removed:
                    let tripId = change.document.documentID
                    let descriptor = FetchDescriptor<KBTrip>(predicate: #Predicate { $0.id == tripId })
                    if let existing = try? modelContext.fetch(descriptor).first {
                        modelContext.delete(existing)
                    }
                default:
                    guard let inbound = decodeTrip(doc: change.document, familyId: familyId) else { continue }
                    let trip = upsertTrip(inbound, modelContext: modelContext)
                    try await syncSubcollections(
                        trip: trip,
                        familyId: familyId,
                        modelContext: modelContext
                    )
                    KBLog.sync.kbInfo(
                        "TripRemoteStore: inbound \(String(describing: change.type)) tripId=\(trip.id) familyId=\(familyId)"
                    )
                }
            }
            try modelContext.save()
            return
        }

        var remoteIds = Set<String>()
        for doc in snapshot.documents {
            guard let inbound = decodeTrip(doc: doc, familyId: familyId) else { continue }
            remoteIds.insert(inbound.id)
            let trip = upsertTrip(inbound, modelContext: modelContext)
            try await syncSubcollections(
                trip: trip,
                familyId: familyId,
                modelContext: modelContext
            )
        }

        if !snapshot.metadata.isFromCache {
            let localDescriptor = FetchDescriptor<KBTrip>(predicate: #Predicate { $0.familyId == familyId })
            let localTrips = (try? modelContext.fetch(localDescriptor)) ?? []
            for trip in localTrips where !remoteIds.contains(trip.id) {
                modelContext.delete(trip)
            }
        }

        try modelContext.save()
    }

    @MainActor
    private func upsertTrip(_ inbound: KBTrip, modelContext: ModelContext) -> KBTrip {
        let tripId = inbound.id
        let descriptor = FetchDescriptor<KBTrip>(predicate: #Predicate { $0.id == tripId })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.familyId = inbound.familyId
            existing.name = inbound.name
            existing.startDate = inbound.startDate
            existing.endDate = inbound.endDate
            existing.participantIdsJson = inbound.participantIdsJson
            existing.budgetTotal = inbound.budgetTotal
            existing.currency = inbound.currency
            existing.statusRaw = inbound.statusRaw
            existing.aiProposalJson = inbound.aiProposalJson
            existing.photoAlbumId = inbound.photoAlbumId
            existing.notesNoteId = inbound.notesNoteId
            existing.todoListId = inbound.todoListId
            existing.updatedBy = inbound.updatedBy
            existing.updatedAt = inbound.updatedAt
            return existing
        }
        modelContext.insert(inbound)
        return inbound
    }

    @MainActor
    private func syncSubcollections(
        trip: KBTrip,
        familyId: String,
        modelContext: ModelContext
    ) async throws {
        let tripRef = db.collection("families")
            .document(familyId)
            .collection("trips")
            .document(trip.id)

        let legsSnap = try await tripRef.collection("legs").getDocuments()
        let inboundLegs = legsSnap.documents.compactMap { decodeLeg(doc: $0, familyId: familyId, tripId: trip.id) }
        if !inboundLegs.isEmpty {
            replaceLegs(for: trip, with: inboundLegs, modelContext: modelContext)
        }

        let daySnap = try await tripRef.collection("dayPlans").getDocuments()
        let inboundDays = daySnap.documents.compactMap { decodeDayPlan(doc: $0, familyId: familyId, tripId: trip.id) }
        if !inboundDays.isEmpty {
            replaceDayPlans(for: trip, with: inboundDays, modelContext: modelContext)
        }

        let packingSnap = try await tripRef.collection("packingItems").getDocuments()
        let inboundPacking = packingSnap.documents.compactMap {
            decodePackingItem(doc: $0, familyId: familyId, tripId: trip.id)
        }
        if !inboundPacking.isEmpty {
            replacePackingItems(for: trip, with: inboundPacking, modelContext: modelContext)
        }
    }

    @MainActor
    private func replaceLegs(
        for trip: KBTrip,
        with inbound: [KBTripLeg],
        modelContext: ModelContext
    ) {
        for leg in trip.legs {
            modelContext.delete(leg)
        }
        trip.legs = inbound
    }

    @MainActor
    private func replaceDayPlans(
        for trip: KBTrip,
        with inbound: [KBTripDayPlan],
        modelContext: ModelContext
    ) {
        for day in trip.dayPlans {
            modelContext.delete(day)
        }
        trip.dayPlans = inbound.sorted { $0.dateString < $1.dateString }
    }

    @MainActor
    private func replacePackingItems(
        for trip: KBTrip,
        with inbound: [KBPackingItem],
        modelContext: ModelContext
    ) {
        for item in trip.packingItems {
            modelContext.delete(item)
        }
        trip.packingItems = inbound
    }

    // MARK: - Decode

    private func decodeTrip(doc: QueryDocumentSnapshot, familyId: String) -> KBTrip? {
        let data = doc.data()
        guard let start = firestoreDate(data["startDate"]),
              let end = firestoreDate(data["endDate"]) else {
            KBLog.sync.kbError(
                "TripRemoteStore: skip tripId=\(doc.documentID) invalid/missing startDate or endDate"
            )
            return nil
        }

        let trip = KBTrip(
            id: doc.documentID,
            familyId: familyId,
            name: data["name"] as? String ?? "",
            startDate: start,
            endDate: end,
            participantIdsJson: data["participantIdsJson"] as? String ?? "[]",
            budgetTotal: firestoreDouble(data["budgetTotal"]) ?? 0,
            currency: data["currency"] as? String ?? "EUR",
            createdBy: data["createdBy"] as? String ?? ""
        )
        trip.statusRaw = data["status"] as? String ?? TripStatus.planning.rawValue
        trip.aiProposalJson = data["aiProposalJson"] as? String
        trip.photoAlbumId = data["photoAlbumId"] as? String
        trip.notesNoteId = data["notesNoteId"] as? String
        trip.todoListId = data["todoListId"] as? String
        trip.updatedBy = data["updatedBy"] as? String ?? trip.createdBy
        trip.createdAt = firestoreDate(data["createdAt"]) ?? Date()
        trip.updatedAt = firestoreDate(data["updatedAt"]) ?? trip.createdAt
        return trip
    }

    private func firestoreDate(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    private func firestoreDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        return nil
    }

    private func firestoreInt(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        return 0
    }

    private func decodeLeg(
        doc: QueryDocumentSnapshot,
        familyId: String,
        tripId: String
    ) -> KBTripLeg? {
        let data = doc.data()
        let leg = KBTripLeg(
            id: doc.documentID,
            familyId: familyId,
            tripId: tripId,
            order: firestoreInt(data["order"]),
            fromLocation: data["fromLocation"] as? String ?? "",
            toLocation: data["toLocation"] as? String ?? "",
            transportModeRaw: data["transportMode"] as? String ?? TransportMode.car.rawValue,
            notes: data["notes"] as? String
        )
        if let updated = data["updatedAt"] as? Timestamp {
            leg.updatedAt = updated.dateValue()
        }
        return leg
    }

    private func decodeDayPlan(
        doc: QueryDocumentSnapshot,
        familyId: String,
        tripId: String
    ) -> KBTripDayPlan? {
        let data = doc.data()
        let plan = KBTripDayPlan(
            id: doc.documentID,
            familyId: familyId,
            tripId: tripId,
            dateString: data["date"] as? String ?? "",
            location: data["location"] as? String ?? "",
            morningPlan: data["morningPlan"] as? String ?? "",
            afternoonPlan: data["afternoonPlan"] as? String ?? "",
            eveningPlan: data["eveningPlan"] as? String ?? ""
        )
        plan.accommodationName = data["accommodationName"] as? String
        plan.accommodationType = data["accommodationType"] as? String
        plan.accommodationCostPerNight = firestoreDouble(data["accommodationCostPerNight"])
        plan.weatherBackupPlan = data["weatherBackupPlan"] as? String
        plan.estimatedDailyCost = firestoreDouble(data["estimatedDailyCost"])
        if let updated = data["updatedAt"] as? Timestamp {
            plan.updatedAt = updated.dateValue()
        }
        return plan
    }

    private func decodePackingItem(
        doc: QueryDocumentSnapshot,
        familyId: String,
        tripId: String
    ) -> KBPackingItem? {
        let data = doc.data()
        let item = KBPackingItem(
            id: doc.documentID,
            familyId: familyId,
            tripId: tripId,
            label: data["label"] as? String ?? "",
            categoryRaw: data["category"] as? String ?? PackingCategory.other.rawValue,
            isAIGenerated: data["isAIGenerated"] as? Bool ?? false,
            fromMedicalProfile: data["fromMedicalProfile"] as? Bool ?? false
        )
        item.isChecked = data["isChecked"] as? Bool ?? false
        if let updated = data["updatedAt"] as? Timestamp {
            item.updatedAt = updated.dateValue()
        }
        return item
    }
}
