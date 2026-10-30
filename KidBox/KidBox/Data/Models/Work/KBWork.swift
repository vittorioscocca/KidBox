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
    var isLeavePlan: Bool { kind == WorkRecordKind.leavePlan }
}

extension KBWorkRecord: HasFamilyId {}

enum WorkRecordKind {
    static let payslip = "payslip"
    static let contract = "contract"
    /// Foglio delle ferie e dei permessi programmati: ogni periodo diventa un
    /// evento di calendario visibile a tutta la famiglia.
    static let leavePlan = "leavePlan"
}

/// Un periodo di assenza letto dal foglio ferie. Date come `yyyy-MM-dd`;
/// un solo giorno = inizio e fine uguali.
struct WorkLeavePeriod: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: String
    var end: String
    /// «Ferie», «Permesso», «ROL»…
    var label: String
    /// L'utente ha scelto di metterlo nel calendario di famiglia (e l'evento
    /// esiste). In bozza parte acceso; nei documenti salvati prima è spento.
    var inCalendar: Bool = false
    /// L'evento di calendario creato per questo periodo: serve a spostarlo o
    /// revocarlo quando l'utente modifica il foglio.
    var eventId: String?

    private enum CodingKeys: String, CodingKey { case start, end, label, inCalendar, eventId }

    init(start: String, end: String, label: String, inCalendar: Bool = false, eventId: String? = nil) {
        self.start = start; self.end = end; self.label = label; self.inCalendar = inCalendar; self.eventId = eventId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = String(((try? c.decodeIfPresent(String.self, forKey: .start)) ?? "").prefix(10))
        let e = String(((try? c.decodeIfPresent(String.self, forKey: .end)) ?? "").prefix(10))
        start = s
        end = e.isEmpty ? s : e
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        inCalendar = ((try? c.decodeIfPresent(Bool.self, forKey: .inCalendar)) ?? nil) ?? false
        eventId = ((try? c.decodeIfPresent(String.self, forKey: .eventId)) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Il nome del periodo come finisce nel calendario: «Ferie» per le ferie
    /// (anche la sigla PAR del foglio), mai una sigla da sola.
    static func cleanLabel(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch t.lowercased() {
        case "", "par", "fer", "f", "ferie": return String(localized: "Ferie")
        case "rol": return String(localized: "Permesso (ROL)")
        case "mal", "m": return String(localized: "Malattia")
        default: return t.prefix(1).uppercased() + t.dropFirst()
        }
    }

    var startDay: Date? { WorkFields.parseDay(start) }
    var endDay: Date? { WorkFields.parseDay(end) ?? startDay }
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

    // Foglio ferie
    var leavePeriods: [WorkLeavePeriod] = []
    /// Eventi di calendario creati dal foglio: servono a toglierli se il
    /// documento viene eliminato.
    var eventIds: [String] = []

    init() {}

    /// Decodifica tollerante: la risposta del modello può omettere campi o
    /// mandare un importo come testo («1.234,56»).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func text(_ k: Key) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
        func day(_ k: Key) -> String? {
            guard let s = try? c.decodeIfPresent(String.self, forKey: k), !s.isEmpty else { return nil }
            return String(s.prefix(10))
        }
        func num(_ k: Key) -> Double? {
            if let d = try? c.decodeIfPresent(Double.self, forKey: k) { return d }
            guard let s = try? c.decodeIfPresent(String.self, forKey: k) else { return nil }
            let cleaned = s.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "")
            let normalized = cleaned.contains(",")
                ? cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                : cleaned
            return Double(normalized)
        }
        title = text(.title); employer = text(.employer); period = text(.period)
        gross = num(.gross); net = num(.net); taxes = num(.taxes); contributions = num(.contributions)
        vacationAccrued = num(.vacationAccrued); vacationTaken = num(.vacationTaken)
        vacationRemaining = num(.vacationRemaining)
        permitHoursAccrued = num(.permitHoursAccrued); permitHoursRemaining = num(.permitHoursRemaining)
        tfr = num(.tfr)
        contractType = text(.contractType); startDate = day(.startDate); endDate = day(.endDate)
        grossAnnual = num(.grossAnnual); level = text(.level); noticePeriod = text(.noticePeriod)
        vacationDaysPerYear = num(.vacationDaysPerYear)
        notes = text(.notes)
        leavePeriods = ((try? c.decodeIfPresent([WorkLeavePeriod].self, forKey: .leavePeriods)) ?? nil) ?? []
        eventIds = ((try? c.decodeIfPresent([String].self, forKey: .eventIds)) ?? nil) ?? []
    }

    private enum Key: String, CodingKey {
        case title, employer, period, gross, net, taxes, contributions
        case vacationAccrued, vacationTaken, vacationRemaining
        case permitHoursAccrued, permitHoursRemaining, tfr
        case contractType, startDate, endDate, grossAnnual, level, noticePeriod, vacationDaysPerYear, notes
        case leavePeriods, eventIds
    }

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
