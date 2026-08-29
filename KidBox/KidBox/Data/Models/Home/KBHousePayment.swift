//
//  KBHousePayment.swift
//  KidBox
//

import Foundation
import SwiftData

/// Pagamento / scadenza domestica (`families/{familyId}/housePayments/{id}`).
@Model
final class KBHousePayment {

    @Attribute(.unique) var id: String
    var familyId: String

    var name: String
    /// `"mutuo"` | `"affitto"` | `"bolletta"` | `"tassa"` | `"altro"`
    var typeRaw: String
    var subtypeRaw: String?

    var importo: Double?
    /// Giorno del mese (1–31) per rate e bollette.
    var giornoDiScadenzaMensile: Int?
    var dataScadenza: Date?
    var dataScadenzaContratto: Date?
    var fornitore: String?
    var note: String?
    /// La spesa creata in Spese famiglia quando la scadenza ha un importo.
    var linkedExpenseId: String?

    var reminderOn: Bool

    var isDeleted: Bool

    var createdAt: Date
    var updatedAt: Date
    var createdBy: String
    var updatedBy: String

    var syncStateRaw: Int
    var lastSyncError: String?

    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        name: String,
        typeRaw: String,
        subtypeRaw: String? = nil,
        importo: Double? = nil,
        giornoDiScadenzaMensile: Int? = nil,
        dataScadenza: Date? = nil,
        dataScadenzaContratto: Date? = nil,
        fornitore: String? = nil,
        note: String? = nil,
        reminderOn: Bool = true,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdBy: String,
        updatedBy: String
    ) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.typeRaw = typeRaw
        self.subtypeRaw = subtypeRaw
        self.importo = importo
        self.giornoDiScadenzaMensile = giornoDiScadenzaMensile
        self.dataScadenza = dataScadenza
        self.dataScadenzaContratto = dataScadenzaContratto
        self.fornitore = fornitore
        self.note = note
        self.reminderOn = reminderOn
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}

extension KBHousePayment: HasFamilyId {}

extension KBHousePayment {

    /// Data di scadenza più prossima (o già passata) tra i campi impostati — per badge e ordinamento.
    func nextMonthlyDeadlineDisplay(from today: Date = Date()) -> Date? {
        guard let day = giornoDiScadenzaMensile else { return nil }
        return Self.nextMonthlyDueDay(day: day, from: today)
    }

    func nextAnnualDeadlineDisplay(from today: Date = Date()) -> Date? {
        guard let ref = dataScadenza else { return nil }
        return Self.nextAnnualOccurrence(reference: ref, from: today)
    }

    func earliestDisplayDeadline(from today: Date = Date()) -> Date? {
        let cal = Calendar.current
        let t0 = cal.startOfDay(for: today)
        var candidates: [Date] = []

        if let day = giornoDiScadenzaMensile,
           let d = Self.nextMonthlyDueDay(day: day, from: today) {
            candidates.append(cal.startOfDay(for: d))
        }
        if let ref = dataScadenza,
           let d = Self.nextAnnualOccurrence(reference: ref, from: today) {
            candidates.append(cal.startOfDay(for: d))
        }
        if let c = dataScadenzaContratto {
            candidates.append(cal.startOfDay(for: c))
        }

        guard !candidates.isEmpty else { return nil }
        return candidates.min()
    }

    private static func nextMonthlyDueDay(day: Int, from today: Date) -> Date? {
        let cal = Calendar.current
        let t0 = cal.startOfDay(for: today)
        guard let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: t0)) else { return nil }
        for offset in 0..<48 {
            guard let monthStart = cal.date(byAdding: .month, value: offset, to: startMonth) else { continue }
            guard let range = cal.range(of: .day, in: .month, for: monthStart) else { continue }
            let dom = min(max(1, day), range.count)
            var comps = cal.dateComponents([.year, .month], from: monthStart)
            comps.day = dom
            guard let candidate = cal.date(from: comps) else { continue }
            let c0 = cal.startOfDay(for: candidate)
            if c0 >= t0 { return candidate }
        }
        return nil
    }

    private static func nextAnnualOccurrence(reference: Date, from today: Date) -> Date? {
        let cal = Calendar.current
        let t0 = cal.startOfDay(for: today)
        let refMonth = cal.component(.month, from: reference)
        let refDay = cal.component(.day, from: reference)
        let startYear = cal.component(.year, from: today)

        for y in startYear...(startYear + 3) {
            var comps = DateComponents()
            comps.year = y
            comps.month = refMonth
            comps.day = 1
            guard let monthStart = cal.date(from: comps),
                  let range = cal.range(of: .day, in: .month, for: monthStart)
            else { continue }
            let dom = min(max(1, refDay), range.count)
            comps.day = dom
            guard let candidate = cal.date(from: comps) else { continue }
            let c0 = cal.startOfDay(for: candidate)
            if c0 >= t0 { return candidate }
        }
        return nil
    }
}

enum KidBoxHousePaymentType: String, CaseIterable {
    case mutuo
    case affitto
    case bolletta
    case tassa
    case altro

    var title: String {
        switch self {
        case .mutuo: return String(localized: "Mutuo")
        case .affitto: return String(localized: "Affitto")
        case .bolletta: return String(localized: "Bolletta")
        case .tassa: return String(localized: "Tassa")
        case .altro: return String(localized: "Altro")
        }
    }

    /// Sottotipi proposti dal form per questo tipo.
    ///
    /// `raw` è il valore **salvato** su Firestore e condiviso con Android: resta
    /// in italiano minuscolo e non va tradotto. `title` è solo l'etichetta a
    /// video. Unica fonte di verità per form, lista e dettaglio, così le tre
    /// schermate non possono divergere.
    var presetSubtypes: [(raw: String, title: String)] {
        switch self {
        case .bolletta:
            return [
                ("luce",       String(localized: "Luce")),
                ("gas",        String(localized: "Gas")),
                ("internet",   String(localized: "Internet")),
                ("telefono",   String(localized: "Telefono")),
                ("acqua",      String(localized: "Acqua")),
                ("condominio", String(localized: "Condominio")),
            ]
        case .tassa:
            return [
                ("IMU",  "IMU"),
                ("TARI", "TARI"),
                ("dichiarazione redditi", String(localized: "Dichiarazione redditi")),
                ("bollo auto",            String(localized: "Bollo auto")),
                ("altre",                 String(localized: "Altre")),
            ]
        case .mutuo, .affitto, .altro:
            return []
        }
    }

    /// Etichetta da mostrare per un sottotipo salvato: tradotta se è uno dei
    /// preset, altrimenti il testo libero scritto dall'utente.
    static func subtypeTitle(_ raw: String) -> String {
        for type in allCases {
            if let match = type.presetSubtypes.first(where: { $0.raw == raw }) { return match.title }
        }
        return raw
    }

    /// `true` se `raw` è un sottotipo predefinito di un tipo qualsiasi.
    ///
    /// Serve al form per non trascinarsi dietro il sottotipo quando si cambia
    /// tipo: senza questo controllo, scegliendo Mutuo restava attaccato il
    /// "luce" preimpostato da Bolletta e finiva salvato.
    static func isPresetSubtype(_ raw: String) -> Bool {
        allCases.contains { $0.presetSubtypes.contains { $0.raw == raw } }
    }
}

// MARK: - Bonifica dei sottotipi ereditati

extension KBHousePayment {

    /// Ripulisce i sottotipi rimasti attaccati da un tipo precedente.
    ///
    /// Il form partiva su Bolletta con `subtypeRaw = "luce"` e, cambiando tipo in
    /// Mutuo/Affitto/Altro, non lo azzerava: il valore finiva salvato e poi a
    /// video ("luce" su un mutuo). Il form è corretto, ma i record già scritti
    /// restano sporchi — qui si puliscono, e la modifica risale su Firestore così
    /// la correzione arriva anche agli altri dispositivi e ad Android.
    ///
    /// Si tocca solo un sottotipo che è **esattamente** un preset di un altro
    /// tipo: il testo libero scritto dall'utente non viene mai perso.
    @MainActor
    static func cleanupInheritedSubtypes(familyId: String, context: ModelContext) {
        let flagKey = "kb.housePayments.subtypeCleanup.\(familyId)"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let fid = familyId
        let descriptor = FetchDescriptor<KBHousePayment>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )
        let payments = (try? context.fetch(descriptor)) ?? []

        var fixed = 0
        for payment in payments {
            guard let raw = payment.subtypeRaw, !raw.isEmpty,
                  let type = KidBoxHousePaymentType(rawValue: payment.typeRaw),
                  type.presetSubtypes.isEmpty,
                  KidBoxHousePaymentType.isPresetSubtype(raw)
            else { continue }
            payment.subtypeRaw = nil
            payment.updatedAt = Date()
            SyncCenter.shared.enqueueHousePaymentUpsert(
                paymentId: payment.id, familyId: familyId, modelContext: context
            )
            fixed += 1
        }

        if fixed > 0 {
            try? context.save()
            SyncCenter.shared.flushGlobal(modelContext: context)
            KBLog.persistence.kbInfo("housePayments: ripuliti \(fixed) sottotipi ereditati familyId=\(familyId)")
        }
        UserDefaults.standard.set(true, forKey: flagKey)
    }
}
