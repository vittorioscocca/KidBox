//
//  KBWalletDocumentKind.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//

import Foundation
import SwiftUI
import FirebaseAuth

/// Categoria dei documenti d'identità acquisiti dalla sezione "Documenti" del
/// Wallet (Tessera Sanitaria, Carta d'identità/CIE, Patente, Passaporto, ecc.).
///
/// Non introduce un nuovo modello SwiftData: i documenti restano `KBDocument`
/// come nel resto dell'app. Kind + metadati (Codice Fiscale, data di rilascio/
/// scadenza, preferenza notifica) sono codificati nel campo `notes` — già
/// usato altrove come tag libero, es. `"treatment:{id}"` — tramite
/// `KBWalletDocumentMetadata`, così il Wallet resta un filtro sopra
/// `KBDocument` senza toccare lo schema/sync esistente.
enum KBWalletDocumentKind: String, CaseIterable, Identifiable {
    case tesseraSanitaria
    case cartaIdentita
    case cie
    case passaporto
    case codiceFiscale
    case patente
    case altro

    var id: String { rawValue }

    static let notesPrefix = "kb_wallet_doc:"

    /// `String` (non `LocalizedStringKey`): assegnato a campi form `String` e
    /// confrontato con `==` (per capire se l'utente ha modificato il titolo
    /// auto-compilato), quindi passa da NSLocalizedString.
    var displayName: String {
        switch self {
        case .tesseraSanitaria: return NSLocalizedString("Tessera Sanitaria", comment: "Document kind")
        case .cartaIdentita:    return NSLocalizedString("Carta d'identità (cartacea)", comment: "Document kind")
        case .cie:              return NSLocalizedString("CIE (Carta d'identità elettronica)", comment: "Document kind")
        case .passaporto:       return NSLocalizedString("Passaporto", comment: "Document kind")
        case .codiceFiscale:    return NSLocalizedString("Codice Fiscale", comment: "Document kind")
        case .patente:          return NSLocalizedString("Patente", comment: "Document kind")
        case .altro:            return NSLocalizedString("Documento", comment: "Document kind")
        }
    }

    var systemImage: String {
        switch self {
        case .tesseraSanitaria: return "cross.case.fill"
        case .cartaIdentita:    return "person.text.rectangle.fill"
        case .cie:              return "person.crop.rectangle.fill"
        case .passaporto:       return "book.closed.fill"
        case .codiceFiscale:    return "number.square.fill"
        case .patente:          return "car.fill"
        case .altro:            return "doc.text.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .tesseraSanitaria: return Color(red: 0.13, green: 0.55, blue: 0.45) // verde sanità
        case .cartaIdentita:    return Color(red: 0.16, green: 0.35, blue: 0.62)
        case .cie:              return Color(red: 0.20, green: 0.45, blue: 0.70)
        case .passaporto:       return Color(red: 0.30, green: 0.20, blue: 0.55)
        case .codiceFiscale:    return Color(red: 0.55, green: 0.42, blue: 0.15)
        case .patente:          return Color(red: 0.86, green: 0.45, blue: 0.62)  // rosa patente
        case .altro:            return Color(red: 0.35, green: 0.35, blue: 0.42)
        }
    }

    /// Secondo colore del gradient (versione scurita), per la card in stile Wallet.
    var accentColorSecondary: Color {
        switch self {
        case .tesseraSanitaria: return Color(red: 0.06, green: 0.32, blue: 0.26)
        case .cartaIdentita:    return Color(red: 0.08, green: 0.19, blue: 0.36)
        case .cie:              return Color(red: 0.09, green: 0.24, blue: 0.42)
        case .passaporto:       return Color(red: 0.15, green: 0.09, blue: 0.32)
        case .codiceFiscale:    return Color(red: 0.30, green: 0.22, blue: 0.06)
        case .patente:          return Color(red: 0.62, green: 0.24, blue: 0.42)  // rosa scuro
        case .altro:            return Color(red: 0.18, green: 0.18, blue: 0.22)
        }
    }

    /// Tag minimo (solo kind, senza metadati) da salvare in `KBDocument.notes`.
    /// Preferire `KBWalletDocumentMetadata.encoded` quando sono disponibili
    /// anche Codice Fiscale/date/preferenza notifica.
    var notesTag: String { Self.notesPrefix + rawValue }
}

/// Categoria di patente (A, B, C, ...) con le sue date di rilascio e scadenza:
/// sulla patente italiana ogni categoria ha date proprie (colonne 10/11 sul retro).
struct KBPatenteCategory: Equatable, Identifiable {
    var id = UUID()
    var code: String
    var issueDate: Date?
    var expiryDate: Date?
}

/// Metadati del documento Wallet codificati in `KBDocument.notes`:
/// `kb_wallet_doc:<kind>|enc=<base64 AES-GCM>`, dove il blob cifrato contiene
/// tutti i campi sensibili (Codice Fiscale, nome, nascita, numero documento,
/// date, categorie patente) cifrati con la chiave di famiglia
/// (`WalletCryptoService`/`FamilyKeychainStore`, la stessa che protegge il PDF).
/// Solo il `kind` resta in chiaro nel prefisso (serve per filtrare/mostrare
/// l'icona senza decifrare). `notes` è lo stesso campo sincronizzato su
/// Firestore per `KBDocument`: cifrandone il contenuto qui, i metadati Wallet
/// risultano protetti sia in locale (SwiftData) sia lato Firebase.
/// Retrocompatibile con il vecchio formato in chiaro (`cf=...|holder=...`)
/// salvato dalle prime versioni della feature.
struct KBWalletDocumentMetadata: Equatable {
    var kind: KBWalletDocumentKind
    var codiceFiscale: String?
    /// Nome e cognome del titolare, letti dal documento (OCR) o inseriti a mano.
    var holderName: String?
    /// Data e luogo di nascita (campo 3 della patente), testo libero.
    var birthInfo: String?
    /// Numero/codice del documento (numero carta, numero passaporto, ecc.).
    var documentNumber: String?
    var issueDate: Date?
    var expiryDate: Date?
    /// Solo per la patente: date di rilascio/scadenza per categoria (A, B, C, ...).
    var patenteCategories: [KBPatenteCategory] = []
    /// Notifica locale una settimana prima della scadenza. Default `true`.
    var notifyBeforeExpiry: Bool = true

    /// Scadenza effettiva usata per il promemoria: per la patente è la più
    /// imminente tra le categorie; altrimenti la scadenza singola.
    var effectiveExpiryDate: Date? {
        if kind == .patente {
            return patenteCategories.compactMap(\.expiryDate).min()
        }
        return expiryDate
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `|` e `=` sono i separatori del formato in `notes`: li rimuoviamo dai
    /// valori testuali liberi (nome, numero documento) per non romperlo.
    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "=", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Payload testuale (pipe-delimited) con tutti i campi sensibili, da cifrare.
    private var sensitivePayload: String {
        var parts: [String] = []
        if let codiceFiscale, !codiceFiscale.isEmpty {
            parts.append("cf=\(Self.sanitize(codiceFiscale))")
        }
        if let holderName, !holderName.isEmpty {
            parts.append("holder=\(Self.sanitize(holderName))")
        }
        if let birthInfo, !birthInfo.isEmpty {
            parts.append("birth=\(Self.sanitize(birthInfo))")
        }
        if let documentNumber, !documentNumber.isEmpty {
            parts.append("docnum=\(Self.sanitize(documentNumber))")
        }
        if let issueDate {
            parts.append("issue=\(Self.dateFormatter.string(from: issueDate))")
        }
        if let expiryDate {
            parts.append("expiry=\(Self.dateFormatter.string(from: expiryDate))")
        }
        if !patenteCategories.isEmpty {
            // cats=<code>~<issue>~<expiry>;<code>~<issue>~<expiry>...  (date vuote ammesse)
            let encodedCats = patenteCategories.compactMap { cat -> String? in
                let code = cat.code
                    .replacingOccurrences(of: "|", with: "")
                    .replacingOccurrences(of: "=", with: "")
                    .replacingOccurrences(of: ";", with: "")
                    .replacingOccurrences(of: "~", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                guard !code.isEmpty else { return nil }
                let issue = cat.issueDate.map { Self.dateFormatter.string(from: $0) } ?? ""
                let expiry = cat.expiryDate.map { Self.dateFormatter.string(from: $0) } ?? ""
                return "\(code)~\(issue)~\(expiry)"
            }.joined(separator: ";")
            if !encodedCats.isEmpty { parts.append("cats=\(encodedCats)") }
        }
        parts.append("notify=\(notifyBeforeExpiry ? "1" : "0")")
        return parts.joined(separator: "|")
    }

    /// Codifica per `KBDocument.notes`: kind in chiaro + payload cifrato con la
    /// chiave della famiglia. Se la cifratura fallisce (es. chiave non ancora
    /// disponibile su questo device) salva in chiaro come fallback, per non
    /// perdere i dati appena inseriti dall'utente.
    func encoded(familyId: String, userId: String) -> String {
        let prefix = KBWalletDocumentKind.notesPrefix + kind.rawValue
        let payload = sensitivePayload
        guard !payload.isEmpty else { return prefix }
        guard let encryptedB64 = try? WalletCryptoService.encryptString(payload, familyId: familyId, userId: userId) else {
            return prefix + "|" + payload
        }
        return prefix + "|enc=" + encryptedB64
    }

    static func parse(_ notes: String?, familyId: String, userId: String) -> KBWalletDocumentMetadata? {
        guard let notes, notes.hasPrefix(KBWalletDocumentKind.notesPrefix) else { return nil }
        let segments = notes.components(separatedBy: "|")
        guard let first = segments.first else { return nil }
        let rawKind = String(first.dropFirst(KBWalletDocumentKind.notesPrefix.count))
        guard let kind = KBWalletDocumentKind(rawValue: rawKind) else { return nil }

        var metadata = KBWalletDocumentMetadata(kind: kind)
        let rest = Array(segments.dropFirst())

        // Nuovo formato: un unico segmento "enc=<base64>" con tutto cifrato.
        if let encSegment = rest.first(where: { $0.hasPrefix("enc=") }) {
            let b64 = String(encSegment.dropFirst("enc=".count))
            guard let decrypted = try? WalletCryptoService.decryptString(b64, familyId: familyId, userId: userId) else {
                // Chiave non disponibile su questo device (o altro errore): il
                // documento resta identificabile (kind) ma i campi sensibili no.
                return metadata
            }
            applyFields(from: decrypted, to: &metadata)
            return metadata
        }

        // Retrocompatibilità: vecchio formato con i campi in chiaro dopo il kind.
        applyFields(from: rest.joined(separator: "|"), to: &metadata)
        return metadata
    }

    private static func applyFields(from payload: String, to metadata: inout KBWalletDocumentMetadata) {
        for segment in payload.components(separatedBy: "|") {
            let kv = segment.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "cf":     metadata.codiceFiscale = kv[1]
            case "holder": metadata.holderName = kv[1]
            case "birth":  metadata.birthInfo = kv[1]
            case "docnum": metadata.documentNumber = kv[1]
            case "issue":  metadata.issueDate = dateFormatter.date(from: kv[1])
            case "expiry": metadata.expiryDate = dateFormatter.date(from: kv[1])
            case "cats":   metadata.patenteCategories = parseCategories(kv[1])
            case "notify": metadata.notifyBeforeExpiry = kv[1] == "1"
            default: break
            }
        }
    }

    private static func parseCategories(_ raw: String) -> [KBPatenteCategory] {
        raw.split(separator: ";").compactMap { entry in
            let f = entry.split(separator: "~", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard let code = f.first, !code.isEmpty else { return nil }
            let issue = f.count > 1 && !f[1].isEmpty ? dateFormatter.date(from: f[1]) : nil
            let expiry = f.count > 2 && !f[2].isEmpty ? dateFormatter.date(from: f[2]) : nil
            return KBPatenteCategory(code: code, issueDate: issue, expiryDate: expiry)
        }
    }
}

extension KBDocument {
    /// Metadati Wallet completi (kind + CF + date + preferenza notifica), se
    /// `notes` contiene il tag dedicato. Decifra automaticamente con la chiave
    /// della famiglia del documento e l'utente corrente.
    var walletMetadata: KBWalletDocumentMetadata? {
        get {
            let uid = Auth.auth().currentUser?.uid ?? "local"
            return KBWalletDocumentMetadata.parse(notes, familyId: familyId, userId: uid)
        }
        set {
            let uid = Auth.auth().currentUser?.uid ?? "local"
            notes = newValue?.encoded(familyId: familyId, userId: uid)
        }
    }

    /// Kind del documento Wallet, se presente. Comodo per la UI quando non
    /// servono gli altri metadati (card, icone, filtri).
    var walletDocumentKind: KBWalletDocumentKind? {
        walletMetadata?.kind
    }
}
