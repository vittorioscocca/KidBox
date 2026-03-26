//
//  KidBoxContractTests.swift
//  KidBox
//
//  Created by vscocca on 26/03/26.
//

//
//  KidBoxContractTests.swift
//  KidBoxTests
//
//  Test sui CONTRATTI tra componenti — non sulla logica interna delle classi.
//  Questi test catturano regressioni involontarie su scenari critici per il business.
//
//  Scenari coperti:
//  1. Join famiglia: un documento cifrato dal membro A può essere decifrato dal membro B
//     dopo aver ricevuto la chiave tramite il flusso QR (InviteWrapService + JoinWrapService).
//  2. Sync offline → online: un'entità creata offline finisce nell'outbox con stato corretto.
//  3. Limite AI: il gate lato app blocca correttamente Free e permette Pro/Max.
//

import XCTest
import CryptoKit
import SwiftData
@testable import KidBox

// MARK: - ─────────────────────────────────────────────────────────────────────
// SCENARIO 1: Join famiglia — contratto crittografico end-to-end
//
// Regressione che cattura:
// - Qualcuno cambia il formato del QR payload → parse fallisce silenziosamente
// - Qualcuno cambia l'HKDF info string → la chiave derivata è diversa → decrypt fallisce
// - Qualcuno cambia il nonce/tag handling → unwrap fallisce
// - Membro B non riesce a decifrare documenti cifrati da Membro A
// ─────────────────────────────────────────────────────────────────────────────

final class JoinFamilyCryptoContractTests: XCTestCase {
    
    private let familyId = "contract-test-family-\(UUID().uuidString)"
    private let memberAUserId = "member-a"
    private let memberBUserId = "member-b"
    
    override func tearDown() {
        super.tearDown()
        // Cleanup Keychain
        let dummy = SymmetricKey(size: .bits256)
        try? FamilyKeychainStore.saveFamilyKey(dummy, familyId: familyId, userId: memberAUserId)
        try? FamilyKeychainStore.saveFamilyKey(dummy, familyId: familyId, userId: memberBUserId)
    }
    
    // MARK: - Contratto principale
    
    /// Simula esattamente il flusso reale:
    /// 1. Membro A crea la famiglia e ha la master key in Keychain
    /// 2. Membro A cifra un documento
    /// 3. Membro A genera un invito (wrap della master key)
    /// 4. Membro B fa join usando il QR payload (unwrap della master key)
    /// 5. Membro B decifra il documento → deve ottenere lo stesso plaintext
    func test_joinFlow_memberBCanDecryptDocumentCipheredByMemberA() throws {
        // Step 1: Membro A ha la master key
        let masterKey = SymmetricKey(size: .bits256)
        try FamilyKeychainStore.saveFamilyKey(masterKey, familyId: familyId, userId: memberAUserId)
        
        // Step 2: Membro A cifra un referto medico
        let sensitiveDocument = "Diagnosi: tutto ok. Terapia: vitamina D 400 UI/die.".data(using: .utf8)!
        let encrypted = try DocumentCryptoService.encrypt(sensitiveDocument,
                                                          familyId: familyId,
                                                          userId: memberAUserId)
        
        // Step 3: Membro A genera l'invito (simula InviteWrapService)
        let secret = InviteCrypto.randomBytes(32)
        let salt   = InviteCrypto.randomBytes(16)
        let wrapKey = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
        let wrapped = try InviteCrypto.wrapFamilyKey(familyKey: masterKey, wrapKey: wrapKey)
        
        // Quello che va su Firestore (NO secret)
        let saltB64   = salt.base64EncodedString()
        let cipherB64 = wrapped.cipher.base64EncodedString()
        let nonceB64  = wrapped.nonce.base64EncodedString()
        let tagB64    = wrapped.tag.base64EncodedString()
        
        // QR payload con secret (non va su Firestore)
        let secretB64url = secret.base64url()
        let qrPayload = "kidbox://join?familyId=\(familyId)&inviteId=test-invite&secret=\(secretB64url)"
        
        // Step 4: Membro B scansiona il QR (simula JoinWrapService)
        let parsed = JoinWrapService().parse(payload: qrPayload)
        XCTAssertNotNil(parsed, "Il QR payload deve essere parseable")
        
        let recoveredSecret = parsed!.secret
        let recoveredSalt   = Data(base64Encoded: saltB64)!
        let recoveredCipher = Data(base64Encoded: cipherB64)!
        let recoveredNonce  = Data(base64Encoded: nonceB64)!
        let recoveredTag    = Data(base64Encoded: tagB64)!
        
        let recoveredWrapKey = InviteCrypto.deriveWrapKey(secret: recoveredSecret,
                                                          salt: recoveredSalt,
                                                          familyId: familyId)
        let recoveredMasterKey = try InviteCrypto.unwrapFamilyKey(cipher: recoveredCipher,
                                                                  nonce: recoveredNonce,
                                                                  tag: recoveredTag,
                                                                  wrapKey: recoveredWrapKey)
        // Membro B salva la chiave in Keychain
        try FamilyKeychainStore.saveFamilyKey(recoveredMasterKey, familyId: familyId, userId: memberBUserId)
        
        // Step 5: Membro B decifra il documento
        let decrypted = try DocumentCryptoService.decrypt(encrypted,
                                                          familyId: familyId,
                                                          userId: memberBUserId)
        
        XCTAssertEqual(sensitiveDocument, decrypted,
                       "Membro B deve poter decifrare documenti cifrati da Membro A dopo il join")
    }
    
    // MARK: - Contratto: secret sbagliato → join fallisce
    
    func test_joinFlow_wrongSecret_cannotDecrypt() throws {
        let masterKey = SymmetricKey(size: .bits256)
        try FamilyKeychainStore.saveFamilyKey(masterKey, familyId: familyId, userId: memberAUserId)
        
        let secret  = InviteCrypto.randomBytes(32)
        let salt    = InviteCrypto.randomBytes(16)
        let wrapKey = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
        let wrapped = try InviteCrypto.wrapFamilyKey(familyKey: masterKey, wrapKey: wrapKey)
        
        // Membro B usa un secret diverso (QR sbagliato o manomesso)
        let wrongSecret  = InviteCrypto.randomBytes(32)
        let wrongWrapKey = InviteCrypto.deriveWrapKey(secret: wrongSecret, salt: salt, familyId: familyId)
        
        XCTAssertThrowsError(
            try InviteCrypto.unwrapFamilyKey(cipher: wrapped.cipher,
                                             nonce: wrapped.nonce,
                                             tag: wrapped.tag,
                                             wrapKey: wrongWrapKey),
            "Un secret sbagliato deve impedire il join"
        )
    }
    
    // MARK: - Contratto: QR parse — tutti i campi obbligatori
    
    func test_joinFlow_qrParse_validPayload_succeeds() {
        let secret = InviteCrypto.randomBytes(32).base64url()
        let qr = "kidbox://join?familyId=fam-123&inviteId=inv-456&secret=\(secret)"
        let parsed = JoinWrapService().parse(payload: qr)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.familyId, "fam-123")
        XCTAssertEqual(parsed?.inviteId, "inv-456")
    }
    
    func test_joinFlow_qrParse_missingSecret_returnsNil() {
        let qr = "kidbox://join?familyId=fam-123&inviteId=inv-456"
        XCTAssertNil(JoinWrapService().parse(payload: qr),
                     "QR senza secret deve essere rifiutato")
    }
    
    func test_joinFlow_qrParse_wrongScheme_returnsNil() {
        let secret = InviteCrypto.randomBytes(32).base64url()
        let qr = "https://join?familyId=fam-123&inviteId=inv-456&secret=\(secret)"
        XCTAssertNil(JoinWrapService().parse(payload: qr),
                     "QR con schema non kidbox deve essere rifiutato")
    }
    
    func test_joinFlow_qrParse_invalidBase64url_returnsNil() {
        let qr = "kidbox://join?familyId=fam-123&inviteId=inv-456&secret=INVALID!!!"
        XCTAssertNil(JoinWrapService().parse(payload: qr))
    }
}

// MARK: - ─────────────────────────────────────────────────────────────────────
// SCENARIO 2: Sync offline → online — contratto outbox
//
// Regressione che cattura:
// - enqueueVaccineUpsert non crea il KBSyncOp → l'entità non viene mai sincronizzata
// - Il KBSyncOp ha entityType o opType sbagliato → processVaccine non lo riconosce
// - Due upsert sullo stesso vaccino creano due op invece di una → doppio sync
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SyncOfflineOutboxContractTests: XCTestCase {
    
    var context: ModelContext!
    var sync: SyncCenter!
    
    override func setUp() {
        super.setUp()
        context = try? makeTestContext()
        sync = SyncCenter.shared
    }
    
    private func makeTestContext() throws -> ModelContext {
        let schema = Schema([KBVaccine.self, KBMedicalVisit.self, KBSyncOp.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }
    
    // MARK: - Contratto: enqueue crea un KBSyncOp
    
    func test_enqueueVaccineUpsert_createsOutboxOp() throws {
        let vaccine = KBVaccine.make(id: "v-offline-1", familyId: "fam-1", childId: "child-1")
        context.insert(vaccine)
        try context.save()
        
        sync.enqueueVaccineUpsert(vaccineId: "v-offline-1", familyId: "fam-1", modelContext: context)
        
        let ops = try context.fetch(FetchDescriptor<KBSyncOp>())
        XCTAssertEqual(ops.count, 1, "enqueue deve creare esattamente 1 KBSyncOp")
        XCTAssertEqual(ops.first?.entityId, "v-offline-1")
        XCTAssertEqual(ops.first?.opType, "upsert")
        XCTAssertEqual(ops.first?.entityTypeRaw, SyncEntityType.vaccine.rawValue,
                       "Il tipo entità deve essere 'vaccine'")
        XCTAssertEqual(ops.first?.familyId, "fam-1")
    }
    
    // MARK: - Contratto: due enqueue sullo stesso vaccino → una sola op (idempotenza)
    
    func test_enqueueVaccineUpsert_twice_onlyOneOp() throws {
        let vaccine = KBVaccine.make(id: "v-offline-2", familyId: "fam-1", childId: "child-1")
        context.insert(vaccine)
        try context.save()
        
        sync.enqueueVaccineUpsert(vaccineId: "v-offline-2", familyId: "fam-1", modelContext: context)
        sync.enqueueVaccineUpsert(vaccineId: "v-offline-2", familyId: "fam-1", modelContext: context)
        
        let ops = try context.fetch(FetchDescriptor<KBSyncOp>())
        XCTAssertEqual(ops.count, 1,
                       "Due enqueue sullo stesso vaccino devono produrre una sola op (upsertOp è idempotente)")
    }
    
    // MARK: - Contratto: enqueue visita
    
    func test_enqueueVisitUpsert_createsOutboxOp() throws {
        let visit = KBMedicalVisit.make(id: "visit-offline-1", familyId: "fam-1")
        context.insert(visit)
        try context.save()
        
        sync.enqueueVisitUpsert(visitId: "visit-offline-1", familyId: "fam-1", modelContext: context)
        
        let ops = try context.fetch(FetchDescriptor<KBSyncOp>())
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.entityTypeRaw, SyncEntityType.visit.rawValue)
        XCTAssertEqual(ops.first?.opType, "upsert")
    }
    
    // MARK: - Contratto: delete enqueue
    
    func test_enqueueVaccineDelete_createsDeleteOp() throws {
        sync.enqueueVaccineDelete(vaccineId: "v-to-delete", familyId: "fam-1", modelContext: context)
        
        let ops = try context.fetch(FetchDescriptor<KBSyncOp>())
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.opType, "delete")
        XCTAssertEqual(ops.first?.entityId, "v-to-delete")
    }
    
    // MARK: - Contratto: upsert dopo delete → rimane delete (LWW outbox)
    
    func test_enqueueUpsertAfterDelete_keepsLatestOp() throws {
        sync.enqueueVaccineDelete(vaccineId: "v-conflict", familyId: "fam-1", modelContext: context)
        sync.enqueueVaccineUpsert(vaccineId: "v-conflict", familyId: "fam-1", modelContext: context)
        
        let ops = try context.fetch(FetchDescriptor<KBSyncOp>(
            predicate: #Predicate { $0.entityId == "v-conflict" }
        ))
        XCTAssertEqual(ops.count, 1, "Deve esserci una sola op per entità")
        // L'ultima operazione vince — upsertOp sostituisce sempre
        XCTAssertEqual(ops.first?.opType, "upsert",
                       "L'ultima enqueue (upsert) deve sovrascrivere la delete precedente")
    }
}

// MARK: - ─────────────────────────────────────────────────────────────────────
// SCENARIO 3: Limite AI — contratto gate lato app
//
// Regressione che cattura:
// - KBPlan.free.includesAI diventa true per errore → utenti free accedono all'AI
// - KBPlan.pro.aiDailyLimit viene cambiato → impatto sui ricavi
// - KBPlan.max.aiDailyLimit viene cambiato → impatto sui ricavi
// - storageQuota di un piano viene ridotta inavvertitamente
// ─────────────────────────────────────────────────────────────────────────────

final class AIGateContractTests: XCTestCase {
    
    // MARK: - Contratto: Free non include AI
    
    func test_freePlan_doesNotIncludeAI() {
        XCTAssertFalse(KBPlan.free.includesAI,
                       "CRITICO: il piano Free NON deve includere l'AI — impatto diretto sui ricavi")
    }
    
    // MARK: - Contratto: Pro e Max includono AI
    
    func test_proPlan_includesAI() {
        XCTAssertTrue(KBPlan.pro.includesAI)
    }
    
    func test_maxPlan_includesAI() {
        XCTAssertTrue(KBPlan.max.includesAI)
    }
    
    // MARK: - Contratto: limiti giornalieri AI esatti
    
    func test_freePlan_aiDailyLimit_isZero() {
        XCTAssertEqual(KBPlan.free.aiDailyLimit, 0,
                       "CRITICO: Free deve avere 0 messaggi AI/giorno")
    }
    
    func test_proPlan_aiDailyLimit_is30() {
        XCTAssertEqual(KBPlan.pro.aiDailyLimit, 30,
                       "CRITICO: Pro deve avere 30 messaggi AI/giorno — allineato con la Cloud Function")
    }
    
    func test_maxPlan_aiDailyLimit_is100() {
        XCTAssertEqual(KBPlan.max.aiDailyLimit, 100,
                       "CRITICO: Max deve avere 100 messaggi AI/giorno — allineato con la Cloud Function")
    }
    
    // MARK: - Contratto: storage quota esatte
    
    func test_freePlan_storageQuota_is200MB() {
        let expected: Int64 = 200 * 1024 * 1024
        XCTAssertEqual(KBPlan.free.storageQuota, expected,
                       "Free deve avere 200 MB di storage")
    }
    
    func test_proPlan_storageQuota_is5GB() {
        let expected: Int64 = 5 * 1024 * 1024 * 1024
        XCTAssertEqual(KBPlan.pro.storageQuota, expected,
                       "Pro deve avere 5 GB di storage")
    }
    
    func test_maxPlan_storageQuota_is20GB() {
        let expected: Int64 = 20 * 1024 * 1024 * 1024
        XCTAssertEqual(KBPlan.max.storageQuota, expected,
                       "Max deve avere 20 GB di storage")
    }
    
    // MARK: - Contratto: gerarchia dei piani (max > pro > free)
    
    func test_planHierarchy_maxStorageGreaterThanPro() {
        XCTAssertGreaterThan(KBPlan.max.storageQuota, KBPlan.pro.storageQuota)
    }
    
    func test_planHierarchy_proStorageGreaterThanFree() {
        XCTAssertGreaterThan(KBPlan.pro.storageQuota, KBPlan.free.storageQuota)
    }
    
    func test_planHierarchy_maxAILimitGreaterThanPro() {
        XCTAssertGreaterThan(KBPlan.max.aiDailyLimit, KBPlan.pro.aiDailyLimit)
    }
    
    // MARK: - Contratto: productId corretti (cambiarli rompe gli acquisti)
    
    func test_proPlan_productId_isCorrect() {
        XCTAssertEqual(KBPlan.pro.productId, "it.vittorioscocca.kidbox.pro.monthly",
                       "CRITICO: productId sbagliato rompe gli acquisti su App Store")
    }
    
    func test_maxPlan_productId_isCorrect() {
        XCTAssertEqual(KBPlan.max.productId, "it.vittorioscocca.kidbox.max.monthly",
                       "CRITICO: productId sbagliato rompe gli acquisti su App Store")
    }
    
    func test_freePlan_productId_isNil() {
        XCTAssertNil(KBPlan.free.productId, "Free non deve avere un productId")
    }
    
    // MARK: - Contratto: rawValue allineato con Cloud Function e Firestore
    
    func test_planRawValues_alignedWithBackend() {
        // La Cloud Function legge families/{familyId}.plan come stringa
        // Se questi rawValue cambiano, il backend non riconosce più il piano
        XCTAssertEqual(KBPlan.free.rawValue, "free",
                       "CRITICO: rawValue 'free' deve restare invariato — usato da Cloud Functions e Firestore")
        XCTAssertEqual(KBPlan.pro.rawValue,  "pro",
                       "CRITICO: rawValue 'pro' deve restare invariato")
        XCTAssertEqual(KBPlan.max.rawValue,  "max",
                       "CRITICO: rawValue 'max' deve restare invariato")
    }
}
