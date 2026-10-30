//
//  KBWork.swift
//  KidBox
//

import Foundation
import SwiftData

/// La scheda «Lavoro» di un adulto: `id` è l'uid del proprietario (una sola per
/// persona), e `visibilityMemberIds` l'elenco degli altri adulti con cui la
/// condivide. Privata di default. Le rules (`workProfiles`) fanno rispettare
/// la visibilità anche a un client che la ignora; il filtro locale
/// (`isVisible(to:)`) resta per ciò che la cache ha già.
///
/// Il datore di lavoro è cifrato con la chiave di famiglia, come ogni campo
/// scritto dall'utente (`WalletCryptoService`).
@Model
final class KBWorkProfile {
    @Attribute(.unique) var id: String
    var familyId: String

    var employerEnc: String?

    /// `"private"` | `"members"`. Mai `"family"`: le rules lo rifiutano.
    var visibilityScope: String
    var visibilityMemberIds: [String]

    var createdBy: String = ""
    var createdByName: String = ""
    var updatedBy: String = ""
    var updatedByName: String = ""
    var createdAt: Date
    var updatedAt: Date

    var isDeleted: Bool
    var syncStateRaw: Int
    var lastSyncError: String?

    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    init(
        ownerUid: String,
        familyId: String,
        ownerName: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = ownerUid
        self.familyId = familyId
        self.visibilityScope = KBVisibilityScope.onlyCreator
        self.visibilityMemberIds = []
        self.createdBy = ownerUid
        self.createdByName = ownerName
        self.updatedBy = ownerUid
        self.updatedByName = ownerName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = false
        self.syncStateRaw = KBSyncState.synced.rawValue
    }

    var ownerUid: String { id }

    /// Scope effettivo: solo `private` o `members`.
    static func normalizedScope(_ raw: String?) -> String {
        raw == KBVisibilityScope.members ? KBVisibilityScope.members : KBVisibilityScope.onlyCreator
    }

    func isVisible(to currentUid: String?) -> Bool {
        guard let currentUid, !currentUid.isEmpty else { return false }
        if id == currentUid { return true }
        return Self.normalizedScope(visibilityScope) == KBVisibilityScope.members
            && visibilityMemberIds.contains(currentUid)
    }
}

extension KBWorkProfile: HasFamilyId {}

/// Una busta paga o un contratto già letti: i valori estratti stanno in
/// `fieldsEnc` (JSON di `WorkFields` cifrato con la chiave di famiglia), in
/// chiaro solo il tipo, la data di riferimento e il puntatore al file.
@Model
final class KBWorkRecord {
    @Attribute(.unique) var id: String
    var familyId: String
    var ownerUid: String

    /// `"payslip"` | `"contract"`
    var kind: String
    var referenceDate: Date
    var fieldsEnc: String?

    /// `KBDocument` con il file originale (visibilità privata, tag `work:{uid}`).
    var attachmentDocumentId: String?

    var createdBy: String = ""
    var createdByName: String = ""
    var updatedBy: String = ""
    var updatedByName: String = ""
    var createdAt: Date
    var updatedAt: Date

    var isDeleted: Bool
    var syncStateRaw: Int
    var lastSyncError: String?

    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        ownerUid: String,
        ownerName: String,
        kind: String,
        referenceDate: Date,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.familyId = familyId
        self.ownerUid = ownerUid
        self.kind = kind
        self.referenceDate = referenceDate
        self.createdBy = ownerUid
        self.createdByName = ownerName
        self.updatedBy = ownerUid
        self.updatedByName = ownerName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = false
        self.syncStateRaw = KBSyncState.synced.rawValue
    }

    var isPayslip: Bool { kind == WorkRecordKind.payslip }
    var isContract: Bool { kind == WorkRecordKind.contract }
}

extension KBWorkRecord: HasFamilyId {}

enum WorkRecordKind {
    static let payslip = "payslip"
    static let contract = "contract"
}

// MARK: - Valori estratti

/// I valori letti da una busta paga o da un contratto. Un solo tipo per
/// entrambi: i campi che non c'entrano restano `nil`. Importi in euro, ferie
/// in giorni, permessi in ore, date come `yyyy-MM-dd`.
struct WorkFields: Codable, Equatable {
    var title: String = ""
    var employer: String = ""

    // Busta paga
    /// Mese di competenza come testo, es. «Settembre 2026».
    var period: String = ""
    var gross: Double?
    var net: Double?
    /// IRPEF e addizionali trattenute nel mese.
    var taxes: Double?
    /// Contributi previdenziali a carico del lavoratore.
    var contributions: Double?
    var vacationAccrued: Double?
    var vacationTaken: Double?
    var vacationRemaining: Double?
    var permitHoursAccrued: Double?
    var permitHoursRemaining: Double?
    var tfr: Double?

    // Contratto
    var contractType: String = ""
    var startDate: String?
    var endDate: String?
    /// Retribuzione annua lorda (RAL).
    var grossAnnual: Double?
    /// Livello e/o CCNL.
    var level: String = ""
    var noticePeriod: String = ""
    var vacationDaysPerYear: Double?

    var notes: String = ""

    static func parseDay(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    static func formatDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

/// Apre e chiude i campi di un `KBWorkRecord`. `nil` = la chiave di famiglia
/// non c'è o il blob non si apre: la UI lo dice invece di mostrare vuoto.
enum WorkRecordCrypto {
    static func open(_ record: KBWorkRecord, userId: String?) -> WorkFields? {
        guard let uid = userId, !uid.isEmpty,
              let b64 = record.fieldsEnc, !b64.isEmpty,
              let json = try? WalletCryptoService.decryptOptional(b64, familyId: record.familyId, userId: uid),
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(WorkFields.self, from: data)
    }

    static func seal(_ fields: WorkFields, into record: KBWorkRecord, userId: String) throws {
        let data = try JSONEncoder().encode(fields)
        let json = String(decoding: data, as: UTF8.self)
        record.fieldsEnc = try WalletCryptoService.encryptOptional(json, familyId: record.familyId, userId: userId)
    }

    static func openEmployer(_ profile: KBWorkProfile, userId: String?) -> String {
        guard let uid = userId, !uid.isEmpty else { return "" }
        return (try? WalletCryptoService.decryptOptional(profile.employerEnc, familyId: profile.familyId, userId: uid)) ?? ""
    }

    static func sealEmployer(_ employer: String, into profile: KBWorkProfile, userId: String) throws {
        profile.employerEnc = try WalletCryptoService.encryptOptional(employer, familyId: profile.familyId, userId: userId)
    }
}
