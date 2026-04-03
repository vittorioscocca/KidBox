//
//  KidBoxSyncTests.swift
//  KidBoxTests
//
//  Test per la logica LWW (Last-Write-Wins) di SyncCenter+Vaccines e SyncCenter+Visits.
//  Questi test usano un ModelContainer in-memory — nessun Firebase coinvolto.
//

import XCTest
import SwiftData
@testable import KidBox

// MARK: - Helpers

private func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([
        KBVaccine.self,
        KBMedicalVisit.self,
        KBSyncOp.self
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    return ModelContext(container)
}

// MARK: - SyncCenter Vaccines LWW Tests

@MainActor
final class SyncCenterVaccinesTests: XCTestCase {
    
    var context: ModelContext!
    var sync: SyncCenter!
    
    override func setUp() {
        super.setUp()
        context = try? makeInMemoryContext()
        sync = SyncCenter.shared
    }
    
    func test_applyVaccinesInbound_insertsNewVaccine() throws {
        let dto = RemoteVaccineDTO.make(id: "v-001",
                                        familyId: "fam-1",
                                        childId: "child-1",
                                        vaccineType: "morbillo",
                                        status: "administered",
                                        updatedAt: Date())
        
        sync.applyVaccinesInbound(changes: [.upsert(dto)], modelContext: context)
        
        let vaccines = try context.fetch(FetchDescriptor<KBVaccine>())
        XCTAssertEqual(vaccines.count, 1)
        XCTAssertEqual(vaccines.first?.id, "v-001")
        XCTAssertEqual(vaccines.first?.syncState, .synced)
    }
    
    // MARK: - LWW: remoto più recente sovrascrive locale
    
    func test_applyVaccinesInbound_remoteWins_whenRemoteIsNewer() throws {
        // Inserisci locale con timestamp vecchio
        let local = KBVaccine.make(id: "v-002",
                                   familyId: "fam-1",
                                   childId: "child-1",
                                   notes: "nota locale",
                                   updatedAt: Date(timeIntervalSinceNow: -3600)) // 1 ora fa
        context.insert(local)
        try context.save()
        
        // Remoto più recente con note diverse
        let dto = RemoteVaccineDTO.make(id: "v-002",
                                        familyId: "fam-1",
                                        childId: "child-1",
                                        notes: "nota remota aggiornata",
                                        updatedAt: Date()) // adesso
        
        sync.applyVaccinesInbound(changes: [.upsert(dto)], modelContext: context)
        
        let fetched = try context.fetch(FetchDescriptor<KBVaccine>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.notes, "nota remota aggiornata", "Il remoto più recente deve vincere")
    }
    
    // MARK: - LWW: locale più recente NON viene sovrascritto
    
    func test_applyVaccinesInbound_localWins_whenLocalIsNewer() throws {
        let localDate = Date() // adesso
        let local = KBVaccine.make(id: "v-003",
                                   familyId: "fam-1",
                                   childId: "child-1",
                                   notes: "nota locale recente",
                                   updatedAt: localDate)
        context.insert(local)
        try context.save()
        
        // Remoto con timestamp più vecchio
        let dto = RemoteVaccineDTO.make(id: "v-003",
                                        familyId: "fam-1",
                                        childId: "child-1",
                                        notes: "nota remota vecchia",
                                        updatedAt: Date(timeIntervalSinceNow: -3600))
        
        sync.applyVaccinesInbound(changes: [.upsert(dto)], modelContext: context)
        
        let fetched = try context.fetch(FetchDescriptor<KBVaccine>())
        XCTAssertEqual(fetched.first?.notes, "nota locale recente", "Il locale più recente NON deve essere sovrascritto")
    }
    
    
    // MARK: - Soft delete remoto
    
    func test_applyVaccinesInbound_remoteSoftDelete_removesLocal() throws {
        let local = KBVaccine.make(id: "v-005", familyId: "fam-1", childId: "child-1")
        context.insert(local)
        try context.save()
        
        let dto = RemoteVaccineDTO.make(id: "v-005",
                                        familyId: "fam-1",
                                        childId: "child-1",
                                        isDeleted: true,
                                        updatedAt: Date())
        
        sync.applyVaccinesInbound(changes: [.upsert(dto)], modelContext: context)
        
        let fetched = try context.fetch(FetchDescriptor<KBVaccine>())
        XCTAssertTrue(fetched.isEmpty, "Un soft delete remoto deve eliminare il record locale")
    }
    
    // MARK: - Remove event
    
    func test_applyVaccinesInbound_removeChange_deletesLocal() throws {
        let local = KBVaccine.make(id: "v-006", familyId: "fam-1", childId: "child-1")
        context.insert(local)
        try context.save()
        
        sync.applyVaccinesInbound(changes: [.remove("v-006")], modelContext: context)
        
        let fetched = try context.fetch(FetchDescriptor<KBVaccine>())
        XCTAssertTrue(fetched.isEmpty)
    }
    
    // MARK: - Multiple changes
    
    func test_applyVaccinesInbound_multipleChanges_appliedCorrectly() throws {
        let dto1 = RemoteVaccineDTO.make(id: "v-010", familyId: "fam-1", childId: "child-1", updatedAt: Date())
        let dto2 = RemoteVaccineDTO.make(id: "v-011", familyId: "fam-1", childId: "child-1", updatedAt: Date())
        let dto3 = RemoteVaccineDTO.make(id: "v-012", familyId: "fam-1", childId: "child-1", updatedAt: Date())
        
        sync.applyVaccinesInbound(changes: [.upsert(dto1), .upsert(dto2), .upsert(dto3)],
                                  modelContext: context)
        
        let fetched = try context.fetch(FetchDescriptor<KBVaccine>())
        XCTAssertEqual(fetched.count, 3)
    }
}

// MARK: - SyncCenter Visits LWW Tests

@MainActor
final class SyncCenterVisitsTests: XCTestCase {
    
    var context: ModelContext!
    var sync: SyncCenter!
    
    override func setUp() {
        super.setUp()
        context = try? makeInMemoryContext()
        sync = SyncCenter.shared
    }
    
    func test_applyVisitsInbound_insertsNewVisit() throws {
        let dto = RemoteVisitDTO.make(id: "visit-001",
                                      familyId: "fam-1",
                                      childId: "child-1",
                                      updatedAt: Date())
        
        sync.applyVisitsInbound(changes: [.upsert(dto)], modelContext: context)
        
        let visits = try context.fetch(FetchDescriptor<KBMedicalVisit>())
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits.first?.id, "visit-001")
    }
    
    func test_applyVisitsInbound_remoteWins_whenRemoteIsNewer() throws {
        let local = KBMedicalVisit.make(id: "visit-002",
                                        familyId: "fam-1",
                                        diagnosis: "diagnosi locale",
                                        updatedAt: Date(timeIntervalSinceNow: -3600))
        context.insert(local)
        try context.save()
        
        let dto = RemoteVisitDTO.make(id: "visit-002",
                                      familyId: "fam-1",
                                      diagnosis: "diagnosi aggiornata",
                                      updatedAt: Date())
        
        sync.applyVisitsInbound(changes: [.upsert(dto)], modelContext: context)
        
        let fetched = try context.fetch(FetchDescriptor<KBMedicalVisit>())
        XCTAssertEqual(fetched.first?.diagnosis, "diagnosi aggiornata")
    }
    
    func test_applyVisitsInbound_localWins_whenLocalIsNewer() throws {
        let local = KBMedicalVisit.make(id: "visit-003",
                                        familyId: "fam-1",
                                        diagnosis: "diagnosi locale recente",
                                        updatedAt: Date())
        context.insert(local)
        try context.save()
        
        let dto = RemoteVisitDTO.make(id: "visit-003",
                                      familyId: "fam-1",
                                      diagnosis: "diagnosi remota vecchia",
                                      updatedAt: Date(timeIntervalSinceNow: -3600))
        
        sync.applyVisitsInbound(changes: [.upsert(dto)], modelContext: context)
        
        let fetched = try context.fetch(FetchDescriptor<KBMedicalVisit>())
        XCTAssertEqual(fetched.first?.diagnosis, "diagnosi locale recente")
    }
    
    func test_applyVisitsInbound_softDelete_removesLocal() throws {
        let local = KBMedicalVisit.make(id: "visit-004", familyId: "fam-1")
        context.insert(local)
        try context.save()
        
        let dto = RemoteVisitDTO.make(id: "visit-004",
                                      familyId: "fam-1",
                                      isDeleted: true,
                                      updatedAt: Date())
        
        sync.applyVisitsInbound(changes: [.upsert(dto)], modelContext: context)
        
        let fetched = try context.fetch(FetchDescriptor<KBMedicalVisit>())
        XCTAssertTrue(fetched.isEmpty)
    }
}

// MARK: - Test Factories (DTO & Model helpers)

extension RemoteVaccineDTO {
    static func make(id: String,
                     familyId: String,
                     childId: String,
                     vaccineType: String = "altro",
                     status: String = "administered",
                     notes: String? = nil,
                     isDeleted: Bool = false,
                     updatedAt: Date = Date()) -> RemoteVaccineDTO {
        RemoteVaccineDTO(
            id: id,
            familyId: familyId,
            childId: childId,
            vaccineTypeRaw: vaccineType,
            statusRaw: status,
            commercialName: nil,
            doseNumber: 1,
            totalDoses: 1,
            administeredDate: nil,
            scheduledDate: nil,
            lotNumber: nil,
            administeredBy: nil,
            administrationSiteRaw: nil,
            notes: notes,
            isDeleted: isDeleted,
            createdAt: Date(),
            updatedAt: updatedAt,
            updatedBy: "test-user",
            createdBy: "test-user"
        )
    }
}

extension KBVaccine {
    static func make(id: String,
                     familyId: String,
                     childId: String,
                     notes: String? = nil,
                     isDeleted: Bool = false,
                     syncState: KBSyncState = .synced,
                     updatedAt: Date = Date()) -> KBVaccine {
        let v = KBVaccine(
            id: id,
            familyId: familyId,
            childId: childId,
            vaccineType: .altro,
            status: .administered,
            notes: notes,
            isDeleted: isDeleted,
            updatedAt: updatedAt
        )
        v.syncStateRaw = syncState.rawValue
        return v
    }
}

extension RemoteVisitDTO {
    static func make(id: String,
                     familyId: String,
                     childId: String = "child-1",
                     diagnosis: String? = nil,
                     isDeleted: Bool = false,
                     updatedAt: Date = Date()) -> RemoteVisitDTO {
        RemoteVisitDTO(
            id: id,
            familyId: familyId,
            childId: childId,
            date: Date(),
            doctorName: nil,
            doctorSpecializationRaw: nil,
            travelDetailsData: nil,
            reason: "",
            diagnosis: diagnosis,
            recommendations: nil,
            linkedTreatmentIds: [],
            linkedExamIds: [],
            asNeededDrugsData: nil,
            therapyTypesRaw: [],
            prescribedExamsData: nil,
            photoURLs: [],
            notes: nil,
            nextVisitDate: nil,
            nextVisitReason: nil,
            isDeleted: isDeleted,
            createdBy: "test-user",
            updatedBy: "test-user",
            createdAt: Date(),
            updatedAt: updatedAt
        )
    }
}

extension KBMedicalVisit {
    static func make(id: String,
                     familyId: String,
                     childId: String = "child-1",
                     diagnosis: String? = nil,
                     updatedAt: Date = Date()) -> KBMedicalVisit {
        let v = KBMedicalVisit(id: id,
                               familyId: familyId,
                               childId: childId,
                               date: Date(),
                               updatedAt: updatedAt)
        v.diagnosis = diagnosis
        return v
    }
}
