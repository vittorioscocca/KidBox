//
//  SectionCrypto.swift
//  KidBox
//
//  Cifratura delle sezioni (Garage, Animali, Spese, Salute) con la chiave di
//  famiglia. Specifica: `internal/cifratura-sezioni.md`.
//
//  Un solo campo in più per documento: `secure` = base64(AES-GCM combined) di
//  un JSON `{"campo": "valore"}` (formato delle note), più `secureV: 1`.
//
//  - Lettura (sempre): il chiaro non vuoto vince, altrimenti il valore in
//    `secure`. Se `secure` non si apre restano i valori in chiaro.
//  - Scrittura: solo con `sections_encryption_enabled` acceso e la chiave in
//    mano; i campi della tabella vanno a "" (non cancellati: le build vecchie li
//    vogliono) e il valore in `secure`. Altrimenti in chiaro come sempre.
//  - Ricifratura: un documento con chiaro non vuoto letto dal listener si
//    riscrive in merge con solo `secure`, `secureV` e i campi a "", senza
//    toccare `updatedAt`/`updatedBy`. Una volta per documento per sessione.
//
//  Gemello Android e web: stessa tabella, stesso formato.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum SectionCrypto {

    // MARK: - Tabella dei campi (unica, identica sui tre client)

    enum Section: String, CaseIterable {
        case vehicles
        case vehicleEvents
        case pets
        case petEvents
        case expenses
        case medicalVisits
        case medicalExams
        case treatments
        case vaccines
        case pediatricProfiles

        /// Campi stringa che finiscono in `secure`.
        var fields: [String] {
            switch self {
            case .vehicles:          return ["name", "licensePlate", "brand", "model", "color", "vin", "notes"]
            case .vehicleEvents:     return ["title", "garageName", "notes"]
            case .pets:              return ["name", "breed", "color", "chipCode", "notes"]
            case .petEvents:         return ["title", "vetName", "notes"]
            case .expenses:          return ["title", "notes"]
            case .medicalVisits:     return ["doctorName", "reason", "diagnosis", "recommendations", "notes", "nextVisitReason"]
            case .medicalExams:      return ["name", "preparation", "location", "resultText", "notes"]
            case .treatments:        return ["drugName", "activeIngredient", "notes"]
            case .vaccines:          return ["commercialName", "lotNumber", "administeredBy", "notes"]
            case .pediatricProfiles: return ["bloodGroup", "allergies", "medicalNotes", "doctorName", "doctorPhone",
                                             "doctorEmail", "doctorAddress", "doctorWebsite",
                                             "doctorOfficeHoursJSON", "emergencyContactsJSON"]
            }
        }
    }

    static let secureKey = "secure"
    static let versionKey = "secureV"
    static let currentVersion = 1

    // MARK: - Regole pure (testabili senza Keychain né Firestore)

    /// Regola di lettura: per ogni campo il chiaro non vuoto vince, altrimenti
    /// il valore in `secure`. Blob assente o che non si apre: dati invariati.
    static func resolve(_ data: [String: Any], fields: [String], decrypt: (String) -> String?) -> [String: Any] {
        guard let blob = data[secureKey] as? String, !blob.isEmpty,
              let json = decrypt(blob),
              let map = decodeMap(json) else { return data }
        var out = data
        for field in fields where !isNonEmptyString(data[field]) {
            if let v = map[field], !v.isEmpty { out[field] = v }
        }
        return out
    }

    /// Sposta i campi della tabella in `secure` e li mette a "". Un campo che
    /// `data` non scrive prende il valore da `existing` (già risolto), così il
    /// blob non perde ciò che questa scrittura non tocca. Nil se la cifratura fallisce.
    static func sealed(_ data: [String: Any], fields: [String], existing: [String: Any]?,
                       encrypt: (String) -> String?) -> [String: Any]? {
        var values: [String: String] = [:]
        for field in fields {
            if let raw = data[field] {
                // nil, NSNull e FieldValue.delete() = campo vuoto: si omette.
                if let s = raw as? String, !s.isEmpty { values[field] = s }
            } else if let s = existing?[field] as? String, !s.isEmpty {
                values[field] = s
            }
        }
        guard let blob = encrypt(encodeMap(values)) else { return nil }
        var out = data
        for field in fields { out[field] = "" }
        out[secureKey] = blob
        out[versionKey] = currentVersion
        return out
    }

    /// Il documento ha un blob `secure`: un nome vuoto non vuol dire documento rotto.
    static func isSealed(_ data: [String: Any]) -> Bool {
        (data[secureKey] as? String).map { !$0.isEmpty } ?? false
    }

    static func hasPlainValues(_ data: [String: Any], fields: [String]) -> Bool {
        fields.contains { isNonEmptyString(data[$0]) }
    }

    private static func isNonEmptyString(_ value: Any?) -> Bool {
        guard let s = value as? String else { return false }
        return !s.isEmpty
    }

    private static func encodeMap(_ map: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private static func decodeMap(_ json: String) -> [String: String]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj.compactMapValues { $0 as? String }
    }

    // MARK: - Chiave di famiglia

    private static var uid: String? { Auth.auth().currentUser?.uid }

    /// families/{familyId}/<sezione>/{id} → familyId.
    static func familyId(of ref: DocumentReference) -> String? {
        ref.parent.parent?.documentID
    }

    private static func canSeal(familyId: String) -> String? {
        guard KBFeatureFlags.isSectionsEncryptionEnabled,
              let uid, !uid.isEmpty,
              FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: uid) != nil else { return nil }
        return uid
    }

    // MARK: - Lettura

    /// Dati del documento con i campi della sezione risolti.
    static func open(_ data: [String: Any], _ section: Section, familyId: String) -> [String: Any] {
        guard isSealed(data) else { return data }
        let uid = self.uid ?? ""
        return resolve(data, fields: section.fields) {
            try? NoteCryptoService.decryptString($0, familyId: familyId, userId: uid)
        }
    }

    /// Lettura di uno snapshot. `reencrypt` solo dai listener: a interruttore
    /// acceso riscrive cifrato il documento che ha ancora campi in chiaro.
    static func read(_ doc: DocumentSnapshot, _ section: Section, reencrypt: Bool = false) -> [String: Any] {
        let raw = doc.data() ?? [:]
        guard let fid = familyId(of: doc.reference) else { return raw }
        let resolved = open(raw, section, familyId: fid)
        if reencrypt {
            reencryptIfNeeded(raw: raw, resolved: resolved, section, ref: doc.reference, familyId: fid)
        }
        return resolved
    }

    // MARK: - Scrittura

    /// Dizionario da scrivere: cifrato se interruttore e chiave lo permettono,
    /// altrimenti invariato. `existing` = dati del documento se già letti; se
    /// manca e `data` non scrive tutti i campi, il documento si rilegge.
    static func seal(_ data: [String: Any], _ section: Section, ref: DocumentReference,
                     existing: [String: Any]? = nil) async -> [String: Any] {
        guard let fid = familyId(of: ref), let uid = canSeal(familyId: fid) else { return data }
        var previous = existing.map { open($0, section, familyId: fid) }
        if previous == nil, section.fields.contains(where: { data[$0] == nil }) {
            // Senza il documento attuale si perderebbero i campi non riscritti:
            // meglio il chiaro di un blob monco.
            guard let snap = try? await ref.getDocument() else { return data }
            previous = open(snap.data() ?? [:], section, familyId: fid)
        }
        return sealed(data, fields: section.fields, existing: previous) {
            try? NoteCryptoService.encryptString($0, familyId: fid, userId: uid)
        } ?? data
    }

    // MARK: - Ricifratura

    private static var reencrypted = Set<String>()

    private static func reencryptIfNeeded(raw: [String: Any], resolved: [String: Any], _ section: Section,
                                          ref: DocumentReference, familyId: String) {
        guard hasPlainValues(raw, fields: section.fields),
              let uid = canSeal(familyId: familyId) else { return }
        // `secure` presente ma illeggibile: non si sovrascrivono valori che non conosciamo.
        if let blob = raw[secureKey] as? String, !blob.isEmpty,
           (try? NoteCryptoService.decryptString(blob, familyId: familyId, userId: uid)) == nil {
            return
        }
        guard reencrypted.insert(ref.path).inserted else { return }
        guard let update = sealed([:], fields: section.fields, existing: resolved, encrypt: {
            try? NoteCryptoService.encryptString($0, familyId: familyId, userId: uid)
        }) else { return }
        ref.setData(update, merge: true) { err in
            if let err {
                KBLog.sync.kbError("[SectionCrypto] ricifratura fallita \(section.rawValue) id=\(ref.documentID) err=\(err.localizedDescription)")
            } else {
                KBLog.sync.kbInfo("[SectionCrypto] ricifrato \(section.rawValue) id=\(ref.documentID)")
            }
        }
    }
}
