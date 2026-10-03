//
//  NewsBriefBuilder.swift
//  KidBox
//
//  Il riassunto da cui partono le offerte su misura: bollette (Casa → scadenze
//  e pagamenti, più il testo letto delle bollette caricate) e lista della
//  spesa. Si costruisce sul telefono, l'unico posto in cui i dati sono in
//  chiaro, e parte solo quando l'utente tocca «Cerca offerte»: il server lo usa
//  per le ricerche e non lo salva.
//
//  Cosa esce: tipo di bolletta, fornitore, importo, scadenza del contratto e le
//  sole righe della bolletta che parlano di consumi e prezzi. Cosa non esce mai:
//  nomi, indirizzi, codici cliente, POD/PDR, IBAN, email — le righe che li
//  contengono si scartano e le cifre lunghe si mascherano. Stesse regole in
//  `NewsBriefBuilder.kt`.
//

import Foundation
import SwiftData

struct NewsBrief: Equatable {
    struct Bill: Equatable {
        var type: String
        var supplier: String?
        var amountEur: Double?
        var periodMonths: Int?
        var contractEnd: String?
        var excerpt: String?
    }

    var bills: [Bill]
    var grocery: [String]

    var isEmpty: Bool { bills.isEmpty && grocery.isEmpty }

    var dictionary: [String: Any] {
        [
            "bills": bills.map { b -> [String: Any] in
                var d: [String: Any] = ["type": b.type]
                if let v = b.supplier { d["supplier"] = v }
                if let v = b.amountEur { d["amountEur"] = v }
                if let v = b.periodMonths { d["periodMonths"] = v }
                if let v = b.contractEnd { d["contractEnd"] = v }
                if let v = b.excerpt { d["excerpt"] = v }
                return d
            },
            "grocery": grocery,
        ]
    }
}

@MainActor
enum NewsBriefBuilder {

    /// Le bollette che hanno un mercato o un bonus da cercare.
    private static let billTypes = ["luce", "gas", "acqua", "internet", "telefono"]

    static func build(familyId: String, uid: String?, context: ModelContext) -> NewsBrief {
        NewsBrief(bills: bills(familyId: familyId, uid: uid, context: context),
                  grocery: grocery(familyId: familyId, context: context))
    }

    // MARK: - Bollette

    private static func bills(familyId: String, uid: String?, context: ModelContext) -> [NewsBrief.Bill] {
        let fid = familyId
        let payments = (try? context.fetch(FetchDescriptor<KBHousePayment>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        ))) ?? []
        let documents = ((try? context.fetch(FetchDescriptor<KBDocument>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\KBDocument.updatedAt, order: .reverse)]
        ))) ?? []).filter { $0.isVisibleToCurrentUser(currentUid: uid) }

        var out: [NewsBrief.Bill] = []
        var usedDocIds = Set<String>()
        for p in payments where p.typeRaw.lowercased() == "bolletta" {
            guard let type = p.subtypeRaw?.lowercased(), billTypes.contains(type) else { continue }
            let attached = documents.first { ($0.notes ?? "").contains("housePayment:\(p.id)") && !($0.extractedText ?? "").isEmpty }
            if let attached { usedDocIds.insert(attached.id) }
            out.append(NewsBrief.Bill(
                type: type,
                supplier: clean(p.fornitore, max: 40),
                amountEur: p.importo.flatMap { $0 > 0 ? $0 : nil },
                periodMonths: p.giornoDiScadenzaMensile != nil ? 1 : nil,
                contractEnd: p.dataScadenzaContratto.map(NewsDates.key),
                excerpt: attached.flatMap { excerpt(from: $0.extractedText) }
            ))
        }
        // Bollette caricate in Documenti senza una scadenza in Casa: si
        // riconoscono dal testo letto, al massimo una per tipo.
        let yearAgo = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        for doc in documents where doc.updatedAt >= yearAgo && !usedDocIds.contains(doc.id) {
            guard let text = doc.extractedText, text.count > 80, let type = classify(text) else { continue }
            guard !out.contains(where: { $0.type == type }) else { continue }
            out.append(NewsBrief.Bill(
                type: type,
                supplier: supplier(in: text),
                amountEur: nil,
                periodMonths: nil,
                contractEnd: nil,
                excerpt: excerpt(from: text)
            ))
            if out.count >= 6 { break }
        }
        return Array(out.prefix(6))
    }

    /// Luce, gas o acqua dal testo di una bolletta; nil se non lo è.
    static func classify(_ text: String) -> String? {
        let t = text.lowercased()
        let isBill = t.contains("bolletta") || t.contains("fattura") || t.contains("facture") || t.contains("factura") || t.contains("bill")
        guard isBill else { return nil }
        if t.contains("kwh") && (t.contains("pod") || t.contains("energia elettrica") || t.contains("électricité") || t.contains("electricidad") || t.contains("luce")) { return "luce" }
        if t.contains("smc") || (t.contains("pdr") && t.contains("gas")) || t.contains("gas naturale") || t.contains("gaz naturel") { return "gas" }
        if (t.contains("m3") || t.contains("m³") || t.contains(" mc ")) && (t.contains("acqua") || t.contains("idric") || t.contains("eau") || t.contains("agua")) { return "acqua" }
        return nil
    }

    private static let knownSuppliers = [
        "Enel", "Servizio Elettrico Nazionale", "A2A", "Edison", "Hera", "Iren", "Eni Plenitude", "Plenitude", "Sorgenia",
        "Acea", "Engie", "Illumia", "Octopus", "Iberdrola", "E.ON", "Axpo", "Wekiwi", "NeN", "Pulsee", "Dolomiti Energia",
        "Estra", "Optima", "Enegan", "Alperia", "AGSM", "Tate", "Metamer",
        "EDF", "TotalEnergies", "Ekwateur", "Mint Énergie", "Vattenfall",
        "Endesa", "Naturgy", "Repsol", "Holaluz",
    ]

    private static func supplier(in text: String) -> String? {
        knownSuppliers.first { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Le sole righe con consumi e prezzi, ripulite dai dati personali.
    static func excerpt(from text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let keep = ["kwh", "smc", "m3", "m³", "€/", "eur/", "prezzo", "quota fissa", "quota energia", "consum", "potenza",
                    "offerta", "tariffa", "f1", "f2", "f3", "spesa per", "totale", "periodo", "prix", "consommation", "abonnement",
                    "precio", "consumo", "término"]
        let drop = ["intestat", "cliente", "codice", "pod", "pdr", "iban", "indirizzo", "via ", "piazza", "c.f.", "codice fiscale",
                    "titulaire", "adresse", "titular", "dirección", "@", "sig.", "sig.ra", "nome"]
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count >= 6, line.count <= 160 else { continue }
            let low = line.lowercased()
            guard keep.contains(where: low.contains), !drop.contains(where: low.contains) else { continue }
            lines.append(mask(line))
            if lines.joined(separator: "; ").count > 560 { break }
        }
        let joined = lines.joined(separator: "; ")
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(600))
    }

    /// Cifre lunghe (codici, contratti, conti) e sigle alfanumeriche lunghe
    /// diventano «…»: i consumi restano, perché hanno separatori o sono corti.
    static func mask(_ line: String) -> String {
        var s = line.replacingOccurrences(of: #"\b\d{7,}\b"#, with: "…", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{10,}\b"#, with: "…", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[\w.+-]+@[\w-]+\.[\w.]+"#, with: "…", options: .regularExpression)
        return s
    }

    // MARK: - Spesa

    private static func grocery(familyId: String, context: ModelContext) -> [String] {
        let fid = familyId
        let items = (try? context.fetch(FetchDescriptor<KBGroceryItem>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\KBGroceryItem.updatedAt, order: .reverse)]
        ))) ?? []
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        var names: [String] = []
        for item in items where !item.isPurchased || (item.purchasedAt ?? .distantPast) >= monthAgo {
            guard let name = clean(item.name, max: 40), !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            names.append(name)
            if names.count >= 30 { break }
        }
        return names
    }

    private static func clean(_ s: String?, max: Int) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return String(t.prefix(max))
    }
}
